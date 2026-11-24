#!/bin/sh
# Full simulator pass on a Mac, or from another machine over ssh: unit tests, then the intro -> home -> camera -> keep -> expire ->
# clear flow and the straight-to-camera setting, in light and dark, checking the simulator's Photos database
# (not the app's word for it) after each step.
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

# Start from an empty screenshot folder, so old runs never pass for new ones.
if [ "$(uname)" = Darwin ]; then rm -f /tmp/tmp-sim-qa/*.png; else ssh "$HOST" 'rm -f /tmp/tmp-sim-qa/*.png'; fi

$S test TmpCameraTests

FIRST=1
for MODE in light dark; do
  echo "== $MODE"
  $S appearance $MODE
  # Fresh Photos permission on the first pass, so the real prompt (and our usage text) is seen once.
  [ $FIRST = 1 ] && $S photos-reset
  FIRST=0
  TMP_SHOT_TAG=$MODE $S test TmpCameraUITests/FlowUITests/test1_CaptureAndKeep
  $S log > "$OUT/$MODE-log-1.txt"
  $S album Tmp > "$OUT/$MODE-album-1.txt"
  cat "$OUT/$MODE-album-1.txt"
  TMP_SHOT_TAG=$MODE $S test TmpCameraUITests/FlowUITests/test2_ExpireAndClear
  $S log > "$OUT/$MODE-log-2.txt"
  $S album Tmp > "$OUT/$MODE-album-2.txt"
  cat "$OUT/$MODE-album-2.txt"
  python3 -I qa/check_album.py "$OUT/$MODE-log-2.txt" "$OUT/$MODE-album-1.txt" "$OUT/$MODE-album-2.txt" || FAILED=1
  TMP_SHOT_TAG=$MODE $S test TmpCameraUITests/FlowUITests/test3_StraightToCamera
done

if [ "$(uname)" = Darwin ]; then cp /tmp/tmp-sim-qa/*.png "$OUT/"; else scp -q "$HOST:/tmp/tmp-sim-qa/*.png" "$OUT/"; fi
echo "screenshots: $OUT"
[ $FAILED = 0 ] && echo "PASS: e2e" || { echo "FAIL: e2e album check"; exit 1; }
