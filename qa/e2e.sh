#!/bin/sh
# Full simulator pass on a Mac, or from another machine over ssh: unit tests, then intro -> home -> camera ->
# share -> save to Photos -> delete -> expire by themselves -> straight to camera -> delete all -> camera access
# off, in light and dark. Between steps it reads the app's Shots folder and the simulator's Photos database
# directly (not the app's word for it).
#   qa/e2e.sh [OUT_DIR]     default OUT_DIR: qa/out (git-ignored). TMP_MAC=host to pick the Mac.
# Shuts the simulator down at the end.
set -eu
cd "$(dirname "$0")/.."
OUT=${1:-qa/out}
mkdir -p "$OUT"
S=ios/scripts/ios-sim.sh
HOST=${TMP_MAC:-mac}
FAILED=0
trap '$S shutdown >/dev/null 2>&1 || true' EXIT

fail() { echo "FAIL: $*"; FAILED=1; }
photo_files() { grep -cE '\.(jpg|heic)$' "$1" || true; }
library_count() { $S library | sed -n 's/^library: \([0-9]*\) photos.*/\1/p'; }

# Start from an empty screenshot folder, so old runs never pass for new ones.
if [ "$(uname)" = Darwin ]; then rm -f /tmp/tmp-sim-qa/*.png; else ssh "$HOST" 'rm -f /tmp/tmp-sim-qa/*.png'; fi

$S test TmpCameraTests

FIRST=1
for MODE in light dark; do
  echo "== $MODE"
  $S appearance $MODE
  # Fresh permissions on the first pass, so the real Save to Photos prompt (and our usage text) is seen once.
  [ $FIRST = 1 ] && $S photos-reset
  FIRST=0
  BEFORE=$(library_count)
  TMP_SHOT_TAG=$MODE $S test TmpCameraUITests/FlowUITests/test1_CaptureShareSaveDelete
  $S log > "$OUT/$MODE-log-1.txt"
  $S files > "$OUT/$MODE-files-1.txt"
  cat "$OUT/$MODE-files-1.txt"
  AFTER=$(library_count)
  # Three taken, one deleted: two files. Save to Photos added exactly one photo to the library.
  [ "$(photo_files "$OUT/$MODE-files-1.txt")" = 2 ] || fail "$MODE: expected 2 files after test1"
  grep -qx "backup: excluded" "$OUT/$MODE-files-1.txt" || fail "$MODE: the Shots folder is not excluded from backup"
  [ "$AFTER" = $((BEFORE + 1)) ] || fail "$MODE: library went from $BEFORE to $AFTER photos, expected +1"
  echo "library: $BEFORE -> $AFTER photos"

  TMP_SHOT_TAG=$MODE $S test TmpCameraUITests/FlowUITests/test2_ExpireByThemselves
  $S log > "$OUT/$MODE-log-2.txt"
  $S files > "$OUT/$MODE-files-2.txt"
  # Expired: files gone too, and the library is untouched (the app never deletes from Photos).
  [ "$(photo_files "$OUT/$MODE-files-2.txt")" = 0 ] || fail "$MODE: files left after expiry: $(cat "$OUT/$MODE-files-2.txt")"
  grep -q "expired " "$OUT/$MODE-log-2.txt" || fail "$MODE: no expiry in the log"
  [ "$(library_count)" = "$AFTER" ] || fail "$MODE: the Photos library changed during expiry"

  TMP_SHOT_TAG=$MODE $S test TmpCameraUITests/FlowUITests/test3_StraightToCamera
  TMP_SHOT_TAG=$MODE $S test TmpCameraUITests/FlowUITests/test4_DeleteAll
  $S files > "$OUT/$MODE-files-4.txt"
  [ "$(photo_files "$OUT/$MODE-files-4.txt")" = 0 ] || fail "$MODE: files left after Delete all"
  TMP_SHOT_TAG=$MODE $S test TmpCameraUITests/FlowUITests/test5_CameraAccessOff
done

if [ "$(uname)" = Darwin ]; then cp /tmp/tmp-sim-qa/*.png "$OUT/"; else scp -q "$HOST:/tmp/tmp-sim-qa/*.png" "$OUT/"; fi
echo "screenshots: $OUT"
[ $FAILED = 0 ] && echo "PASS: e2e" || { echo "FAIL: e2e"; exit 1; }
