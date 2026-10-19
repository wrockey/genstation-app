#!/usr/bin/env python3
"""Live discovery/validation checks; never submits a generation.
Usage: styles_workflows_test.py /path/to/matching/embedded/helper
Contacts the configured ComfyUI server with GET for the first saved workflow.
"""
import json
import sys
import uuid
from live_readonly_test import Client

client = Client(sys.argv[1])
checks = 0

def check(condition, name):
    global checks
    assert condition, name
    checks += 1
    print('PASS ' + name, flush=True)

def call(name, args=None):
    data, error = client.tool(name, args)
    assert not error, (name, data)
    return data

def invalid(name, args):
    data, error = client.tool(name, args)
    check(error, name + ' rejects ' + ','.join(args))

try:
    discovery = client.rpc('tools/list')['result']['tools']
    names = {t['name'] for t in discovery}
    check({'list_styles', 'compose_prompt', 'list_workflows', 'validate_workflow_request', 'run_saved_workflow'} <= names, 'five new tools advertised')
    check('run_workflow' not in names, 'arbitrary workflow tool absent')
    for tool in discovery:
        if tool['name'] in {'list_styles', 'compose_prompt', 'list_workflows', 'validate_workflow_request'}:
            check(tool['annotations']['readOnlyHint'], tool['name'] + ' read-only annotation')
    rows = call('list_styles')['styles']
    check(len(rows) > 0 and len({r['style_id'] for r in rows}) == len(rows), 'unique namespaced style IDs')
    builtins = call('list_styles', {'source': 'builtin'})['styles']
    check(all(r['source'] == 'builtin' for r in builtins), 'builtin filter')
    custom = call('list_styles', {'source': 'custom'})['styles']
    check(all(r['source'] == 'custom' for r in custom), 'custom filter')
    search = call('list_styles', {'query': builtins[0]['name']})['styles']
    check(any(r['style_id'] == builtins[0]['style_id'] for r in search), 'search finds named style')
    plain = call('compose_prompt', {'prompt': 'A blue ceramic lighthouse', 'style_ids': []})
    check(plain['prompt'] == 'A blue ceramic lighthouse' and plain['negative_prompt'] == '', 'empty styles preserve prompt')
    ids = [r['style_id'] for r in builtins[:2]]
    a = call('compose_prompt', {'prompt': 'A blue ceramic lighthouse', 'style_ids': [ids[0]]})
    b = call('compose_prompt', {'prompt': 'A blue ceramic lighthouse', 'style_ids': [ids[1]]})
    both = call('compose_prompt', {'prompt': 'A blue ceramic lighthouse', 'style_ids': ids})
    check(both['prompt'] == a['prompt'] + ' . ' + b['prompt'].split('\n', 1)[1], 'ordered style stacking preserves both descriptions')
    check(both['negative_prompt'] == ', '.join(s for s in [a['negative_prompt'], b['negative_prompt']] if s), 'negative prompts remain separate')
    check(both['generation_submitted'] is False and both['ui_selection_changed'] is False, 'composition has no generation or UI mutation')
    for args in [{'prompt': '', 'style_ids': []}, {'prompt': 'a', 'style_ids': ['missing']}, {'prompt': 'a', 'style_ids': ids*2}, {'prompt': 'a', 'style_ids': [], 'api_key': 'invalid-test-value'}]:
        invalid('compose_prompt', args)
    invalid('list_styles', {'source': 'unknown'})
    invalid('list_styles', {'query': True})
    invalid('list_workflows', {'workflow_json': {}})
    invalid('validate_workflow_request', {'workflow_id': str(uuid.uuid4()), 'workflow_json': {}})
    invalid('run_saved_workflow', {'workflow_id': str(uuid.uuid4()), 'request_id': 'invalid-' + str(uuid.uuid4())})
    invalid('run_workflow', {'workflow_json': {}})
    workflows = call('list_workflows')
    check('workflows' in workflows and workflows['scope'] == 'user_saved_workflows_only', 'saved library discovery')
    for row in workflows['workflows'][:1]:
        validated = call('validate_workflow_request', {'workflow_id': row['workflow_id']})
        check(validated['valid'] and not validated['generation_submitted'], 'saved workflow validates without execution')
        if validated['prompt_override_supported']:
            validated = call('validate_workflow_request', {'workflow_id': row['workflow_id'], 'prompt': both['prompt']})
            check(validated['prompt_override_applied'], 'styled prompt override validated')
        print('Validated saved workflow: ' + row['name'], flush=True)
    print(f'{checks} checks passed; no generation submitted', flush=True)
finally:
    client.close()
