# Tmp (temporary camera)

A small iPhone camera for throwaway photos. Shots go into one Photos album and expire; the app tracks
only the assets it created and clears expired ones with one batched delete (iOS confirms). No networking code, no dependencies, no analytics, no account. Home screen name "Tmp".

## Stack
- SwiftUI, Swift 5.10 language mode, iOS 17+, iPhone only, no third-party packages. AVFoundation and PhotoKit.
- `ios/project.yml` generates the Xcode project with xcodegen (the `.xcodeproj` is git-ignored).
- Name and bundle id live in ONE place: `ios/Config/App.xcconfig` (`APP_DISPLAY_NAME`, `APP_BUNDLE_ID`).
  Scripts read the bundle id from there. Per-machine signing goes in git-ignored `ios/Config/Local.xcconfig`
  (`DEVELOPMENT_TEAM = ...`).
- The app lives in `ios/`. Builds and simulator runs happen on a Mac; from another machine the scripts
  copy the tree there over ssh.

## Code map
- `Model/Ledger.swift`: lifetimes, the ledger of tracked shots (PhotoKit local identifier, capture time,
  expiry), labels, the JSON file in Application Support. Pure logic, unit tested.
- `Photos/PhotoLibrary.swift`: every PhotoKit call (access, save into album, find or create album,
  batched delete, thumbnails).
- `Camera/Camera.swift`: `RealCamera` (AVFoundation on its own queue, rotation coordinator, full-size
  photos) and `MockCamera` (generated frames and JPEGs). `Camera/CaptureMath.swift`: the pure, tested parts
  (largest photo size, angle to Exif orientation, reading a photo's size and orientation).
- `App/AppModel.swift`: state and actions. `App/QA.swift`: launch switches and the opt-in QA log.
- `Views/`: intro (first run), home (grid, summary, expired banner, camera button), camera (full screen,
  stays open between shots), viewer, settings. `App/TmpCameraApp.swift` picks intro or home.

## Commands (on a Mac, or from another machine with `TMP_MAC=<ssh host>`, default `mac`)
- Unit tests: `ios/scripts/ios-sim.sh test`
- Full simulator pass, light and dark, with the Photos database check: `qa/e2e.sh /path/to/out`
- Run it: `TMP_TIME_SCALE=1440 TMP_QA_LOG=1 ios/scripts/ios-sim.sh`, then `shot NAME`, `log`, `album Tmp`.
  Always finish with `ios/scripts/ios-sim.sh shutdown`.
- Switches and what the flow proves: `qa/README.md`.

## Rules
- Never add networking code, a dependency, analytics or crash reporting. The README says so; the grep
  and symbol checks in `qa/README.md` ("No network code") must keep printing nothing.
- README: short and plain, first person, no em dashes, no hype. Only what a stranger needs to decide to
  install or build it. No photo library access-level discussion.
- Only delete identifiers from the ledger. Never fetch-and-delete by album, date or anything else.
- One `performChanges` per user action that deletes, so iOS asks once.
- Ask for Photos access on the first shot, not at launch. Camera access is asked when the camera first opens.
- The launch screen colour (`LaunchBackground`) must equal the home and intro background (system
  background: white / black) so launch has no flash.
- Any new required-reason API (file timestamps, disk space, boot time, etc.) needs an entry in
  `ios/TmpCamera/Resources/PrivacyInfo.xcprivacy`.
- UI copy short and plain, no em dashes. The camera screen and viewer are always dark; intro, home and
  settings follow the system. Filled buttons are the bright yellow with black content; accent-coloured text
  uses AccentColor (darker in light mode for 4.5:1 contrast).
- Do not install on a real phone or touch App Store Connect unless asked.

## Done means
Unit tests pass, `qa/e2e.sh` prints `PASS: e2e`, you looked at the light and dark screenshots it made,
README claims still match the code, and the work is committed. Real-camera behaviour needs a device check
(see "What the simulator cannot show" in `qa/README.md`).
