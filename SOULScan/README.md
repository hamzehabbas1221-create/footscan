# SOUL Scan

Native iPhone prototype for guided **TrueDepth foot scanning**, built for the SOUL custom-insole workflow. This package contains the app source and a ready-to-open Xcode project. It is **not an installable IPA or an App Store release**.

## What is built

- Black-and-white SOUL interface using your wordmark.
- Left/right foot selection, activity and optional fitting reference.
- Actual front TrueDepth capture through AVFoundation, with permission and unsupported-device states.
- Live depth point-cloud preview, distance guidance, spoken countdown and scanning cues.
- Lens-calibrated unprojection, foreground/range and depth-edge filtering.
- On-device geometric alignment and voxel fusion; poor matches are rejected and repeated stationary frames do not inflate the scan.
- Pause, resume, finish, discard and interruption handling.
- Local scan library, 3D orbit/zoom, diagnostics and deletion.
- Share/export a ZIP containing the fused PLY, captured PLY frames, original depth buffers and calibration/pose metadata.
- No account, server, analytics, payment SDK or third-party scanning SDK. Nothing is uploaded automatically.

## Start here: run it on your iPhone

You need a **Mac with Xcode 16 or newer** and a physical **iPhone with a front TrueDepth camera running iOS 17 or later**. The app checks the camera at runtime. A rear LiDAR sensor is not required. The iOS simulator can show the interface and run export tests, but cannot scan a real foot.

1. Unzip this package on the Mac.
2. Open `SOULScan.xcodeproj` in Xcode. There is no package-install step.
3. Select the **SOULScan** target → **Signing & Capabilities**.
4. Choose your Apple development team. Change `com.soul.scan.prototype` to a unique bundle identifier if Xcode requests it.
5. Connect and trust your iPhone, enable Developer Mode if prompted, and select it as the run destination.
6. Choose the **SOULScan** scheme and press **Run**.
7. Allow camera access, open **Before your first scan**, then choose **Start a foot scan**.

Signing, a Mac build and a real-device scan were not available in the creation environment. Expect a device integration pass before distribution. Windows cannot build or sign this native iOS project by itself.

## How to capture

The **front** camera and screen face the foot. Having a second person operate the phone is the easiest starting workflow. Voice guidance is included because the operator may not see the screen.

1. Seat the subject with the leg comfortably supported. Keep the bare foot still and the sole exposed. Leave clear space behind it.
2. Use soft indoor light. Keep hands, supports, furniture and reflective surfaces out of the cropped area.
3. Position the front camera about **25–45 cm** from the sole. The prototype accepts calibrated depth between 20 and 55 cm.
4. Begin. After the three-second countdown, move the phone in a slow, shallow arc around the sole, arch and heel. Keep consecutive views overlapping.
5. If alignment is lost, return to the last good angle. If the foot moved, discard the scan and start again.
6. Finish and orbit the scan. Inspect missing surfaces, background geometry and duplicated contours. Capture the other foot as a separate scan.

Sessions stop at 45 seconds of continuous recording, 100 saved keyframes or the 100,000-point budget. Pausing and resuming starts a new 45-second recording interval; the 100-keyframe cap remains. One accepted frame can be saved for troubleshooting; this is explicitly shown as limited coverage, not a complete scan.

## What this first version does NOT claim

This is an **engineering prototype**, not a clinically validated scanner or an automated orthotic designer. It exports a surface **point cloud**, not a watertight STL, a corrective prescription or a printable insole.

- There is no trained anatomical foot segmentation. The depth crop can include other nearby objects.
- Geometric ICP can drift or align to the wrong surface, particularly on flat or symmetric areas. The algorithm has no global tracking, loop closure or automatic relocalisation.
- Capturing more frames does not prove completeness. View bins describe camera-direction changes around one axis; they are not a percentage of the foot captured.
- The displayed residual is how well nearby points align, **not measurement accuracy**. The bounding box is aligned to the first camera, **not anatomical foot length or shoe size**.
- Unseen plantar areas cannot be recovered from standing photos. This workflow captures a non-weight-bearing foot. Defining the right loading/positioning protocol for your intended footbed remains a separate fitting decision.
- No fabricated missing surfaces, automatic footbed generation, pressure measurements or commercial treatment claims are included.

