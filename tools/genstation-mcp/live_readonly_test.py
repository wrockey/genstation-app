#!/usr/bin/env python3
"""Exercise the real app through its signed MCP helper without valid generation calls.
No preference changes, asset sharing, provider calls, or approval clicks.
Usage: live_readonly_test.py /path/to/genstation-mcp
The app must already be running; helper auto-launch is disabled.
"""
import base64
import json
import os
import selectors
import socket
import struct
import subprocess
import sys
import uuid
import zlib


def png_fixture():
    def chunk(kind, payload):
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
    raw = b''.join(b'\0' + b'\x30\x80\xd0' * 16 for _ in range(16))
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 16, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
    return 'data:image/png;base64,' + base64.b64encode(data).decode()


class Client:
    def __init__(self, helper):
        env = dict(os.environ)
        env.setdefault('GENSTATION_MCP_SOCKET', os.path.expanduser('~/Library/Containers/art.genstation.app/Data/Library/Application Support/art.genstation.app/mcp.sock'))
        self.process = subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env)
        self.reader = selectors.DefaultSelector()
        self.reader.register(self.process.stdout, selectors.EVENT_READ)
        self.next_id = 0

    def rpc(self, method, params=None):
        self.next_id += 1
        message = {'jsonrpc': '2.0', 'id': self.next_id, 'method': method, 'params': params or {}}
        self.process.stdin.write((json.dumps(message) + '\n').encode())
        self.process.stdin.flush()
        if not self.reader.select(timeout=20):
            raise RuntimeError('Timed out waiting for ' + method)
        reply = json.loads(self.process.stdout.readline())
        assert reply.get('id') == self.next_id, 'response ID mismatch'
        return reply

    def tool(self, name, args=None):
        result = self.rpc('tools/call', {'name': name, 'arguments': args or {}})['result']
        content = result['structuredContent']
        assert json.loads(result['content'][0]['text']) == content, 'structured/text mismatch'
        return content, bool(result.get('isError'))

    def close(self):
        self.process.stdin.close()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            self.process.wait(timeout=3)
        self.reader.close()


