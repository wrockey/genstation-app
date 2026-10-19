#!/usr/bin/env python3
"""Stage 3 Task 12 — write displayName and family onto the 122 canonical catalog rows.

displayName comes from the captured /models fixture (`info.name`, 907/907), except for the ids in
Catalog/Models/PresentationOverrides.swift's `displayNameOverrides`, which this script PARSES out
of that Swift file so there is exactly one copy of the override list. family comes from
presentation_seed.FAMILY.

A spelling can be served under MORE THAN ONE endpoint family with a DIFFERENT `info.name` on each
(e.g. `"Gemini 3 Pro Image"` on `openai/image-generations` vs `"Nano Banana Pro (Gemini 3 Pro Image
Preview)"` on `openai/chat-completions`, both for `google/gemini-3-pro-image-preview`). Picking
"whichever entry comes first/last in the JSON array" would make the answer depend on wire order,
and there is exactly one place in this repository that already resolves this ambiguity:
`AIMLEndpoints.infoPreferenceOrder` (Providers/AIMLEndpoints.swift), consumed by
`AIMLModelsFixture.infoBySpelling()` in the Swift test target. PREFERENCE_ORDER below is that same
list, reimplemented in Python because a build script cannot call into the Swift test target.
`CatalogPresentationTests.testSixDualNameIDsMatchInfoBySpellingsChoice` pins that the two
implementations agree on the ids where it matters (i.e. where a registered catalog row is affected).
Keep PREFERENCE_ORDER and AIMLEndpoints.infoPreferenceOrder identical, in the same order.

STRICT, in the same sense as tools/stage3-catalog-gen/gen_catalog_rows.py: it aborts naming the
file and line rather than doing something approximate. It aborts if a row has no fixture entry
under any of its spellings, if a row has no FAMILY entry, if a FAMILY or override key matches no
row, if a row is missing an `id:`/`aliases:`/`displayName:`/`family:` line, if two rows would end
up with the same displayName, or if the row count is not 122.

Only the displayName and family lines are ever rewritten. Every other byte of every row is left
exactly as the generator wrote it, so `git diff` shows 244 changed lines and nothing else.

Run from the repository root:

    python3 tools/stage3-catalog-gen/apply_presentation.py
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from presentation_seed import FAMILY

MODELS = "Packages/GenStationCore/Sources/GenStationCore/Catalog/Models/*.swift"
OVERRIDES_SWIFT = ("Packages/GenStationCore/Sources/GenStationCore/Catalog/Models/"
                   "PresentationOverrides.swift")
FIXTURE = "Packages/GenStationCore/Tests/GenStationCoreTests/Fixtures/aiml-models-response.json"

# Mirrors AIMLEndpoints.infoPreferenceOrder exactly (Providers/AIMLEndpoints.swift). A spelling
# served under a type in this list is preferred, in this order; a type not in the list falls back
# to lexicographically-smallest-type, same as AIMLModelsFixture.infoBySpelling().
PREFERENCE_ORDER = [
    "internal/video-generations/submit",
    "openai/image-generations",
    "openai/image-editing",
]

ROW_START = re.compile(r"^(\s*)CatalogModel\($")
ID = re.compile(r'^\s*id: "([^"]+)",$')
ALIASES = re.compile(r"^\s*aliases: \[(.*)\],$")
DISPLAY = re.compile(r'^(\s*)displayName: ".*",$')
FAMILY_LINE = re.compile(r'^(\s*)family: ".*",$')


def die(msg):
    raise SystemExit("ABORT — " + msg)


def load_overrides():
    """Parse `displayNameOverrides`'s dictionary literal out of the Swift file."""
    text = open(OVERRIDES_SWIFT, encoding="utf-8").read()
    marker = "public static let displayNameOverrides: [String: String] = ["
    if text.count(marker) != 1:
        die("expected exactly one `displayNameOverrides` declaration in %s" % OVERRIDES_SWIFT)
    body = text.split(marker, 1)[1].split("\n    ]", 1)[0]
    pairs = re.findall(r'^\s*"([^"]+)": "([^"]+)",$', body, re.M)
    out = dict(pairs)
    if len(out) != len(pairs):
        die("duplicate key in displayNameOverrides")
    if not out:
        die("parsed zero entries from displayNameOverrides — the regex or the file shape changed")
    return out


