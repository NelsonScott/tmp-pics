# QA

The simulator has no camera, so the app has a mock camera and a fast clock. Everything here runs on the
Mac; from another machine the scripts copy the working tree over ssh first.

## Commands

- Unit tests (ledger, expiry, photo files, thumbnails, the shutter-to-saved model steps): `ios/scripts/ios-sim.sh test`
- Full pass, light and dark, checking the app's Shots folder and the Photos database: `qa/e2e.sh [OUT_DIR]`
  (about 12 minutes). Screenshots land in OUT_DIR (default `qa/out/`, git-ignored). Shuts the simulator down
  at the end.
- Poke at it by hand: `TMP_TIME_SCALE=1440 TMP_QA_LOG=1 ios/scripts/ios-sim.sh`, then
  `ios-sim.sh shot NAME`, `ios-sim.sh log`, `ios-sim.sh files` (the Shots folder and whether it is backed
  up), `ios-sim.sh library` (photo count in Photos), and `ios-sim.sh shutdown` when done.

`TMP_MAC=host` picks the Mac (default `mac`, an ssh host alias).

## Launch switches

Environment variables. `ios-sim.sh` passes every `TMP_*` variable to the app (as `SIMCTL_CHILD_TMP_*`)
and to UI tests (as `TEST_RUNNER_TMP_*`). All are off in a normal launch.

| Switch | Effect |
| --- | --- |
| `TMP_MOCK_CAMERA=1` | Generated frames in the viewfinder; the shutter renders a real JPEG with a counter and time. On by default in the simulator (`=0` turns it off). |
| `TMP_TIME_SCALE=N` | Lifetimes run N times faster. 1440 makes 24 hours last 60 seconds; 3600 makes an hour last a second. |
| `TMP_LIFETIME=oneHour` | Start with this lifetime (`oneHour`, `oneDay`, `threeDays`, `sevenDays`, `never`). |
| `TMP_RESET=1` | Delete every shot (files and ledger), settings and the QA log at launch. |
| `TMP_QA_LOG=1` | Write `Documents/tmp.log` (identifiers and events only). Read it with `ios-sim.sh log`. |
| `TMP_DEMO_PHOTOS=1` | Debug builds only, for App Store screenshots. The mock camera shows and saves stand-in photos (`Camera/DemoScenes.swift`: a parking level sign, a receipt, a router sticker, a test page, a sticky note, a paint chip) instead of numbered test frames, and hides the "Test mode" pill and Settings' Testing section. |
| `TMP_DEMO_AGES=20,16,12.5` | Debug builds only. Backdates the capture time of shot 1, 2, 3... of a camera visit by that many hours, so the grid shows real times left without the fast clock, whose times read in seconds. |
| `TMP_SHOT_TAG=light` | UI tests only: prefix for screenshot names. |
| `TMP_STORE_SHOTS=1` | UI tests only: runs `StoreShotsUITests` (skipped otherwise). Use `store/tools/shots.sh`. |

## What `qa/e2e.sh` proves

1. `test1_CaptureShareSaveDelete`: fresh start shows the intro once, then the empty home screen. The camera
   button opens the camera; three mock shots, with no permission prompt, and the camera stays open with the
   counter at 3. Done goes home, where the grid shows three shots and the summary line. In the viewer: Share
   opens the share sheet with the original file (its name and size show at the top), Save to Photos shows the
   real add-only prompt (first pass) and then "Saved to Photos", Delete asks once and removes the shot. Then
   settings and How it works.
2. `ios-sim.sh files` reads the app's Shots folder straight from the simulator: two files, and the folder is
   excluded from backup. `ios-sim.sh library` reads the simulator's `Photos.sqlite`: Save to Photos added
   exactly one photo.
3. `test2_ExpireByThemselves`: on the home screen the fast clock (24 hours in 2 minutes) runs out and the
   grid empties by itself, with no banner and no prompt. The Shots folder is then empty and the Photos
   library unchanged.
4. `test3_StraightToCamera`: with "Open straight to camera" on, a relaunch lands in the camera and Done
   goes home; switched off again, a relaunch lands on home.
5. `test4_DeleteAll`: two shots, Settings, Delete all photos now, confirm: the grid and the folder are empty.
6. `test5_CameraAccessOff`: the real camera with access refused at the system prompt shows "Camera access is
   off" and Open Settings, and the shutter is disabled.

Screenshots are numbered in flow order (`light-01-intro.png` to `dark-18-camera-off.png`). Look at
them: the tests check behaviour, not alignment, clipping or contrast.

## Instant thumbnail

