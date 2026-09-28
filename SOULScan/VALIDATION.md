# Validation and release status

## Verified in the creation environment

- C++17 core compiled with warnings treated as errors.
- Known rigid transform recovered on an asymmetric synthetic surface.
- Collinear geometry rejected.
- Repeated stationary frames do not add points.
- ICP recovers a small translated/rotated synthetic frame.
- A non-overlapping frame does not alter the fused model.
- NaN and null inputs are rejected.
- Point-copy capacity is respected; reset clears the model.
- Noisy synthetic registration with 0.7 mm Gaussian depth noise and 10% non-overlapping outliers passed. This does not model all TrueDepth error sources.
- AddressSanitizer/UndefinedBehaviorSanitizer checks passed for these core tests with leak detection disabled (the container does not support LeakSanitizer).
- Python export-inspector tests verify archive reads, explicit metre-to-millimetre conversion, refusal to overwrite and rejection of truncated/nonfinite model data.
- Swift source syntax parsed with the tree-sitter Swift grammar.
- Project source/resource references, XML property lists and the generated scheme checked.

Synthetic errors reported by tests are **not estimates of iPhone measurement accuracy**. The tests use known noiseless geometry unless explicitly identified otherwise.

## Not yet verified

- Full Xcode compile, framework API integration, code signing or TestFlight upload.
- The included XCTest tests on an Apple runtime.
- Camera orientation/calibration on any physical iPhone.
- Real-world precision, repeatability, bias or drift.
- Clinical suitability, anatomical completeness or manufacturing suitability.

## First device integration pass

1. Build for a physical iPhone with iOS 17+ and TrueDepth. Resolve any SDK-specific integration errors before collecting data.
2. Check camera permissions: allow, deny, then grant through Settings. Confirm unsupported devices disable capture without a crash.
3. Verify a visibly asymmetric object is not mirrored. Check the portrait preview orientation, raw calibration dimensions and coordinate basis.
4. Start/stop/discard/restart; pause/resume; background/foreground the app; interrupt the camera. Verify there are no unexpected captures in the background.
5. Export an archive. Check its CRC, metadata and depth sizes with `Tools/inspect-scan.py`; read the PLY in an independent 3D application. Verify the **metres → millimetres** conversion.
6. Delete a scan and check it disappears from the library. Never assume an export held by another application is deleted too.
7. Run the XCTest suite for PLY round-trip, corrupted input handling and ZIP structure/CRC.

## Measurement validation before customer production

Set acceptance thresholds based on the required footbed fit and a qualified assessment of the intended use. This prototype does not supply a justified manufacturing tolerance.

- Use a stable reference object with independently measured distances, curved surfaces and an arch-like recess. Test several sizes and positions in the depth camera field.
- Repeat scans across your intended working distances, light conditions and supported phone models. Compare scale, signed surface error, local detail and repeatability with an independent reference scanner or measured fixture.
- Test foot immobility, small involuntary movement, support-object inclusion and backgrounds close to the sole. Record what the current crop accepts.
- Check arch, heel and toe coverage separately. Do not treat a low ICP residual or more captured frames as evidence of completeness.
- Compare repeated full capture sessions, not only frames within one session. Investigate systematic scale and distortion bias.
- Establish your fitting posture and loading protocol. A non-weight-bearing surface does not automatically specify corrective support, pressure redistribution or the shape of the finished insole.
- Add operator review and a documented rejection/rescan process. Keep exports marked unvalidated until the agreed gates pass.

## Deliberate first-version limits

Geometry-only registration uses a KD-tree, trimmed point-to-point ICP and voxel averaging. There is no global optimisation, automatic foot segmentation, loop closure, mesh reconstruction or clinical decision logic. Scale comes from the device’s absolute depth and calibration; software tests cannot establish its physical accuracy.

Scans are local and excluded from backups. Interrupted unfinished folders can remain on disk after a process crash; they are not shown as completed records. Manual recovery can inspect their `frames.json` and captured frame files. A dedicated recovery interface is a future feature.

Do not distribute this package as an already validated medical or manufacturing system.