def load_fixture():
    """spelling (lowercased) -> the vendor's `info.name`, resolved by the SAME rule as
    AIMLEndpoints.infoPreferenceOrder / AIMLModelsFixture.infoBySpelling(): the entry whose `type`
    has the lowest rank in PREFERENCE_ORDER wins; a type absent from PREFERENCE_ORDER ranks last
    and ties break on the lexicographically smallest `type`. This must not degrade to "first (or
    last) entry in the JSON array wins" — that is order-dependent and is exactly how this script
    and infoBySpelling() could silently disagree on a dual-name id."""
    data = json.load(open(FIXTURE, encoding="utf-8"))["data"]
    best = {}  # spelling -> (rank, type, name)
    for entry in data:
        info = entry.get("info") or {}
        name = info.get("name")
        if not name:
            continue
        etype = entry.get("type") or ""
        rank = (PREFERENCE_ORDER.index(etype) if etype in PREFERENCE_ORDER
                else len(PREFERENCE_ORDER))
        candidate = (rank, etype)
        for spelling in [entry["id"]] + (entry.get("aliases") or []):
            key = spelling.lower()
            if key in best and best[key][:2] <= candidate:
                continue
            best[key] = (rank, etype, name)
    return {k: v[2] for k, v in best.items()}


overrides = load_overrides()
names_by_spelling = load_fixture()

used_family, used_override, via_alias = set(), set(), []
assigned = {}
patched = 0
touched = []

for path in sorted(glob.glob(MODELS)):
    if path.endswith("PresentationOverrides.swift"):
        continue
    lines = open(path, encoding="utf-8").read().split("\n")
    changed = False
    i = 0
    while i < len(lines):
        if not ROW_START.match(lines[i]):
            i += 1
            continue
        start = i
        depth, j = 1, i + 1
        while j < len(lines) and depth:
            depth += lines[j].count("(") - lines[j].count(")")
            j += 1
        if depth:
            die("%s:%d — unterminated CatalogModel(" % (path, start + 1))
        block = list(range(start + 1, j))

        ids = [ID.match(lines[k]).group(1) for k in block if ID.match(lines[k])]
        if len(ids) != 1:
            die("%s:%d — expected exactly one `id:` line, found %d" % (path, start + 1, len(ids)))
        row_id = ids[0]
        alias_lines = [k for k in block if ALIASES.match(lines[k])]
        if len(alias_lines) != 1:
            die("%s:%d — expected exactly one `aliases:` line" % (path, start + 1))
        aliases = re.findall(r'"([^"]+)"', ALIASES.match(lines[alias_lines[0]]).group(1))

        if row_id in overrides:
            display = overrides[row_id]
            used_override.add(row_id)
        else:
            hits = [s for s in [row_id] + aliases if s in names_by_spelling]
            if not hits:
                die("%s:%d — row %s has no /models entry under any of its %d spellings"
                    % (path, start + 1, row_id, 1 + len(aliases)))
            if hits[0] != row_id:
                via_alias.append((row_id, hits[0]))
            display = names_by_spelling[hits[0]]

        if row_id not in FAMILY:
            die("%s:%d — no FAMILY entry for %s" % (path, start + 1, row_id))
        family = FAMILY[row_id]
        used_family.add(row_id)

        if display in assigned:
            die("displayName %r would be shared by %s and %s — add an override"
                % (display, assigned[display], row_id))
        assigned[display] = row_id

        for regex, label, value in ((DISPLAY, "displayName", display),
                                    (FAMILY_LINE, "family", family)):
            hits = [k for k in block if regex.match(lines[k])]
            if len(hits) != 1:
                die("%s:%d — expected exactly one `%s:` line" % (path, start + 1, label))
            if '"' in value:
                die("%s contains a double quote and cannot be written as a Swift literal" % value)
            indent = regex.match(lines[hits[0]]).group(1)
            lines[hits[0]] = '%s%s: "%s",' % (indent, label, value)

        changed = True
        patched += 1
        i = j

    if changed:
        open(path, "w", encoding="utf-8").write("\n".join(lines))
        touched.append(path)

unused_family = sorted(set(FAMILY) - used_family)
if unused_family:
    die("%d FAMILY keys matched no catalog row: %s" % (len(unused_family), ", ".join(unused_family)))
unused_override = sorted(set(overrides) - used_override)
if unused_override:
    die("%d override keys matched no catalog row: %s"
        % (len(unused_override), ", ".join(unused_override)))
if patched != 122:
    die("patched %d rows, expected 122" % patched)
print("patched %d rows across %d files" % (patched, len(touched)))
print("overrides applied: %d" % len(used_override))
print("resolved via an alias: %d %s" % (len(via_alias), via_alias))
print("distinct families: %d" % len(set(FAMILY.values())))
