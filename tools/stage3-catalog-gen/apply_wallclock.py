#!/usr/bin/env python3
"""Stage 3 Task 13 — write typicalWallClock onto the 74 canonical video rows.

The value is GENERATION TIME in seconds, per family. The table below is
ModelRegistry.typicalDurationsByFamily's 11 substring tokens re-expressed against the families
Task 12 authored, so no video row changes the range the app showed on 2026-07-27.

STRICT: aborts if a video row's family is not in the table, if a non-video row would be touched,
if a table family matches no row, or if the number of video rows is not 74. Run from the
repository root:

    python3 tools/stage3-catalog-gen/apply_wallclock.py
"""
import glob
import re

# family -> the Swift literal written into the row. "nil" is a value, not a gap: the old token
# table had no entry for these two families and this stage does not invent one.
BY_FAMILY = {
    "Veo 2": "120...300", "Veo 3": "120...300", "Veo 3.1": "120...300",
    "Sora 2": "120...360",
    "Kling 1.0": "180...480", "Kling 1.6": "180...480", "Kling 2.0": "180...480",
    "Kling 2.1": "180...480", "Kling 2.5": "180...480", "Kling 2.6": "180...480",
    "Kling 3.0": "180...480", "Kling O1": "180...480",
    "Wan 2.1": "120...360", "Wan 2.2": "120...360", "Wan 2.5": "120...360",
    "Wan 2.6": "120...360", "Wan 2.7": "120...360",
    "Seedance 1.0": "120...300", "Seedance 1.5": "120...300", "Seedance 2.0": "120...300",
    "MiniMax Hailuo": "180...480", "MiniMax Video": "180...480",
    "Luma Ray": "60...240",
    "Runway Gen-3": "60...180", "Runway Gen-4": "60...180",
    "PixVerse V5": "60...180", "PixVerse V5.5": "60...180",
    "LTX Video 2": "60...180",
    "OmniHuman": "nil",
    "Kandinsky 5": "nil",
}

MODELS = "Packages/GenStationCore/Sources/GenStationCore/Catalog/Models/*.swift"

ROW_START = re.compile(r"^(\s*)CatalogModel\($")
ID = re.compile(r'^\s*id: "([^"]+)",$')
FAMILY = re.compile(r'^\s*family: "(.*)",$')
TASK = re.compile(r"^\s*task: \.(\w+),$")
WALLCLOCK = re.compile(r"^(\s*)typicalWallClock: .*,$")


def die(msg):
    raise SystemExit("ABORT — " + msg)


used = set()
video_rows = 0
image_rows = 0
touched = []

for path in sorted(glob.glob(MODELS)):
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

        def only(regex, label):
            hits = [k for k in block if regex.match(lines[k])]
            if len(hits) != 1:
                die("%s:%d — expected exactly one `%s` line, found %d"
                    % (path, start + 1, label, len(hits)))
            return hits[0]

        row_id = ID.match(lines[only(ID, "id:")]).group(1)
        family = FAMILY.match(lines[only(FAMILY, "family:")]).group(1)
        task = TASK.match(lines[only(TASK, "task:")]).group(1)
        wc = only(WALLCLOCK, "typicalWallClock:")

        if task != "video":
            image_rows += 1
            if not lines[wc].strip().endswith("nil,"):
                die("%s:%d — non-video row %s carries a wall clock" % (path, start + 1, row_id))
            i = j
            continue

        if family not in BY_FAMILY:
            die("%s:%d — video row %s has family %r, which is not in BY_FAMILY"
                % (path, start + 1, row_id, family))
        indent = WALLCLOCK.match(lines[wc]).group(1)
        lines[wc] = "%stypicalWallClock: %s," % (indent, BY_FAMILY[family])
        used.add(family)
        video_rows += 1
        changed = True
        i = j

    if changed:
        open(path, "w", encoding="utf-8").write("\n".join(lines))
        touched.append(path)

unused = sorted(set(BY_FAMILY) - used)
if unused:
    die("%d families matched no video row: %s" % (len(unused), ", ".join(unused)))
if video_rows != 74:
    die("patched %d video rows, expected 74" % video_rows)
print("patched %d video rows across %d files (%d non-video rows left nil)"
      % (video_rows, len(touched), image_rows))
