"""Cross-check the app's QA log against the simulator's Photos database.

After capture: every saved shot and the seeded foreign photo are in the album, not trashed.
After Clear: the expired shots are trashed (Recently Deleted); the kept shot and the foreign photo are not.
Usage: check_album.py LOG ALBUM_AFTER_CAPTURE ALBUM_AFTER_CLEAR
"""
import re
import sys


def uuid(local_id):
    return local_id.split("/")[0]


def album(path):
    rows = {}
    for line in open(path):
        m = re.match(r"^([0-9A-F-]{36})\s+(\d)\s", line)
        if m:
            rows[m.group(1)] = int(m.group(2))
    return rows


log = open(sys.argv[1]).read()
before, after = album(sys.argv[2]), album(sys.argv[3])
saved = [uuid(x) for x in re.findall(r"saved (\S+) album=", log)]
kept = [uuid(x) for x in re.findall(r"kept (\S+)", log)]
foreign = [uuid(x) for x in re.findall(r"seeded foreign photo (\S+)", log)]
cleared = [s for s in saved if s not in kept]

problems = []
if len(saved) != 3 or len(kept) != 1 or len(foreign) != 1:
    problems.append(f"log: expected 3 saved, 1 kept, 1 foreign; got {len(saved)}, {len(kept)}, {len(foreign)}")
for u in saved + foreign:
    if before.get(u) != 0:
        problems.append(f"after capture: {u} not in the album (state {before.get(u)})")
for u in kept + foreign:
    if after.get(u) != 0:
        problems.append(f"after clear: {u} should still be in the album (state {after.get(u)})")
for u in cleared:
    if u in after and after[u] != 1:
        problems.append(f"after clear: expired shot {u} still in the library")
untouched = [u for u, s in before.items() if s == 0 and u not in saved + foreign]
for u in untouched:
    if after.get(u) != 0:
        problems.append(f"after clear: older photo {u} was touched")

if problems:
    print("FAIL:\n  " + "\n  ".join(problems))
    sys.exit(1)
print(f"OK: 3 shots landed in the album; Clear removed {len(cleared)} expired shots; "
      f"the kept shot, the foreign photo and {len(untouched)} older album photos survived")
