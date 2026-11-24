# Tmp (temporary camera)

A small iPhone camera for throwaway photos. Shots are files inside the app's own container (never the Photos
library) and delete themselves, with no prompt, when their lifetime is up. Share sends the original file;
Save to Photos is the only PhotoKit code (add-only, asked when tapped). No networking code, no dependencies,
no analytics, no account. Home screen name "Tmp".

## Stack
- SwiftUI, Swift 5.10 language mode, iOS 17+, iPhone only, no third-party packages. AVFoundation, ImageIO,
  and PhotoKit for Save to Photos only.
- `ios/project.yml` generates the Xcode project with xcodegen (the `.xcodeproj` is git-ignored).
- Name and bundle id live in ONE place: `ios/Config/App.xcconfig` (`APP_DISPLAY_NAME`, `APP_BUNDLE_ID`).
  Scripts read the bundle id from there. Per-machine signing goes in git-ignored `ios/Config/Local.xcconfig`
  (`DEVELOPMENT_TEAM = ...`).
- The app lives in `ios/`. Builds and simulator runs happen on a Mac; from another machine the scripts
  copy the tree there over ssh.

## Code map
- `Model/Ledger.swift`: lifetimes, the ledger of shots (UUID, file name, capture time, expiry or none for
  Never), labels, the versioned JSON file in Application Support (an old or corrupt file loads empty).
  Pure logic, unit tested. Dates live here, never in file attributes.
- `Model/ShotStore.swift`: the photo files in `Application Support/Shots/` (excluded from backup, file
  protection `completeUnlessOpen`), written as the camera made them; ImageIO thumbnails kept in memory.
- `Photos/PhotoSaver.swift`: the only PhotoKit code. Save to Photos, add-only access.
- `Camera/Camera.swift`: `RealCamera` (AVFoundation on its own queue, rotation coordinator, full-size
  photos, a small preview delivered with each photo) and `MockCamera` (generated frames and JPEGs).
  `Camera/CaptureMath.swift`: the pure, tested parts (largest photo size, angle to Exif orientation,
  reading a photo's size and orientation).
  `Camera/DemoScenes.swift`: debug-only stand-in photos for App Store screenshots (`TMP_DEMO_PHOTOS`).
- `App/AppModel.swift`: state and actions. A shot shows (grid, counter, instant thumbnail) the moment the
  shutter is pressed, as `pending`, and joins the ledger once its file is written; a failed save takes it
  out again. Expiry sweep on launch, on return to the front and every second while open. Launch cleanup
  forgets shots whose file is gone and deletes files the ledger does not name. `App/QA.swift`: launch
  switches and the opt-in QA log.
- `Views/`: intro (first run), home (grid, summary, camera button), camera (full screen, stays open between
  shots, camera-off state), viewer (Share, Save to Photos, Delete), settings (lifetime, Delete all now).
  `App/TmpCameraApp.swift` picks intro or home.

## Commands (on a Mac, or from another machine with `TMP_MAC=<ssh host>`, default `mac`)
- Unit tests: `ios/scripts/ios-sim.sh test`
- Full simulator pass, light and dark, with the Shots folder and Photos database checks: `qa/e2e.sh /path/to/out`
- Run it: `TMP_TIME_SCALE=1440 TMP_QA_LOG=1 ios/scripts/ios-sim.sh`, then `shot NAME`, `log`, `files`, `library`.
  Always finish with `ios/scripts/ios-sim.sh shutdown`.
- Switches and what the flow proves: `qa/README.md`.
- App Store package (listing, privacy answers, review notes, screenshots, what is left): `store/`, start at
  `store/CHECKLIST.md`. Screenshots: `store/tools/shots.sh`.

## Rules
- Never add networking code, a dependency, analytics or crash reporting. The README says so; the grep
  and symbol checks in `qa/README.md` ("No network code") must keep printing nothing.
- README: short and plain, first person, no em dashes, no hype. Only what a stranger needs to decide to
  install or build it. No photo library access-level discussion.
- Only ever delete inside the Shots folder: files the ledger names, or (at launch) files it does not name.
  Never delete anything while the ledger file exists but cannot be read.
- Never read the Photos library. PhotoKit is used only by Save to Photos, with add-only access, asked
  when the user taps it. Camera access is asked when the camera first opens.
- The shutter never waits: a shot shows at once and saves in the background.
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
