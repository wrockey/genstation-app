#!/usr/bin/env python3
"""Stage 3 Task 11 — collapse the AI/ML catalog rows from 209 to 122.

Reads the grouping from AliasGroups.swift (Task 10's pinned recording of the reg() blocks) and
rewrites the generated row files so each group contributes ONE row carrying its group-mates in
`aliases`. Nothing else changes: every surviving field line is byte-for-byte the line Task 8's
generator wrote.

ADAPTED FROM THE BRIEF. The brief's Step 3 assumed one monolithic row file
(`AIMLRegisteredModels.swift`, 209 `CatalogModel(` blocks in a single 4,618-line file). That is
not what Task 8 actually produced: Task 8 emitted the 209 rows across 23 per-vendor files under
Catalog/Models/ (ImageAlibabaRows.swift, VideoKlingRows.swift, ...), by design — each vendor
file's own header says so: "Every id of a single reg() group lands in ONE file even when the
spellings disagree about the vendor prefix ... which keeps the later alias collapse a local
edit." AIMLRegisteredModels.swift is just a 37-line roll-up that concatenates and sorts the 23
files' arrays; it carries zero rows itself. This script therefore operates on the glob of the 23
vendor files instead of a single ROWS path. The canonical rule, the capability guard, and the
resulting counts (122 models / 87 aliases / 52 multi-id groups) are unchanged from the brief —
only the file-discovery mechanism differs. The load-bearing assumption (every group's ids live in
exactly one file) was verified empirically before this script was written: 0 of the 122 groups
span two files. This script re-verifies it itself and aborts if it ever stops being true.

STRICT. Aborts, naming the group and both lines, if two ids in a group do not carry identical
capability lines — that is the gpt-image failure mode, and it must never be silent.

Run from the repository root:

    python3 tools/stage3-catalog-gen/collapse_aliases.py
    python3 tools/stage3-catalog-gen/collapse_aliases.py --report-suspect-groups
"""
import glob
import re
import sys

ROWS_DIR = "Packages/GenStationCore/Sources/GenStationCore/Catalog/Models"
ROLLUP = ROWS_DIR + "/AIMLRegisteredModels.swift"
GROUPS = "Packages/GenStationCore/Tests/GenStationCoreTests/AliasGroups.swift"
ROW_LINES = 22                      # `CatalogModel(` + 21 field lines
# Excluded from the capability comparison. `id`/`aliases`/`displayName` differ by construction at
# this point in the plan — displayName is still the id; Task 12 supplies the real one.
SKIP = ("id:", "aliases:", "displayName:")

# The per-vendor header boilerplate this task's collapse invalidates. All 23 vendor files carry
# this verbatim (Task 8 generated it from one template), so one search-and-replace list serves all
# of them.
STALE_VENDOR_HEADER = [
    '// One row per REGISTERED ID, not per group — aliases are still separate rows with `aliases: []`.',
    '// displayName == id, family == "", lifecycle == .current, typicalWallClock == nil: the identity',
    '// value of each presentation field, so nothing here pretends to know a display name or a family.',
]
NEW_VENDOR_HEADER = [
    '// One row per MODEL, not per registered id (Task 11 collapsed 209 -> 122). The other spellings',
    '// are carried in `aliases` and resolve through `Catalog.canonicalID(for:)` — nothing addressable',
    '// was lost. displayName == id, family == "": still true, pending Task 12.',
]

STALE_ROLLUP_DOC = "    /// Every registered id, sorted by id. 209 rows today."
NEW_ROLLUP_DOC = ("    /// Every model, sorted by id. 122 rows, collapsed from 209 registered "
                   "spellings in Task 11.")


def die(msg):
    raise SystemExit("ABORT: " + msg)


def vendor_files():
    files = sorted(f for f in glob.glob(ROWS_DIR + "/*.swift") if f != ROLLUP)
    if len(files) != 23:
        die("expected 23 per-vendor row files, found %d: %s" % (len(files), files))
    return files


def read_groups():
    text = open(GROUPS, encoding="utf-8").read()
    body = text.split("static let groups: [[String]] = [", 1)[1].split("\n    ]", 1)[0]
    groups = [re.findall(r'"([^"]+)"', line)
              for line in body.split("\n") if line.strip().startswith("[")]
    if len(groups) != 122:
        die("expected 122 groups in AliasGroups.swift, found %d" % len(groups))
    flat = [i for g in groups for i in g]
    if len(flat) != 209 or len(set(flat)) != 209:
        die("AliasGroups.swift does not partition 209 distinct ids")
    return groups


