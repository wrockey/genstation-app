#!/usr/bin/env python3
"""Regenerate the recorded baseline of payload keys no published schema documents.

    tools/undocumented_key_baseline.py [--write]

Reads three checked-in files and writes one:

    Tests/GenStationCoreTests/Fixtures/aiml-models-response.json   id -> canonical served id
    Tests/GenStationCoreTests/Fixtures/aiml-model-schemas.json     canonical id -> OpenAPI 3.0 doc
    Tests/GenStationCoreTests/GoldenPayloads.swift                 registered id -> emitted keys
    -> Tests/GenStationCoreTests/Fixtures/aiml-undocumented-keys.json

NOTHING HERE IS A BUG LIST TO FIX ON SIGHT. Every correction moves the wire for existing users and
belongs in the drift ledger as a group-A row awaiting
approval, never as a table edit. An undocumented key is also not proof of rejection: most APIs ignore
unknown fields, so the likely effect is a feature that silently never happens.

`UndocumentedKeyBaselineTests` recomputes all of this in Swift, from `GoldenPayloads` directly rather
than by parsing it, and asserts equality with the file this script writes. Two independent
implementations agreeing is the point; do not "simplify" the test into reading the fixture back.

Output is normalised the same way as the sibling fixtures — indent=1, sort_keys=True,
ensure_ascii=False — so a regeneration produces a reviewable diff rather than a reformatting.
"""
import collections
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "Packages/GenStationCore/Tests/GenStationCoreTests")
MODELS = os.path.join(TESTS, "Fixtures/aiml-models-response.json")
SCHEMAS = os.path.join(TESTS, "Fixtures/aiml-model-schemas.json")
GOLDEN = os.path.join(TESTS, "GoldenPayloads.swift")
OUT = os.path.join(TESTS, "Fixtures/aiml-undocumented-keys.json")

source = open(GOLDEN).read()

# registered id -> table symbol, from the single `byModelId` dictionary.
block = re.search(r"static let byModelId: \[String: ProbePayloads\] = \[(.*?)\n    \]", source, re.S)
if not block:
    sys.exit("could not find `static let byModelId` in %s" % GOLDEN)
by_model_id = {}
for line in block.group(1).split("\n"):
    m = re.match(r'\s*"([^"]+)":\s*(\w+),\s*$', line)
    if m:
        by_model_id[m.group(1)] = m.group(2)

# table symbol -> every payload key it emits, across all five probes. Probe keys sit at eight spaces
# of indent inside the table literal and payload keys at twelve, so the depth is the discriminator.
tables = {}
for m in re.finditer(r"static let (\w+): ProbePayloads = \[(.*?)\n    \]", source, re.S):
    keys = set()
    for line in m.group(2).split("\n"):
        km = re.match(r'"([^"]+)":', line.strip())
        if km and len(line) - len(line.lstrip()) == 12:
            keys.add(km.group(1))
    tables[m.group(1)] = keys

# lowercased spelling -> canonical served id, and canonical served id -> documented property names.
entries = json.load(open(MODELS))["data"]
canonical = {}
for entry in entries:
    canonical[entry["id"].lower()] = entry["id"]
    for alias in entry.get("aliases") or []:
        canonical.setdefault(alias.lower(), entry["id"])

schemas = json.load(open(SCHEMAS))
documented = {}
for served_id, doc in schemas.items():
    names = set()
    for operations in doc.get("paths", {}).values():
        for spec in operations.values():
            body = spec.get("requestBody", {}).get("content", {}).get("application/json", {})
            names |= set(body.get("schema", {}).get("properties", {}).keys())
    documented[served_id.lower()] = names

offenders, frequency, unchecked = {}, collections.Counter(), []
for model_id in sorted(by_model_id):
    served = canonical.get(model_id.lower())
    props = documented.get(served.lower()) if served else None
    if props is None:
        unchecked.append(model_id)
        continue
    undocumented = sorted(k for k in tables[by_model_id[model_id]] if k not in props)
    if undocumented:
        offenders[model_id] = undocumented
        frequency.update(undocumented)

checked = len(by_model_id) - len(unchecked)
print("registered ids: %d   checked against a schema: %d   not served, no schema: %d"
      % (len(by_model_id), checked, len(unchecked)))
print("ids emitting at least one undocumented key: %d" % len(offenders))
print("id/key pairs: %d" % sum(len(v) for v in offenders.values()))
print("\nkey frequency:")
for key, n in frequency.most_common():
    print("  %-26s %d" % (key, n))
print("\nnot checked (unserved, so no schema): %s" % ", ".join(unchecked))

payload = {
    "_readMe": "Recorded baseline, not a bug list. See tools/undocumented_key_baseline.py and "
               "spec 4.10. Fixes move the wire and belong in the drift ledger as group-A rows.",
    "checkedIDCount": checked,
    "offendingIDCount": len(offenders),
    "uncheckedIDs": sorted(unchecked),
    "undocumentedKeysByID": offenders,
}
if "--write" in sys.argv:
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1, sort_keys=True, ensure_ascii=False)
        handle.write("\n")
    print("\nwrote %s" % OUT)
else:
    print("\ndry run; pass --write to update %s" % OUT)
