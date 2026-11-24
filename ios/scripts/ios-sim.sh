#!/bin/sh
# The app in the iOS simulator with its QA switches. Runs on the Mac. From another machine it copies this working
# tree (committed or not) to the Mac at ~/.cache/tmp-camera-pc/<dir name> and runs there over ssh.
#
#   ios-sim.sh [run]               build, install, launch with the TMP_* switches
#   ios-sim.sh build               xcodegen, build for the simulator, install
#   ios-sim.sh launch              relaunch without building
#   ios-sim.sh test [--fresh] [T...]  xcodebuild test, -only-testing T (default TmpCameraTests), PASS/FAIL line
#                                  --fresh uninstalls the app first, so first-run state is exercised
#   ios-sim.sh shot NAME           screenshot to /tmp/tmp-sim-qa/NAME.png on the Mac
#   ios-sim.sh appearance light|dark
#   ios-sim.sh statusbar [clear]   9:41, full battery and bars (App Store screenshots); clear undoes it
#   ios-sim.sh photos-reset        revoke Photos and camera access (the next shot asks again)
#   ios-sim.sh album [NAME]        what is in album NAME (default Tmp) in the simulator's Photos database
#   ios-sim.sh log                 the app's Documents/tmp.log (needs TMP_QA_LOG=1)
#   ios-sim.sh udid | shutdown
#
# Simulator by name: SIM_NAME (default "Tmp iPhone 16 iOS18"), created on first use as an iPhone 16 on the
# newest iOS 18 runtime (SIM_RUNTIME=<runtime id> and SIM_DEVICE=<device type, e.g. iPhone-17-Pro-Max> to
# override). No other simulator is touched.
# Every TMP_* variable reaches the app as SIMCTL_CHILD_TMP_* (and UI tests as TEST_RUNNER_TMP_*):
#   TMP_TIME_SCALE=3600 TMP_QA_LOG=1 ios/scripts/ios-sim.sh
# Switches are listed in qa/README.md.
# Script settings, not passed to the app: TMP_MAC (ssh host, default mac) and TMP_MAC_REPO
# (a Mac checkout to use as is instead of copying).
set -eu

q() { printf "'%s'" "$(printf %s "$1" | sed "s/'/'\\\\''/g")"; }   # quote one word for a remote shell
app_vars() { env | sed -n 's/^\(TMP_[A-Za-z0-9_]*\)=.*/\1/p' | grep -vxE 'TMP_MAC|TMP_MAC_REPO' || true; }

if [ "$(uname)" != Darwin ]; then
  HOST=${TMP_MAC:-mac}
  TOP=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
  if [ -n "${TMP_MAC_REPO:-}" ]; then
    R=$TMP_MAC_REPO
  else
    R=.cache/tmp-camera-pc/$(basename "$TOP")
    ssh "$HOST" "mkdir -p $R" || { echo "FAIL: ssh $HOST"; exit 1; }
    rsync -a --delete --exclude=.git --exclude=.claude/ --exclude-from="$TOP/.gitignore" "$TOP/" "$HOST:$R/" \
      || { echo "FAIL: copying the tree to $HOST:$R"; exit 1; }
  fi
  ENVS=""
  for n in $(app_vars) SIM_NAME SIM_RUNTIME SIM_DEVICE; do
    eval "v=\${$n-}"; eval "set_=\${$n+x}"
    [ -n "$set_" ] && ENVS="$ENVS $n=$(q "$v")"
  done
  ARGS=""
  for a in "$@"; do ARGS="$ARGS $(q "$a")"; done
  exec ssh "$HOST" "cd $R && env$ENVS sh ios/scripts/ios-sim.sh$ARGS"
fi

export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
export GIT_CONFIG_GLOBAL=/dev/null LANG=en_US.UTF-8
cd "$(dirname "$0")/.."
NAME=${SIM_NAME:-Tmp iPhone 16 iOS18}
BUNDLE=$(sed -n 's/^APP_BUNDLE_ID *= *//p' Config/App.xcconfig)
DD=build/sim
APP=$DD/Build/Products/Debug-iphonesimulator/TmpCamera.app
QA=/tmp/tmp-sim-qa
mkdir -p build