Before making customer footbeds, perform the physical validation in `VALIDATION.md`. The generated website has not been changed to claim this prototype is publicly available.

## Export format

Use **Export scan package** in a saved scan. Share it through Files, AirDrop or another destination of your choice. Temporary share copies are cleared when the share sheet closes. Local scan data is excluded from device backup; deleting the app removes its local scans, so export anything you need to retain.

| File | Contents |
| --- | --- |
| `model.ply` | Fused binary little-endian surface point cloud. **Coordinates in metres**. No triangles. |
| `scan.json` | Side, activity, reference, capture statistics, cloud bounds and validation status. |
| `frames.json` | Intrinsics, reference image dimensions, distortion table, depth dimensions and each camera-to-model transform. Timestamps are seconds relative to the first accepted frame. |
| `frame-0001.ply`, etc. | Cropped calibrated points before fusion, in each depth camera’s own coordinate system. |
| `frame-0001.depth-f32`, etc. | Original depth buffer: row-major little-endian Float32 metres, no row padding. Invalid values may be NaN. |
| `READ-ME.txt` | Coordinate and processing notes. |

Camera basis: **+x right, +y up, −z forward**, with no mirror. Matrices are 4×4 row-major transforms from the frame’s camera space into the first camera/model frame. The app rotates only the visualisation for portrait display.

To inspect an archive on Windows, macOS or Linux with Python 3:

```sh
python3 Tools/inspect-scan.py your-scan.zip
python3 Tools/inspect-scan.py your-scan.zip --millimetres model-mm.ply
```

The second command explicitly converts coordinates to millimetres for tools that assume mm. It refuses to overwrite an existing output. Import the resulting point cloud into a compatible 3D tool for inspection and subsequent surface reconstruction. Footbed design remains a separate step.

## Tests

The portable C++ core was compiled and its synthetic tests were run in Linux. Swift files were syntax-parsed. The native app, camera behaviour, lens calibration on an actual phone, visual layout and Apple signing **have not been verified in Xcode or on hardware**.

Run the portable tests with a C++17 compiler:

```sh
sh Tools/test-core.sh
```

In Xcode, select the SOULScan scheme and use **Product → Test** to run the included XCTest export/serialization tests. These native tests are supplied but were not run in the creation environment.

See `VALIDATION.md` for the complete status and the first hardware checks.

## Project layout

```text
SOULScan.xcodeproj/       Xcode app and unit-test targets
SOULScan/                SwiftUI screens, AVFoundation capture, local files and exports
Core/                    Dependency-free C++17 alignment/fusion, C bridge
Tests/                   Portable geometry tests and XCTest export tests
Tools/                   Project generator, test runner and scan inspector
```

The Xcode project is already generated. Run `python3 Tools/generate-project.py` only after adding or removing source files. It resets project-generated signing settings, so set your team again afterwards.

## Primary references

- Apple: [Streaming depth data from the TrueDepth camera](https://developer.apple.com/documentation/avfoundation/streaming-depth-data-from-the-truedepth-camera)
- Apple: [AVDepthData](https://developer.apple.com/documentation/avfoundation/avdepthdata)
- Apple: [Lens distortion lookup table](https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata/lensdistortionlookuptable)
- Apple: [Camera calibration](https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata)
- Sooley: [Its stated use of iPhone TrueDepth](https://sooley.de/en/blogs/news/3d-fussscan-iphone-vorteile)

SOUL’s code and imagery are independent. Sooley’s scanning SDK and proprietary reconstruction software are not included.
