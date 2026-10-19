#!/usr/bin/env python3
"""Verify bundled agent docs with no app, socket or repository working directory.
Usage: documentation_test.py /absolute/path/to/genstation-mcp
No paid calls, app launch, network access, or preference changes.
"""
import json
import plistlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

helper = str(Path(sys.argv[1]).resolve())
for parent in Path(helper).parents:
    info = parent / 'Contents/Info.plist'
    if parent.suffix == '.app' and info.exists() and plistlib.loads(info.read_bytes()).get('CFBundleIdentifier') == 'art.genstation.demo':
        raise SystemExit('Offline tests require a production-mode helper, never an embedded demo helper.')
probe = subprocess.run([helper], input=json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{}})+'\n', text=True, capture_output=True, check=True)
if json.loads(probe.stdout)['result']['serverInfo']['name'] == 'genstation-demo':
    raise SystemExit('Use a standalone production-mode helper for offline tests; demo helpers ignore socket overrides.')
uri = 'genstation://docs/image-workflow'
checks = 0
with tempfile.TemporaryDirectory(prefix='genstation-docs-') as directory:
    env = dict(os.environ, GENSTATION_MCP_SOCKET=os.path.join(directory, 'missing.sock'))
    for version in ['2024-11-05', '2025-03-26', '2025-06-18']:
        requests = [
            ('initialize', {'protocolVersion': version, 'capabilities': {}, 'clientInfo': {'name':'offline-doc-test', 'version':'1'}}),
            ('resources/list', {}),
            ('resources/read', {'uri': uri}),
            ('resources/templates/list', {}),
            ('resources/read', {'uri': 'file:///etc/passwd'}),
            ('resources/read', {'uri': 123}),
            ('resources/list', {'cursor': 'invalid'}),
            ('tools/call', {'name':'connection_status', 'arguments':{}}),
            ('resources/read', {'uri': uri}),
            ('ping', {}),
        ]
        wire = ''.join(json.dumps({'jsonrpc':'2.0', 'id': i, 'method': method, 'params': params}) + '\n' for i, (method, params) in enumerate(requests, 1))
        completed = subprocess.run([helper], input=wire, text=True, capture_output=True, timeout=15, cwd=directory, env=env, check=True)
        replies = {r['id']:r for r in map(json.loads, completed.stdout.splitlines())}
        assert len(replies) == 10
        assert replies[1]['result']['protocolVersion'] == version
        assert replies[1]['result']['capabilities']['resources'] == {}
        assert uri in replies[1]['result']['instructions']
        assert replies[2]['result']['resources'][0]['uri'] == uri
        guide = replies[3]['result']['contents'][0]
        assert guide['mimeType'] == 'text/markdown' and guide['uri'] == uri
        assert all(name in guide['text'] for name in ['connection_status', 'list_models', 'validate_image_request', 'generate_image', 'get_job_status', 'list_assets', 'get_asset', 'generate_video', 'list_styles', 'compose_prompt', 'list_workflows', 'validate_workflow_request', 'run_saved_workflow', 'validate_video_request', 'recover_video_job', 'recover_workflow_job', 'list_jobs', 'wait_for_job', 'list_history_folders', 'create_history_folder', 'rename_history_folder', 'move_history_assets'])
        assert all(term in guide['text'] for term in ['filter_reasons', 'genstation_local', 'normalized_phrase', 'policy_version'])
        assert replies[4]['result']['resourceTemplates'] == []
        assert replies[5]['error']['code'] == -32002
        assert replies[6]['error']['code'] == -32602
        assert replies[7]['error']['code'] == -32602
        assert replies[8]['result']['isError'] and replies[8]['result']['structuredContent']['error']['code'] == 'app_unreachable'
        assert replies[9]['result']['contents'][0] == guide
        assert replies[10]['result'] == {}
        checks += 15
        print('PASS offline documentation:', version)
print(f'{checks} checks passed; app unavailable, auto-launch disabled, unrelated working directory.')
