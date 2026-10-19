#!/usr/bin/env python3
"""Delete keyed entries from ONE named dictionary block of a golden fixture. Deletions only.

    subtract_ids.py <file> <block-symbol> <row|block|extension> <ids-file> [--apply]

Modes:
  row        single-line entries:  `        "key": value,`
  block      nested entries:       `        "key": [` ... `        ],`
  extension  a `// MARK: - <key>` .. `extension <Enum> { ... }` section (GoldenPayloads tables)

Never anchors on indentation alone: `row` and `block` operate strictly between the
`    static let <block-symbol>` line and the first `    ]` after it, which is that
dictionary's own close. Every payload table in GoldenPayloads.swift uses the same
eight-space indentation for its probe keys, and an unscoped filter would delete them all.
"""
import re, sys

path, symbol, mode, ids_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
apply = "--apply" in sys.argv
targets = {l.strip().lower() for l in open(ids_file) if l.strip()}
if not targets:
    sys.exit("id list is empty — nothing to do")

lines = open(path).read().split("\n")
drop = set()

if mode in ("row", "block"):
    starts = [i for i, l in enumerate(lines) if l.startswith("    static let %s" % symbol)]
    if len(starts) != 1:
        sys.exit("expected exactly one `static let %s` in %s, found %d" % (symbol, path, len(starts)))
    start = starts[0]
    ends = [i for i in range(start + 1, len(lines)) if lines[i] == "    ]"]
    if not ends:
        sys.exit("no closing `    ]` found for %s" % symbol)
    end = ends[0]
    ROW = re.compile(r'^        "([^"]+)":\s')
    i = start + 1
    while i < end:
        m = ROW.match(lines[i])
        if m and m.group(1).lower() in targets:
            if mode == "row":
                drop.add(i)
            else:
                j = i
                while j < end and lines[j] != "        ],":
                    j += 1
                if j >= end:
                    sys.exit("unterminated nested entry for %s at line %d" % (m.group(1), i + 1))
                drop.update(range(i, j + 1))
                i = j
        i += 1
    print("%s [%s] lines %d..%d: %d lines to drop" % (path, symbol, start + 1, end + 1, len(drop)))
else:
    for name in targets:
        marks = [i for i, l in enumerate(lines) if l.strip() == "// MARK: - %s" % name]
        if len(marks) != 1:
            sys.exit("expected exactly one `// MARK: - %s` in %s, found %d" % (name, path, len(marks)))
        s = marks[0]
        ext = next(i for i in range(s, len(lines)) if lines[i].startswith("extension "))
        e = next(i for i in range(ext + 1, len(lines)) if lines[i] == "}")
        drop.update(range(s, e + 1))
        print("%s: `// MARK: - %s` section lines %d..%d" % (path, name, s + 1, e + 1))

if not apply:
    print("DRY RUN — pass --apply to write. Would remove %d lines." % len(drop))
    sys.exit(0)
open(path, "w").write("\n".join(l for i, l in enumerate(lines) if i not in drop))
print("wrote %s (%d lines removed)" % (path, len(drop)))
