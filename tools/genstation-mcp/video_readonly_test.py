#!/usr/bin/env python3
"""Exercise durable video discovery/preflight and invalid submissions against the real helper.
No valid generation, approval dialog, hosting, recovery GET or provider call is requested.
Usage: video_readonly_test.py /path/to/matching/embedded/helper
"""
import sys
import uuid
from live_readonly_test import Client, png_fixture

client = Client(sys.argv[1])
checks = 0

def check(condition, title, detail=None):
    global checks
    assert condition, (title, detail)
    checks += 1
    print('PASS ' + title, flush=True)

try:
    tools = client.rpc('tools/list')['result']['tools']
    by_name = {t['name']: t for t in tools}
    check(len(tools) == 22, '22 tools exposed')
    check('request_id' in by_name['generate_video']['inputSchema']['required'], 'video requires durable identity')
    check(by_name['generate_video']['annotations']['idempotentHint'], 'identical video replay is idempotent')
    check(by_name['validate_video_request']['annotations']['readOnlyHint'], 'preflight read-only hint')
    check(by_name['recover_video_job']['annotations']['idempotentHint'], 'recovery idempotent hint')
    guide = client.rpc('resources/read', {'uri': 'genstation://docs/image-workflow'})['result']['contents'][0]['text']
    check(all(t in guide for t in ['submission_unknown', 'recover_video_job', 'validate_video_request', 'GET-only']), 'durable video recovery instructions bundled')
    models, error = client.tool('list_models', {'type': 'video'})
    check(not error and models['models'], 'video model discovery')
    for model in models['models']:
        check('parameter_schema' in model and model['request_id_required'], model['id'] + ' strict discovery')
        if model['requires_input_image']:
            continue  # Public hosting credentials are user settings; pure core tests cover frame-model defaults.
        args = {'model': model['id'], 'prompt': 'A small lighthouse at sunrise'}
        result, error = client.tool('validate_video_request', args)
        check(not error and result['valid'] and result['network_requests'] == 0, model['id'] + ' default preflight', result)
    model = next(m for m in models['models'] if not m['requires_input_image'])
    base = {'model': model['id'], 'prompt': 'A small lighthouse at sunrise'}
    for name, args in [
        ('generate_video', base),
        ('generate_video', {**base, 'request_id': 'invalid-' + str(uuid.uuid4()), 'params': {'unrecognized': 1}}),
        ('validate_video_request', {**base, 'params': 'invalid'}),
        ('validate_video_request', {**base, 'input_images': ['/etc/passwd']}),
        ('validate_video_request', {**base, 'input_images': ['https://example.com/input.png']}),
        ('validate_video_request', {**base, 'input_images': ['asset:' + str(uuid.uuid4())]}),
        ('validate_video_request', {**base, 'prompt': ''}),
        ('validate_video_request', {**base, 'provider': 'grok'}),
        ('validate_video_request', {**base, 'api_key': 'invalid-test-value'}),
        ('recover_video_job', {'job_id': str(uuid.uuid4())}),
        ('recover_video_job', {'job_id': str(uuid.uuid4()), 'model': model['id']}),
    ]:
        result, error = client.tool(name, args)
        check(error and 'job_id' not in result, name + ' rejects invalid request', result)
    print(f'{checks} checks passed; no valid generation or provider recovery requested', flush=True)
finally:
    client.close()