udid() {
  xcrun simctl list devices -j | jq -r --arg n "$NAME" \
    '[.devices[][] | select(.name == $n and (.isAvailable // true))][0].udid // empty'
}
U=$(udid)
if [ -z "$U" ]; then
  RT=${SIM_RUNTIME:-$(xcrun simctl list runtimes -j | jq -r '[.runtimes[] | select(.platform == "iOS" and .isAvailable)]
    | (map(select(.version | startswith("18."))) | last) // last | .identifier')}
  U=$(xcrun simctl create "$NAME" "com.apple.CoreSimulator.SimDeviceType.${SIM_DEVICE:-iPhone-16}" "$RT")
  echo "created simulator $NAME ($U) on $RT"
fi

boot() { xcrun simctl boot "$U" 2>/dev/null || true; xcrun simctl bootstatus "$U" -b >/dev/null; }
gen() { xcodegen generate --quiet >/dev/null || { echo "FAIL: xcodegen generate"; exit 1; }; }
xb() {
  xcodebuild -project TmpCamera.xcodeproj -scheme TmpCamera -configuration Debug -destination "id=$U" \
    -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO "$@"
}
build() {
  gen; boot
  LOG=build/sim-build.log
  if ! xb build > "$LOG" 2>&1; then
    grep -E '(^|: )error:|\*\* BUILD FAILED' "$LOG" | head -20
    echo "FAIL: simulator build (full log: $(pwd)/$LOG)"; exit 1
  fi
  grep -E ': warning:' "$LOG" | sed 's/^.*TmpCamera\//TmpCamera\//' | sort -u | head -20 || true
  xcrun simctl install "$U" "$APP"
  echo "built and installed on $NAME ($U)"
}
launch() {
  boot
  xcrun simctl terminate "$U" "$BUNDLE" 2>/dev/null || true
  SW=""
  for n in $(app_vars); do
    eval "v=\${$n}"
    export "SIMCTL_CHILD_$n=$v"
    SW="$SW $n=$v"
  done
  xcrun simctl launch "$U" "$BUNDLE" >/dev/null
  echo "launched on $NAME with${SW:- no switches}"
}
container() { xcrun simctl get_app_container "$U" "$BUNDLE" data; }
photos_db() { echo "$HOME/Library/Developer/CoreSimulator/Devices/$U/data/Media/PhotoData/Photos.sqlite"; }

# Lists the assets in a user album straight from the simulator's Photos database (not through the app):
# uuid, trashed state (0 = in library, 1 = Recently Deleted), file name, created date.
album() {
  DB=$(photos_db)
  [ -f "$DB" ] || { echo "no Photos database yet"; return 0; }
  # The album-to-asset join table is Z_<n>ASSETS with columns Z_<n>ALBUMS and Z_<m>ASSETS; n and m vary by iOS.
  num() { echo "(name GLOB '$1' OR name GLOB '$2')"; }
  JT=$(sqlite3 "$DB" "SELECT m.name FROM sqlite_master m WHERE m.type = 'table' AND EXISTS (SELECT 1 FROM
    pragma_table_info(m.name) WHERE $(num 'Z_[0-9]ALBUMS' 'Z_[0-9][0-9]ALBUMS'))
    AND EXISTS (SELECT 1 FROM pragma_table_info(m.name) WHERE $(num 'Z_[0-9]ASSETS' 'Z_[0-9][0-9]ASSETS'))" | head -1)
  [ -n "$JT" ] || { echo "FAIL: album join table not found in $DB"; return 1; }
  AC=$(sqlite3 "$DB" "SELECT name FROM pragma_table_info('$JT') WHERE $(num 'Z_[0-9]ALBUMS' 'Z_[0-9][0-9]ALBUMS')")
  SC=$(sqlite3 "$DB" "SELECT name FROM pragma_table_info('$JT') WHERE $(num 'Z_[0-9]ASSETS' 'Z_[0-9][0-9]ASSETS')")
  sqlite3 -header -column "$DB" "
    SELECT a.ZUUID AS uuid, a.ZTRASHEDSTATE AS trashed, a.ZFILENAME AS file,
           datetime(a.ZDATECREATED + 978307200, 'unixepoch') AS created
    FROM ZGENERICALBUM g JOIN $JT j ON j.$AC = g.Z_PK JOIN ZASSET a ON a.Z_PK = j.$SC
    WHERE g.ZTITLE = '$1' AND g.ZTRASHEDSTATE = 0 ORDER BY a.ZDATECREATED;"
  echo "albums named '$1': $(sqlite3 "$DB" "SELECT count(*) FROM ZGENERICALBUM WHERE ZTITLE = '$1' AND ZTRASHEDSTATE = 0")"
  echo "library: $(sqlite3 "$DB" "SELECT count(*) FROM ZASSET WHERE ZTRASHEDSTATE = 0") photos, $(sqlite3 "$DB" "SELECT count(*) FROM ZASSET WHERE ZTRASHEDSTATE = 1") in Recently Deleted"
}

CMD=${1:-run}
[ $# -gt 0 ] && shift
case "$CMD" in
  run) build; launch ;;
  build) build ;;
  launch) launch ;;
  test)
    FRESH=0
    if [ "${1:-}" = --fresh ]; then FRESH=1; shift; fi
    [ $# -gt 0 ] || set -- TmpCameraTests
    gen; boot
    [ $FRESH = 1 ] && { xcrun simctl uninstall "$U" "$BUNDLE" 2>/dev/null || true; }
    for n in $(app_vars); do eval "export TEST_RUNNER_$n=\"\${$n}\""; done
    ONLY=""
    for t in "$@"; do ONLY="$ONLY -only-testing:$t"; done
    STAMP=$(date +%Y%m%d-%H%M%S)
    LOG=build/test-$STAMP.log
    RB=build/results/test-$STAMP.xcresult
    mkdir -p build/results
    START=$(date +%s)
    # shellcheck disable=SC2086
    xb test $ONLY -resultBundlePath "$RB" > "$LOG" 2>&1 && RC=0 || RC=$?
    SECS=$(( $(date +%s) - START ))
    grep -E "Test Case .* (passed|failed)|[✔✘] Test|(^|: )error:|XCTAssert" "$LOG" | sed 's/^.*Test Case/Test Case/' | head -200 || true
    SUM=$(xcrun xcresulttool get test-results summary --path "$RB" --compact 2>/dev/null \
      | jq -r '"\(.passedTests) passed, \(.failedTests) failed, \(.skippedTests) skipped"' 2>/dev/null || true)
    if [ $RC = 0 ]; then
      echo "PASS: $* on $NAME: ${SUM:-ok} (${SECS}s)"
    else
      grep -E '(^|: )error:|\*\* (BUILD|TEST) FAILED' "$LOG" | sort -u | head -10 || true
      echo "FAIL: $* on $NAME: ${SUM:-xcodebuild exit $RC} (${SECS}s). Log: $(pwd)/$LOG  Results: $(pwd)/$RB"
      exit 1
    fi ;;
  shot) mkdir -p "$QA"; xcrun simctl io "$U" screenshot "$QA/${1:-shot}.png" >/dev/null && echo "$QA/${1:-shot}.png" ;;
  appearance) boot; xcrun simctl ui "$U" appearance "${1:-light}"; echo "appearance ${1:-light}" ;;
  statusbar)
    boot
    if [ "${1:-}" = clear ]; then
      xcrun simctl status_bar "$U" clear; echo "status bar cleared"
    else
      xcrun simctl status_bar "$U" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
        --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
      echo "status bar 9:41, full"
    fi ;;
  photos-reset)
    boot
    xcrun simctl privacy "$U" reset photos "$BUNDLE" 2>/dev/null || true
    xcrun simctl privacy "$U" reset camera "$BUNDLE" 2>/dev/null || true
    echo "Photos and camera access reset" ;;
  album) album "${1:-Tmp}" ;;
  log) cat "$(container)/Documents/tmp.log" ;;
  udid) echo "$U" ;;
  shutdown) xcrun simctl shutdown "$U" 2>/dev/null || true; echo "shut down $NAME" ;;
  *) sed -n '2,26p' "$0"; exit 2 ;;
esac