def main():
    client = Client(sys.argv[1])
    outcomes = []

    def check(name, condition, detail=''):
        outcomes.append((name, bool(condition)))
        print(('PASS ' if condition else 'FAIL ') + name + ((': ' + str(detail)) if not condition else ''), flush=True)

    def valid(name, args):
        data, error = client.tool('validate_image_request', args)
        check(name, not error and data.get('valid') and data.get('network_requests') == 0, data)

    def invalid(name, args, tool='validate_image_request'):
        data, error = client.tool(tool, args)
        check(name, error and data.get('error', {}).get('code') == 'invalid_params', data)

    try:
        init = client.rpc('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': 'genstation-live-readonly', 'version': '1'}})['result']
        check('MCP version 2.1.7', init['serverInfo']['version'] == '2.1.7')
        check('connection instructions include replay rules', 'request_id' in init.get('instructions', '') and 'IDENTICAL' in init.get('instructions', ''))
        resources = client.rpc('resources/list')['result']['resources']
        check('workflow resource advertised', len(resources) == 1 and resources[0]['uri'] == 'genstation://docs/image-workflow')
        guide = client.rpc('resources/read', {'uri': resources[0]['uri']})['result']['contents'][0]
        check('workflow resource readable', guide['mimeType'] == 'text/markdown' and '## Example' in guide['text'] and 'insufficient_credits' in guide['text'])
        tools = client.rpc('tools/list')['result']['tools']
        check('twenty-two advertised tools', len(tools) == 22)
        status, error = client.tool('connection_status')
        check('live app supports workflow 2.1', not error and status.get('workflow_version') == '2.1', status)
        if error:
            return 1
        check('durable storage ready', status.get('storage_ready'))
        check('individual approval with unknown prices', status.get('approval') == 'individual_request' and status.get('price_status') == 'unknown')
        print('Configured providers: ' + ', '.join(k for k, v in status['providers'].items() if v), flush=True)
        models, error = client.tool('list_models', {'type': 'image'})
        check('image discovery', not error and models.get('count', 0) > 0 and all(not m['is_video'] for m in models['models']))
        for provider in ['aimlapi', 'gemini', 'grok']:
            filtered, error = client.tool('list_models', {'type': 'image', 'provider': provider})
            check(provider + ' discovery filter', not error and filtered.get('count', 0) > 0 and all(m['provider'] == provider for m in filtered['models']))
        videos, error = client.tool('list_models', {'type': 'video'})
        check('video discovery filter', not error and videos.get('count', 0) > 0 and all(m['is_video'] for m in videos['models']))
        invalid('reject invalid discovery type', {'type': 'invalid'}, 'list_models')
        invalid('reject video without model before approval', {'prompt': 'Local invalid-request check'}, 'generate_video')
        fixture = png_fixture()
        for model in models['models']:
            args = {'provider': model['provider'], 'model': model['id'], 'prompt': 'A blue ceramic lighthouse. Local validation only.', 'params': {}}
            if model['requires_input_image']:
                args['input_images'] = [fixture]
            valid('default request ' + model['provider'] + '/' + model['id'], args)
            if model['max_input_images']:
                valid('image input ' + model['provider'] + '/' + model['id'], dict(args, input_images=[fixture]))
            for key, schema in model['parameter_schema']['properties'].items():
                for value in schema.get('enum', []):
                    valid('published option ' + model['provider'] + '/' + model['id'] + ' ' + key + '=' + str(value), dict(args, params={key: value}))
        base = {'provider': 'gemini', 'model': 'gemini-2.5-flash-image', 'prompt': 'Local validation test'}
        invalid('reject missing provider', {'model': base['model'], 'prompt': base['prompt']})
        invalid('reject private parameter', dict(base, params={'api_key': 'fixture-not-a-real-key'}))
        invalid('reject top-level credential', dict(base, api_key='fixture-not-a-real-key'))
        invalid('reject malformed params', dict(base, params=[]))
        invalid('reject malformed input list', dict(base, input_images='not-an-array'))
        invalid('reject arbitrary file path', dict(base, input_images=['/tmp/unshared-test.png']))
        invalid('reject arbitrary HTTPS input', dict(base, input_images=['https://example.invalid/test.png']))
        invalid('reject invalid image bytes', dict(base, input_images=['data:image/png;base64,YQ==']))
        invalid('reject invalid enum', dict(base, params={'aspect_ratio': '500:1'}))
        invalid('reject wrong scalar type', dict(base, params={'aspect_ratio': True}))
        invalid('reject unshared asset reference', dict(base, input_images=['asset:' + str(uuid.uuid4())]))
        invalid('reject unknown asset lookup', {'asset_id': str(uuid.uuid4())}, 'get_asset')
        invalid('reject unknown job lookup', {'job_id': str(uuid.uuid4())}, 'get_job_status')
        invalid('reject submission without request identity', base, 'generate_image')
        invalid('reject invalid submission before registration', dict(base, request_id='invalid-' + str(uuid.uuid4()), input_images=['/tmp/not-shared.png']), 'generate_image')
        assets, error = client.tool('list_assets')
        check('scoped asset listing', not error and isinstance(assets.get('assets'), list) and len(assets['assets']) <= 100)
        check('asset listing exposes no prompts or payloads', all(set(a) <= {'asset_id', 'model', 'created_at', 'media_kind', 'parent_folder_id'} for a in assets.get('assets', [])))
        # A second helper connection exercises real peer authentication and reconnect.
        another = Client(sys.argv[1])
        try:
            result, error = another.tool('connection_status')
            check('second signed-helper connection', not error and result.get('workflow_version') == '2.1')
        finally:
            another.close()
        if status.get('app_flavor') == 'demo':
            address = os.path.expanduser('~/Library/Containers/art.genstation.demo/Data/Library/Application Support/art.genstation.demo/mcp.sock')
        else:
            address = os.environ.get('GENSTATION_MCP_SOCKET', os.path.expanduser('~/Library/Containers/art.genstation.app/Data/Library/Application Support/art.genstation.app/mcp.sock'))
        raw = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        raw.settimeout(3)
        original_directory = os.open('.', os.O_RDONLY)
        try:
            # macOS sockaddr_un has a short pathname limit; use the helper's relative-path approach.
            os.chdir(os.path.dirname(address))
            raw.connect(os.path.basename(address))
            try:
                raw.sendall(b'{"id":"unsigned-readonly-check","method":"connection_status","params":{}}\n')
                reply = raw.recv(1024)
            except (ConnectionResetError, BrokenPipeError):
                reply = b''
            check('Release rejects unsigned client', not reply)
        finally:
            raw.close()
            os.fchdir(original_directory)
            os.close(original_directory)
        print(f'\n{sum(ok for _, ok in outcomes)} passed, {sum(not ok for _, ok in outcomes)} failed. No valid generation calls.', flush=True)
        return int(any(not ok for _, ok in outcomes))
    finally:
        client.close()


if __name__ == '__main__':
    sys.exit(main())
