import AVFoundation
import CoreVideo
import UIKit

final class DepthCamera: NSObject, AVCaptureDepthDataOutputDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.soul.camera")
    private let processing = DispatchQueue(label: "com.soul.depth", qos: .userInitiated)
    private let output = AVCaptureDepthDataOutput()
    private let engine = soul_create()!
    private var configured = false
    private var wantsRunning = false // sessionQueue only
    private var recording = false // processing queue only below
    private var hasFinished = false
    private var saveFailed = false
    private var lastFrameTime = -Double.infinity
    private var lastSnapshotTime = -Double.infinity
    private var startedAt: Double = 0
    private var firstDepthTimestamp: Double?
    private var snapshot = ScanSnapshot()
    private var frames: [FrameRecord] = []
    private var folder: URL?
    private var scanID = UUID()
    private var side: FootSide = .left
    private var activity = "Everyday"
    private var reference = ""
    private var latestPoints: [SoulPoint] = []
    private var failures = 0
    private var minimumDepth: Float = 0.20
    private var maximumDepth: Float = 0.55
    var onUpdate: ((ScanSnapshot) -> Void)?
    var onError: ((String) -> Void)?
    var onSaved: ((ScanRecord) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    static var isSupported: Bool { AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(runtimeError), name: .AVCaptureSessionRuntimeError, object: session)
    }
    deinit { NotificationCenter.default.removeObserver(self); soul_destroy(engine) }
    @objc private func interrupted() { processing.async { [weak self] in self?.pauseWithError("Capture was interrupted. Your partial scan has been retained. Return to the scan position to resume, or finish and review.") } }
    @objc private func runtimeError() { processing.async { [weak self] in self?.pauseWithError("The depth camera stopped. Finish this partial scan or start a new scan.") } }
    private func report(_ text: String) { DispatchQueue.main.async { [weak self] in self?.onError?(text) } }
    private func pauseWithError(_ message: String) { recording = false; snapshot.isRecording = false; publish(); DispatchQueue.main.async { [weak self] in self?.onRecordingChanged?(false) }; report(message) }

    func start() {
        guard Self.isSupported else { report("This device does not have a front TrueDepth camera. Use a supported iPhone; simulator and camera-only devices cannot capture metric depth."); return }
        sessionQueue.async { [weak self] in self?.wantsRunning = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: run()
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in if allowed { self?.run() } else { self?.report("Camera access is required. Enable it in Settings → SOUL Scan → Camera.") } }
        default: report("Camera access is off. Enable it in Settings → SOUL Scan → Camera.")
        }
    }
    func stop() { sessionQueue.async { [weak self] in guard let self else { return }; self.wantsRunning = false; if self.session.isRunning { self.session.stopRunning() } } }
    private func run() {
        sessionQueue.async { [weak self] in
            guard let self, self.wantsRunning else { return }
            do { if !self.configured { try self.configure() }; if self.wantsRunning && !self.session.isRunning { self.session.startRunning() } }
            catch { self.report(error.localizedDescription) }
        }
    }
    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) else { throw ScanFailure.message("No TrueDepth camera is available.") }
        session.beginConfiguration(); defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw ScanFailure.message("Could not connect the depth camera.") }; session.addInput(input)
        // Select a video/depth pair explicitly. Never assume the default video format carries depth.
        let candidates = device.formats.flatMap { video in video.supportedDepthDataFormats.compactMap { depth -> (AVCaptureDevice.Format, AVCaptureDevice.Format)? in
            let type = CMFormatDescriptionGetMediaSubType(depth.formatDescription)
            return (type == kCVPixelFormatType_DepthFloat16 || type == kCVPixelFormatType_DepthFloat32) ? (video, depth) : nil
        } }
        guard let selected = candidates.max(by: { CMVideoFormatDescriptionGetDimensions($0.1.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.1.formatDescription).width }) else { throw ScanFailure.message("This device has no supported metric depth format.") }
        try device.lockForConfiguration()
        device.activeFormat = selected.0; device.activeDepthDataFormat = selected.1
        device.unlockForConfiguration()
        guard session.canAddOutput(output) else { throw ScanFailure.message("Could not start the depth stream.") }; session.addOutput(output)
        output.isFilteringEnabled = false
        output.alwaysDiscardsLateDepthData = true
        output.setDelegate(self, callbackQueue: processing)
        if let connection = output.connection(with: .depthData) { connection.isEnabled = true; if connection.isVideoMirroringSupported { connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = false } }
        configured = true
    }

    func prepare(root: URL, side: FootSide, activity: String, reference: String) {
        processing.async { [weak self] in
            guard let self else { return }; self.recording = false; self.hasFinished = false; self.saveFailed = false; self.scanID = UUID(); self.side = side; self.activity = activity; self.reference = reference
            self.folder = root.appendingPathComponent(self.scanID.uuidString, isDirectory: true); self.frames = []; self.latestPoints = []; self.failures = 0; self.snapshot = ScanSnapshot(); soul_reset(self.engine)
            self.lastFrameTime = -.infinity; self.lastSnapshotTime = -.infinity; self.firstDepthTimestamp = nil
        }
    }
    func begin() {
        processing.async { [weak self] in
            guard let self, !self.hasFinished, !self.saveFailed, self.snapshot.canCapture, let folder = self.folder else { return }
            do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete]) }
            catch { self.report("Could not create a local scan: \(error.localizedDescription)"); return }
            self.recording = true; self.startedAt = ProcessInfo.processInfo.systemUptime; self.snapshot.isRecording = true; self.failures = 0
            DispatchQueue.main.async { [weak self] in self?.onRecordingChanged?(true) }
        }
    }
    func pause() { processing.async { [weak self] in self?.recording = false; self?.snapshot.isRecording = false; self?.publish(); DispatchQueue.main.async { [weak self] in self?.onRecordingChanged?(false) } } }
    func discard() { processing.async { [weak self] in guard let self else { return }; self.recording = false; if !self.hasFinished, let folder = self.folder { try? FileManager.default.removeItem(at: folder) }; soul_reset(self.engine); self.hasFinished = true } }
    private func fusedPoints() -> [SoulPoint] { let n = soul_point_count(engine); var points = [SoulPoint](repeating: SoulPoint(x: 0,y: 0,z: 0), count: Int(n)); if n > 0 { _ = points.withUnsafeMutableBufferPointer { soul_copy_points(engine, $0.baseAddress, n) } }; return points }
    private func publish() { let state = snapshot; DispatchQueue.main.async { [weak self] in self?.onUpdate?(state) } }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, connection: AVCaptureConnection) {
        guard !hasFinished, !saveFailed else { return }
        let time = ProcessInfo.processInfo.systemUptime
        guard time - lastFrameTime >= 0.1 else { return }; lastFrameTime = time
        guard depthData.depthDataAccuracy == .absolute, let calibration = depthData.cameraCalibrationData else { snapshot.canCapture = false; snapshot.status = "Waiting for calibrated metric depth…"; publish(); return }
        let data = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = data.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly); defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return }
        let width = CVPixelBufferGetWidth(map), height = CVPixelBufferGetHeight(map), rowBytes = CVPixelBufferGetBytesPerRow(map)
        func depth(_ x: Int, _ y: Int) -> Float { base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)[x] }
        var central: [Float] = []
        for y in stride(from: height/2-12, to: height/2+12, by: 3) { for x in stride(from: width/2-12, to: width/2+12, by: 3) { let z = depth(x,y); if z.isFinite && z > 0.1 && z < 1 { central.append(z) } } }
        central.sort()
        guard central.count > 12 else { snapshot.canCapture = false; snapshot.status = "Keep the foot in the centre of the view."; if !recording { snapshot.points = [] }; publish(); return }
        let distance = central[central.count/2]; snapshot.distanceCM = distance * 100
        let k = calibration.intrinsicMatrix, reference = calibration.intrinsicMatrixReferenceDimensions
        let rw = Float(reference.width), rh = Float(reference.height), cx = k.columns.2.x, cy = k.columns.2.y, fx = k.columns.0.x, fy = k.columns.1.y
        guard fx > 0, fy > 0, rw > 0, rh > 0 else { return }
        let dc = calibration.lensDistortionCenter
        let table: [Float] = calibration.lensDistortionLookupTable.map { bytes in bytes.withUnsafeBytes { raw in (0..<(raw.count/4)).map { raw.loadUnaligned(fromByteOffset: $0*4, as: Float.self) } } } ?? []
        let maxRadius = hypot(max(Float(dc.x),rw-Float(dc.x)),max(Float(dc.y),rh-Float(dc.y)))
        var points: [SoulPoint] = []; points.reserveCapacity(12000)
        // A depth/range crop, not anatomical segmentation. Capture the foot with clear space behind it.
        let step = max(2, width / 220)
        for y in stride(from: 2, to: height-2, by: step) { for x in stride(from: 2, to: width-2, by: step) {
            let z = depth(x,y)
            guard z.isFinite, z >= minimumDepth, z <= maximumDepth, abs(z-distance) < 0.085 else { continue }
            let left = depth(x-1,y), right = depth(x+1,y), up = depth(x,y-1), down = depth(x,y+1)
            guard left.isFinite, right.isFinite, up.isFinite, down.isFinite, abs(left-z) < 0.008, abs(right-z) < 0.008, abs(up-z) < 0.008, abs(down-z) < 0.008 else { continue }
            var u = (Float(x)+0.5)*rw/Float(width), v = (Float(y)+0.5)*rh/Float(height)
            if table.count > 1 && maxRadius > 0 {
                let dx = u-Float(dc.x), dy = v-Float(dc.y), radius = hypot(dx,dy)
                let location = min(max(radius/maxRadius*Float(table.count-1),0),Float(table.count-1)), lo = Int(location), hi = min(lo+1,table.count-1)
                let magnification = table[lo]+(table[hi]-table[lo])*(location-Float(lo))
                u = Float(dc.x)+dx*(1+magnification); v = Float(dc.y)+dy*(1+magnification)
            }
            let px = (u-cx)*z/fx, py = -(v-cy)*z/fy
            guard px*px+py*py < 0.22*0.22 else { continue }
            points.append(SoulPoint(x: px, y: py, z: -z))
        } }
        snapshot.canCapture = points.count >= 700 && distance >= minimumDepth && distance <= maximumDepth && !table.isEmpty
        if table.isEmpty { snapshot.status = "Lens calibration unavailable. Capture is disabled." }
        else if distance < minimumDepth { snapshot.status = "Move the phone a little farther away." }
        else if distance > maximumDepth { snapshot.status = "Move closer. Aim for 25–45 cm." }
        else { snapshot.status = points.count >= 700 ? "Depth ready. Hold the foot still." : "More of the foot needs to be visible." }
        latestPoints = points
        if recording {
            snapshot.elapsed = time-startedAt
            if snapshot.canCapture {
                let result = points.withUnsafeBufferPointer { soul_add_frame(engine, $0.baseAddress, Int32($0.count)) }
                snapshot.acceptedFrames = Int(result.accepted_frames); snapshot.rejectedFrames = Int(result.rejected_frames); snapshot.viewBins = Int(result.view_bins); snapshot.pointCount = Int(result.point_count); snapshot.residualMM = result.rms_metres*1000
                if result.status == 1 {
                    failures = 0; snapshot.status = "Capturing. Move slowly around the arch and heel."
                    do {
                        guard let folder else { return }
                        let number = Int(result.accepted_frames), stem = String(format: "frame-%04d", number), pointName = stem+".ply", depthName = stem+".depth-f32"
                        try PointFile.ply(points).write(to: folder.appendingPathComponent(pointName), options: [.atomic,.completeFileProtection])
                        var rawDepth = Data(capacity: width*height*4)
                        for row in 0..<height { rawDepth.append(base.advanced(by: row*rowBytes).assumingMemoryBound(to: UInt8.self), count: width*4) }
                        try rawDepth.write(to: folder.appendingPathComponent(depthName), options: [.atomic,.completeFileProtection])
                        let r = withUnsafeBytes(of: result.pose.r) { Array($0.bindMemory(to: Float.self)) }, t = withUnsafeBytes(of: result.pose.t) { Array($0.bindMemory(to: Float.self)) }
                        let calibrationRecord = Calibration(depthWidth: width, depthHeight: height, referenceWidth: rw, referenceHeight: rh, intrinsicsRowMajor: [fx,k.columns.1.x,cx,k.columns.0.y,fy,cy,k.columns.0.z,k.columns.1.z,k.columns.2.z], distortionCenter: [Float(dc.x),Float(dc.y)], lensDistortionTable: table, depthAccuracy: "absolute", depthQuality: depthData.depthDataQuality == .high ? "high" : "low")
                        let depthTimestamp = CMTimeGetSeconds(timestamp)
                        if firstDepthTimestamp == nil { firstDepthTimestamp = depthTimestamp }
                        frames.append(FrameRecord(number: number, timestampSeconds: depthTimestamp - (firstDepthTimestamp ?? depthTimestamp), poseRowMajor: [r[0],r[1],r[2],t[0],r[3],r[4],r[5],t[1],r[6],r[7],r[8],t[2],0,0,0,1], residualMM: result.rms_metres*1000, inlierRatio: result.inlier_ratio, pointFile: pointName, depthFile: depthName, calibration: calibrationRecord))
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; try encoder.encode(frames).write(to: folder.appendingPathComponent("frames.json"), options: [.atomic,.completeFileProtection])
                    } catch { saveFailed = true; snapshot.canCapture = false; pauseWithError("A depth frame could not be saved. Discard this scan and free some storage before starting again. \(error.localizedDescription)"); return }
                } else if result.status == 2 { snapshot.status = "Move slowly to reveal another angle." }
                else if result.status == 3 { finishOnQueue(); return }
                else { failures += 1; snapshot.status = "Alignment lost. Return to the last good angle."; if failures >= 25 { pauseWithError("Alignment was lost. Return to your last good position before resuming. If the foot moved, start a fresh scan."); return } }
            }
            if snapshot.elapsed >= 45 || frames.count >= 100 { finishOnQueue(); return }
        }
        if time-lastSnapshotTime > 0.25 {
            snapshot.points = recording && !frames.isEmpty ? fusedPoints() : points; lastSnapshotTime = time; snapshot.isRecording = recording; publish()
        }
    }
    func finish() { processing.async { [weak self] in self?.finishOnQueue() } }
    private func finishOnQueue() {
        recording = false; snapshot.isRecording = false
        DispatchQueue.main.async { [weak self] in self?.onRecordingChanged?(false) }
        guard !saveFailed else { report("This capture contains an unsaved frame and cannot be finalised. Discard it and start a new scan."); return }
        guard !hasFinished, let folder, frames.count >= 1 else { report("Capture at least one valid depth frame before saving."); return }
        do {
            let points = fusedPoints(); guard points.count >= 500 else { throw ScanFailure.message("There are not enough points to save this scan.") }
            let xs=points.map(\.x),ys=points.map(\.y),zs=points.map(\.z)
            let bounds = [xs.max()!-xs.min()!,ys.max()!-ys.min()!,zs.max()!-zs.min()!].map { $0*1000 }
            let record = ScanRecord(id: scanID, createdAt: Date(), side: side, activity: activity, reference: reference, pointCount: points.count, acceptedFrames: frames.count, rejectedFrames: snapshot.rejectedFrames, viewBins: snapshot.viewBins, averageResidualMM: frames.map(\.residualMM).reduce(0,+)/Float(frames.count), boundsMM: bounds, device: UIDevice.current.model, schemaVersion: 1, coordinateSystem: "metres; first depth-camera frame; +x right, +y up, -z forward; no mirroring", validation: "UNVALIDATED RESEARCH PROTOTYPE. Open surface point cloud, not a finished orthotic or manufacturing mesh. ICP residual is not measurement accuracy. Geometric alignment can drift or accept incorrect matches.")
            try PointFile.ply(points).write(to: folder.appendingPathComponent("model.ply"), options: [.atomic,.completeFileProtection])
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];try encoder.encode(record).write(to: folder.appendingPathComponent("scan.json"), options: [.atomic,.completeFileProtection])
            let notice="SOUL Scan\nUnits: metres. Multiply coordinates by 1000 for millimetres.\nmodel.ply: fused surface point cloud, no faces.\nframe-*.ply: cropped calibrated depth points in that camera frame.\nframe-*.depth-f32: raw little-endian Float32 depth in metres, row-major; invalid pixels may be NaN. Dimensions and calibration are in frames.json.\nframes.json: per-frame camera-to-model transforms, calibration and alignment diagnostics.\nThis scan has NOT passed manufacturing validation. Missing surfaces are not inferred. The operator must inspect segmentation, scale, pose and coverage. No guaranteed accuracy.\n"
            try Data(notice.utf8).write(to: folder.appendingPathComponent("READ-ME.txt"), options:[.atomic,.completeFileProtection])
            hasFinished=true; stop(); DispatchQueue.main.async { [weak self] in self?.onSaved?(record) }
        } catch { report("The scan could not be saved: \(error.localizedDescription)") }
    }
}