def read_file_rows(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    first = next((i for i, l in enumerate(lines) if l == "        CatalogModel("), None)
    if first is None:
        die("%s has no `CatalogModel(` row" % path)
    last = max(i for i, l in enumerate(lines) if l.startswith("            pollingEndpoint:"))
    head, foot = lines[:first], lines[last + 1:]
    span = lines[first:last + 1]
    if len(span) % ROW_LINES:
        die("%s: row span is %d lines, not a multiple of %d" % (path, len(span), ROW_LINES))
    rows = {}       # id -> block
    order = []       # ids in file order
    for n in range(0, len(span), ROW_LINES):
        b = span[n:n + ROW_LINES]
        if b[0] != "        CatalogModel(":
            die("%s row %d does not open with `CatalogModel(`" % (path, n // ROW_LINES + 1))
        m = re.fullmatch(r'            id: "([^"]+)",', b[1])
        if not m:
            die("%s row %d has no `id:` on its second line: %r" % (path, n // ROW_LINES + 1, b[1]))
        rid = m.group(1)
        if rid in rows:
            die("%s: id %s appears twice in the same file" % (path, rid))
        if b[2] != "            aliases: [],":
            die("%s: row %s does not carry `aliases: []` — already collapsed?" % (path, rid))
        rows[rid] = b
        order.append(rid)
    return head, rows, order, foot


def canonical(group):
    """The fully-qualified `vendor/model` spelling wins; ties break on reg() literal order, which
    is the order AliasGroups preserves inside each group. A group with no `/` at all has exactly
    one id (verified: 5 such groups, all singletons)."""
    qualified = [i for i in group if "/" in i]
    return qualified[0] if qualified else group[0]


def capability(block):
    return [l for l in block if not any(l.strip().startswith(p) for p in SKIP)]


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s)


def report_suspect_groups(groups):
    # A reg() group is a builder-sharing group, not an identity group. Flag any group where a
    # demoted id is not a spelling of the canonical modulo punctuation and vendor prefix, so a
    # human can decide whether it is a different product. Task 22's live /models fixture is the
    # mechanical decider; this is what gets it a list to decide over.
    n = 0
    for g in sorted(groups, key=canonical):
        c = canonical(g)
        odd = [a for a in g if a != c
               and not (norm(c).endswith(norm(a)) or norm(a).endswith(norm(c)))]
        if odd:
            n += 1
            print("%s\n    not a spelling of the canonical: %s" % (c, ", ".join(odd)))
    print("\n%d groups flagged for review" % n)


def patch_vendor_header(head, path):
    if STALE_VENDOR_HEADER[0] not in head:
        die("%s: the generated header is not the one this script was written against" % path)
    at = head.index(STALE_VENDOR_HEADER[0])
    if head[at:at + 3] != STALE_VENDOR_HEADER:
        die("%s: stale header lines found out of order" % path)
    return head[:at] + NEW_VENDOR_HEADER + head[at + 3:]


def main():
    groups = read_groups()

    if "--report-suspect-groups" in sys.argv:
        report_suspect_groups(groups)
        return

    files = vendor_files()
    id_to_file = {}
    file_data = {}          # path -> {"head": [...], "rows": {id: block}, "order": [...], "foot": [...]}
    for path in files:
        head, rows, order, foot = read_file_rows(path)
        for rid in rows:
            if rid in id_to_file:
                die("id %s appears in two files: %s and %s" % (rid, id_to_file[rid], path))
            id_to_file[rid] = path
        file_data[path] = {"head": head, "rows": rows, "order": order, "foot": foot}

    total = sum(len(fd["order"]) for fd in file_data.values())
    if total != 209:
        die("expected 209 rows across the 23 vendor files, found %d" % total)

    for g in groups:
        c = canonical(g)
        if c not in id_to_file:
            die("canonical %s of group %s has no generated row" % (c, g))
        cfile = id_to_file[c]
        base = capability(file_data[cfile]["rows"][c])
        for a in g:
            if a == c:
                continue
            if a not in id_to_file:
                die("alias %s of group %s has no generated row" % (a, g))
            if id_to_file[a] != cfile:
                die("group %s spans two files: %s is in %s, %s is in %s"
                    % (g, c, cfile, a, id_to_file[a]))
            for x, y in zip(base, capability(file_data[cfile]["rows"][a])):
                if x != y:
                    die("group %s: %s and %s disagree —\n    %s\n    %s"
                        % (g, c, a, x.strip(), y.strip()))

        aliases = sorted(i for i in g if i != c)
        block = list(file_data[cfile]["rows"][c])
        block[2] = "            aliases: [%s]," % ", ".join('"%s"' % a for a in aliases)
        file_data[cfile]["rows"][c] = block
        for a in g:
            if a != c:
                del file_data[cfile]["rows"][a]

    canonical_count = sum(len(fd["rows"]) for fd in file_data.values())
    if canonical_count != 122:
        die("expected 122 canonical rows after the collapse, found %d" % canonical_count)

    for path, fd in file_data.items():
        surviving_order = [rid for rid in fd["order"] if rid in fd["rows"]]
        body = [line for rid in surviving_order for line in fd["rows"][rid]]
        head = patch_vendor_header(fd["head"], path)
        open(path, "w", encoding="utf-8").write("\n".join(head + body + fd["foot"]))

    rollup = open(ROLLUP, encoding="utf-8").read()
    if STALE_ROLLUP_DOC not in rollup:
        die("%s: the roll-up doc comment is not the one this script was written against" % ROLLUP)
    open(ROLLUP, "w", encoding="utf-8").write(rollup.replace(STALE_ROLLUP_DOC, NEW_ROLLUP_DOC, 1))

    print("collapsed 209 rows to %d, %d alias spellings"
          % (canonical_count, sum(len(g) - 1 for g in groups)))


main()
