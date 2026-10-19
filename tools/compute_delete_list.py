#!/usr/bin/env python3
"""Registered ids the captured /models response no longer serves.

Reports and writes id lists; deletes nothing. Usage:
    compute_delete_list.py <fixture.json> <AliasGroups.swift> <out-dir>
"""
import json, os, re, sys

fixture, groups_swift, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(outdir, exist_ok=True)

data = json.load(open(fixture))["data"]
served = set()
for entry in data:
    served.add(entry["id"].lower())
    for alias in (entry.get("aliases") or []):
        served.add(alias.lower())

groups = []
for line in open(groups_swift):
    m = re.match(r'^        \[(.*)\],$', line)
    if m:
        groups.append([s.strip().strip('"').lower() for s in m.group(1).split(",")])
registered = [i for g in groups for i in g]
assert len(registered) == len(set(registered)), "an id appears in two groups"

unserved = sorted(i for i in registered if i not in served)
whole, canonical_only, alias_only = [], [], []
for i in unserved:
    group = next(g for g in groups if i in g)
    if all(x in unserved for x in group):
        whole.append((i, group))
    elif i == group[0]:
        canonical_only.append((i, group))
    else:
        alias_only.append((i, group))

print("served spellings: %d   registered: %d   groups: %d   unserved: %d"
      % (len(served), len(registered), len(groups), len(unserved)))
for label, rows in (("WHOLE MODEL (canonical and every alias unserved)", whole),
                    ("CANONICAL UNSERVED, group still served -> RE-ELECT", canonical_only),
                    ("ALIAS ONLY (model still served under another spelling)", alias_only)):
    print("\n%s — %d:" % (label, len(rows)))
    for i, g in rows:
        print("  %-46s group: %s" % (i, ", ".join(g)))

def write(name, ids):
    open(os.path.join(outdir, name), "w").write("".join(i + "\n" for i in ids))

write("unserved-all.txt", unserved)
write("unserved-whole.txt", [i for i, _ in whole])
write("unserved-canonical.txt", [i for i, _ in canonical_only])
write("unserved-alias-only.txt", [i for i, _ in alias_only])
print("\nwrote %s/unserved-{all,whole,canonical,alias-only}.txt" % outdir)
