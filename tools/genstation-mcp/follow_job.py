#!/usr/bin/env python3
"""Follow an existing GenStation job. Never submits, approves or starts recovery.
Example: follow_job.py /exact/GenStation.app/Contents/Helpers/genstation-mcp --request-id panel-1 --kind image
Keep the same arguments to resume after disconnect. A helper exit never creates a new job.
"""
import argparse
import hashlib
import stat
import json
import subprocess
import select
import os
import sys
import time

class Client:
    def __init__(self, helper, deadline=None):
        self.deadline = deadline
        self.buffer = b''
        self.process = subprocess.Popen([helper], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL, text=True)
        self.serial = 0
        try:
            self.rpc('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {},
                                    'clientInfo': {'name': 'genstation-follow-job', 'version': '1'}})
        except Exception:
            self.close()
            raise
    def rpc(self, method, params):
        self.serial += 1
        self.process.stdin.write(json.dumps({'jsonrpc': '2.0', 'id': self.serial, 'method': method, 'params': params}) + '\n')
        self.process.stdin.flush()
        while b'\n' not in self.buffer:
            timeout = 35 if self.deadline is None else max(0, min(35, self.deadline - time.monotonic()))
            if not select.select([self.process.stdout], [], [], timeout)[0]:
                raise ConnectionError('Helper response timed out; retain the same identity')
            chunk = os.read(self.process.stdout.fileno(), 65536)
            if not chunk:
                raise ConnectionError('Helper disconnected')
            self.buffer += chunk
            if len(self.buffer) > 64 * 1024 * 1024:
                raise RuntimeError('Helper response exceeds 64 MB')
        line, self.buffer = self.buffer.split(b'\n', 1)
        reply = json.loads(line)
        if reply.get('id') != self.serial or 'error' in reply:
            raise RuntimeError('Unexpected protocol response')
        return reply['result']
    def tool(self, name, arguments):
        result = self.rpc('tools/call', {'name': name, 'arguments': arguments})
        value = result.get('structuredContent', {})
        if result.get('isError'):
            error = value.get('error', {})
            if error.get('code') == 'app_unreachable':
                raise ConnectionError(error.get('message', 'Disconnected'))
            raise RuntimeError(json.dumps(error))
        return value
    def close(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait()

def verify_asset(asset):
    manifest = asset.get('manifest')
    if not manifest:
        asset['verification'] = 'unavailable_legacy_manifest'
        return asset
    path = asset.get('file_path')
    if not isinstance(path, str) or not os.path.isabs(path):
        raise RuntimeError('Asset handoff needs an authorized local original path')
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        metadata = os.fstat(descriptor)
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_size > 200_000_000:
            raise RuntimeError('Original is not a bounded regular file')
        digest = hashlib.sha256()
        count = 0
        while True:
            chunk = os.read(descriptor, 1024 * 1024)
            if not chunk:
                break
            count += len(chunk)
            if count > 200_000_000:
                raise RuntimeError('Original exceeds the handoff size limit')
            digest.update(chunk)
        if count != manifest.get('byte_count') or digest.hexdigest() != manifest.get('sha256'):
            raise RuntimeError('Original checksum/byte count changed; do not promote this asset')
        asset['verification'] = 'checksum_verified'
        return asset
    finally:
        os.close(descriptor)

def follow(helper, identity, max_seconds=120, on_pending=lambda job: None):
    deadline = time.monotonic() + max_seconds
    client = None
    announced = False
    token = None
    delay = 0.5
    try:
        while time.monotonic() < deadline:
            try:
                if client is None:
                    client = Client(helper, deadline)
                    status = client.tool('get_job_status', identity)
                    # Resolve the durable ID once; subsequent lookups never submit.
                    identity = {'job_id': status['job_id']}
                else:
                    status = client.tool('wait_for_job', dict(identity, since=token,
                        timeout_seconds=min(15, max(0, deadline - time.monotonic())))) if token else client.tool('get_job_status', identity)
                token = status.get('state_token')
                if status.get('approval_state') == 'pending' and not announced:
                    on_pending(status)
                    announced = True
                state = status.get('status')
                if state == 'done':
                    result = client.tool('get_job_status', identity)
                    result['assets'] = [verify_asset(client.tool('get_asset', {'asset_id': asset})) for asset in result.get('asset_ids', [])]
                    return result
                if state in {'denied', 'failed', 'cancelled', 'interrupted', 'recoverable', 'submission_unknown', 'budget_exhausted', 'billing_unresolved', 'grant_revoked', 'grant_expired', 'storage_unavailable'}:
                    return client.tool('get_job_status', identity)
                delay = 0.5
                # Older helpers/statuses may not provide tokens. Bounded polling fallback.
                if not token:
                    time.sleep(min(2, max(0, deadline - time.monotonic())))
            except (ConnectionError, BrokenPipeError, OSError):
                if client:
                    client.close()
                client = None
                time.sleep(min(delay, max(0, deadline - time.monotonic())))
                delay = min(5, delay * 2)
        return {'status': 'caller_wait_expired', 'identity': identity,
                'message': 'Resume with the same identity. This did not cancel, approve or resubmit the job.'}
    finally:
        if client:
            client.close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('helper')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--job-id')
    group.add_argument('--request-id')
    parser.add_argument('--kind', choices=['image', 'video', 'saved_comfy_workflow'])
    parser.add_argument('--max-seconds', type=float, default=120)
    args = parser.parse_args()
    if not 0 < args.max_seconds <= 3600:
        parser.error('--max-seconds must be from 0 to 3600')
    identity = {'job_id': args.job_id} if args.job_id else {'request_id': args.request_id}
    if args.kind:
        identity['kind'] = args.kind
    result = follow(args.helper, identity, args.max_seconds,
                    lambda job: print(job.get('approval_guidance', 'Review this job in GenStation → Jobs → Pending Approvals.'), file=sys.stderr))
    # Preview bytes are not needed for a continuation summary.
    result.pop('preview_png_base64', None)
    for asset in result.get('assets', []):
        asset.pop('preview_png_base64', None)
    print(json.dumps(result, indent=2))
