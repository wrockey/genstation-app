#!/usr/bin/env python3
"""Provider-free multi-connection helper/client acceptance. Uses a temporary mock socket only."""
import json
import os
from pathlib import Path
import socket
import sys
import tempfile
import threading
import time
from follow_job import Client, follow, verify_asset
import hashlib

helper = str(Path(sys.argv[1]).resolve())
# Do not run a demo helper: it intentionally ignores mock socket overrides.
import plistlib
for parent in Path(helper).parents:
    info = parent / 'Contents/Info.plist'
    if parent.suffix == '.app' and info.exists() and plistlib.loads(info.read_bytes()).get('CFBundleIdentifier') == 'art.genstation.demo':
        raise SystemExit('Use a production-mode helper; demo helpers ignore the test socket.')

with tempfile.TemporaryDirectory(prefix='gs-job-') as directory:
    original = Path(directory, 'original.png')
    original.write_bytes(b'original')
    socket_directory = Path(directory, 'long-' + 'x' * 80)
    socket_directory.mkdir()
    path = str(socket_directory / 'mock.sock')
    os.environ['GENSTATION_MCP_SOCKET'] = path
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    previous_directory = os.getcwd()
    try:
        os.chdir(socket_directory)
        server.bind('mock.sock')
    finally:
        os.chdir(previous_directory)
    server.listen(10)
    calls = []
    waiting = threading.Event()
    done = threading.Event()
    disconnect_once = [True]
    lock = threading.Lock()
    def snapshot():
        terminal = done.is_set()
        return {'job_id': 'durable-job', 'request_id': 'panel-1', 'status': 'done' if terminal else 'awaiting_approval',
                'approval_state': 'not_pending' if terminal else 'pending', 'state_token': ('b' if terminal else 'a') * 64,
                'asset_ids': ['original-1'] if terminal else []}
    def serve(connection):
        with connection, connection.makefile('r') as lines:
            for line in lines:
                request = json.loads(line)
                name = request['method']
                with lock:
                    calls.append(request)
                if name == 'wait_for_job' and request['params'].get('job_id') == 'stalled-app':
                    time.sleep(30)
                    return
                if name == 'wait_for_job':
                    waiting.set()
                    done.wait(2)
                if name == 'get_job_status':
                    with lock:
                        lose = disconnect_once[0]
                        disconnect_once[0] = False
                    if lose:
                        return  # caller must reconnect by the same identity
                if name in {'get_job_status', 'wait_for_job'}:
                    result = snapshot()
                elif name == 'list_jobs':
                    result = {'jobs': [snapshot()], 'scope': 'local_mcp_jobs'}
                elif name == 'get_asset':
                    result = {'asset_id': 'original-1', 'media_type': 'image/png', 'file_path': str(original), 'manifest': {'byte_count': 8, 'sha256': hashlib.sha256(b'original').hexdigest()}}
                else:
                    raise AssertionError('Unexpected tool: ' + name)
                connection.sendall((json.dumps({'id': request['id'], 'result': result}) + '\n').encode())
    def accept():
        while True:
            try:
                connection, _ = server.accept()
            except OSError:
                return
            threading.Thread(target=serve, args=(connection,), daemon=True).start()
    threading.Thread(target=accept, daemon=True).start()
    pending = []
    output = []
    worker = threading.Thread(target=lambda: output.append(follow(helper, {'request_id': 'panel-1', 'kind': 'image'}, 8, pending.append)))
    worker.start()
    assert waiting.wait(4), 'caller did not resume polling after lost response'
    # Same helper: a bounded wait must not hold its ordinary tool queue/socket.
    client = Client(helper)
    client.serial += 1
    client.process.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': 90, 'method': 'tools/call', 'params': {'name': 'wait_for_job', 'arguments': {'job_id': 'durable-job', 'since': 'a'*64}}}) + '\n')
    client.process.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': 91, 'method': 'tools/call', 'params': {'name': 'list_jobs', 'arguments': {'filter': 'pending'}}}) + '\n')
    client.process.stdin.flush()
    first = json.loads(client.process.stdout.readline())
    assert first['id'] == 91, 'wait blocked another tool on the same helper'
    done.set()
    second = json.loads(client.process.stdout.readline())
    assert second['id'] == 90
    client.close()
    worker.join(5)
    assert not worker.is_alive() and output[0]['status'] == 'done'
    assert output[0]['assets'][0]['asset_id'] == 'original-1'
    assert output[0]['assets'][0]['verification'] == 'checksum_verified'
    original.write_bytes(b'changed')
    try:
        verify_asset(output[0]['assets'][0])
        raise AssertionError('Changed original was accepted')
    except RuntimeError:
        pass
    assert len(pending) == 1, 'approval guidance should appear once across continuation'
    assert not any(call['method'].startswith(('generate', 'run_', 'recover')) for call in calls)
    assert any(call['params'].get('request_id') == 'panel-1' for call in calls)
    done.clear()
    capped = Client(helper)
    for index in range(5):
        capped.process.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': 200 + index, 'method': 'tools/call', 'params': {'name': 'wait_for_job', 'arguments': {'job_id': 'durable-job', 'since': 'a'*64}}}) + '\n')
    capped.process.stdin.flush()
    rejected = json.loads(capped.process.stdout.readline())
    assert rejected['id'] == 204 and rejected['result']['isError'], 'fifth simultaneous wait was not bounded'
    done.set()
    remaining = [json.loads(capped.process.stdout.readline()) for _ in range(4)]
    assert {reply['id'] for reply in remaining} == {200, 201, 202, 203}
    capped.close()
    stalled = Client(helper)
    began = time.monotonic()
    try:
        stalled.tool('wait_for_job', {'job_id': 'stalled-app', 'since': 'a'*64})
        raise AssertionError('Stalled app did not time out')
    except ConnectionError:
        assert time.monotonic() - began < 29, 'wait socket was not bounded'
    assert stalled.tool('list_jobs', {})['scope'] == 'local_mcp_jobs'
    stalled.close()
    print('PASS stalled wait connection times out; ordinary tools remain usable.')
    server.close()
    print('PASS four-wait cap and concurrent long Unix socket paths.')
    print('PASS reconnect by exact request ID, pending once, waiting, concurrent tool, terminal asset consumption; zero generation/recovery calls.')