The shot appears (counter, camera thumbnail, home grid) in the same frame as the shutter press, before the
photo is processed or written: `AppModel.shoot` adds it as `pending` with the camera's instant picture
before its first `await`. The mock camera draws the frame it is about to save; the real camera shows a grey
square for the moment until the photo's own small preview (`previewPhotoFormat`) arrives with the capture,
then the ImageIO thumbnail takes over once the file is written. `AppModelTests` checks the steps (shown
before the file exists, withdrawn if the save fails, three quick taps all show at once). To see it, record the
simulator (`xcrun simctl io <udid> recordVideo`) while a UI test taps the shutter and step through the frames.

## App Store screenshots

`store/tools/shots.sh` runs `StoreShotsUITests` on an iPhone 17 Pro Max iOS 26 simulator (its own, created on
first use) with `TMP_DEMO_PHOTOS` and a 9:41 status bar (`ios-sim.sh statusbar`), then captions the shots with
`store/tools/captions.py`. Details in `store/CHECKLIST.md`.

## What the simulator cannot show

Real camera (preview, flash, flip, zoom, orientation, photo size, how soon the photo's preview arrives),
launch speed on a phone, and file protection (the simulator does not enforce it). Check those on a device
with the list below.

## Device checklist (camera)

Rotation and size are set in `RealCamera` (`Camera/Camera.swift`); the pure parts are in
`Camera/CaptureMath.swift` and its tests. For each photo, tap Save to Photos, then open it in Photos and
swipe up for the size.

1. Preview, portrait, back camera: hold the phone upright and point at a door frame. Vertical lines are
   vertical on screen, and moving the phone left moves the picture the natural way. Same after Flip.
2. Preview while turning: rotate the phone to landscape and back. The app UI stays portrait (like the system
   Camera's controls), and the scene in the viewfinder stays level with the world, never sideways.
3. Saved photo, back camera, in each of portrait, landscape with the top of the phone to the left,
   landscape with the top to the right: open each in Photos. All three are upright, the landscape ones are
   wider than tall, and the portrait one is taller than wide.
4. Front camera, portrait and one landscape: the preview is mirrored (like the system Camera), the saved
   photo is NOT mirrored (writing on a shirt or a page reads correctly), and it is upright.
5. Phone flat, pointing down at a page on a table: take one shot holding it in portrait, one in landscape.
   Compare with the same two shots in the system Camera; Tmp should match it.
6. Size: the Photos info panel for a back-camera shot shows the main camera's full size (48 MP, 8064 x 6048,
   on an iPhone 14 Pro or any iPhone 15 or later; 12 MP, 4032 x 3024, on older ones). Front: 12 MP.
7. Speed: five quick shutter taps in a row all save (counter reaches 5), with no long freeze. Each tap shows
   its thumbnail at once (grey for a moment at most, then the picture).
8. Launch: from a cold start the home screen appears with no white or black flash in light and dark, and
   the camera opens in well under a second once camera access is granted.
9. Share a back-camera shot to Files or AirDrop it to a Mac: the file is the full-size HEIC, upright.
10. Take a shot, lock the phone at once, unlock: the shot is there. Lock the phone with the app open and
    unlock after a minute: thumbnails and the viewer still load.

With `TMP_QA_LOG=1` set in the Xcode scheme, each shot also logs its rotation angle, the Exif orientation
expected for it, and what the saved data actually has, for example
`camera: back angle=90 expect exif=6 got 8064x6048 (48.8 MP) exif=6 upright=portrait`.

## No network code

The README promises no network code and no dependencies. These must print nothing:

```sh
grep -rnE "URLSession|URLRequest|NWConnection|import Network|CFNetwork|WebKit|Socket|https?://" ios/TmpCamera --include="*.swift"
nm -u TmpCamera.app/TmpCamera* | grep -iE "urlsession|nwconnection|nw_|socket|getaddrinfo"
```

`otool -L TmpCamera.app/TmpCamera*` lists only Apple system frameworks, and `ios/project.yml` has no
package section. The privacy manifest (`ios/TmpCamera/Resources/PrivacyInfo.xcprivacy`) declares no
tracking and no collected data; its only required-reason API is UserDefaults (CA92.1). Capture and expiry
dates live in the ledger, so the app reads no file timestamps, and it does not check disk space. This must
print nothing:

```sh
grep -rnE "creationDate|modificationDate|contentModificationDate|attributesOfItem|volumeAvailableCapacity|systemFreeSize|systemUptime|\bstat\(" ios/TmpCamera --include="*.swift" | grep -v "request.creationDate ="
```

(`request.creationDate` in `PhotoSaver` sets the date of the photo added to Photos; it reads nothing.)
