#!/usr/bin/env python3
"""Read-only local-client handshake/reconnect probe. Never launches the app or generates."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import time

from follow_job import Client


def probe(helper):
    helper = Path(helper).resolve(strict=True)
    app = helper.parents[2]
    if app.suffix != '.app' or helper != (app / 'Contents/Helpers/genstation-mcp').resolve():
        raise RuntimeError('Use the exact helper embedded in the candidate app.')
    with (app / 'Contents/Info.plist').open('rb') as source:
        bundle = plistlib.load(source)
    if bundle.get('CFBundleIdentifier') != 'art.genstation.app':
        raise RuntimeError('This probe requires the production candidate, not the isolated demo.')
    # An explicit socket disables helper auto-launch. Never launch an old installed
    # app by bundle identifier or silently use an inherited test-socket override.
    os.environ['GENSTATION_MCP_SOCKET'] = str(Path.home() /
        'Library/Containers/art.genstation.app/Data/Library/Application Support/art.genstation.app/mcp.sock')
    required = {'connection_status', 'list_jobs', 'get_job_status', 'wait_for_job', 'get_asset'}
    observations = []
    for attempt in range(2):
        client = Client(str(helper), deadline=time.monotonic() + 30)
        try:
            names = {tool['name'] for tool in client.rpc('tools/list', {})['tools']}
            if not required.issubset(names):
                raise RuntimeError('Helper lacks continuity tools: ' + ', '.join(sorted(required - names)))
            status = client.tool('connection_status', {})
            reported_app, reported_helper = status.get('app_path'), status.get('helper_path')
            if (not isinstance(reported_app, str) or not isinstance(reported_helper, str)
                    or Path(reported_app).resolve() != app or Path(reported_helper).resolve() != helper):
                raise RuntimeError('Connected app/helper paths do not match the requested candidate.')
            # No history, jobs, prompts, originals, or key values are emitted.
            observations.append({
                'connection': attempt + 1,
                'tool_count': len(names),
                **{key: status.get(key) for key in (
                    'app_path', 'helper_path', 'app_version', 'app_build', 'app_flavor',
                    'history_ready', 'workflow_storage_ready', 'video_storage_ready',
                    'budgeted_approval_available')},
            })
        finally:
            client.close()
    return {'status': 'connected_and_reconnected', 'observations': observations,
            'scope': 'Local MCP connection only; bot continuation and generation remain unverified.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('helper', help='Exact Contents/Helpers/genstation-mcp path')
    args = parser.parse_args()
    try:
        print(json.dumps(probe(args.helper), indent=2))
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        parser.exit(1, f'Connection probe failed: {error}\n')
