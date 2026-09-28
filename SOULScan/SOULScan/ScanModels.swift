import Foundation
import UIKit
import Combine

enum FootSide: String, Codable, CaseIterable, Identifiable {
    case left = "Left", right = "Right"
    var id: String { rawValue }
}
struct ScanRecord: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let side: FootSide
    let activity: String
    let reference: String
    let pointCount: Int
    let acceptedFrames: Int
    let rejectedFrames: Int
    let viewBins: Int
    let averageResidualMM: Float
    let boundsMM: [Float]
    let device: String
    let schemaVersion: Int
    let coordinateSystem: String
    let validation: String
    var title: String { "\(side.rawValue) foot" }
}
struct Calibration: Codable {
    let depthWidth: Int
    let depthHeight: Int
    let referenceWidth: Float
    let referenceHeight: Float
    let intrinsicsRowMajor: [Float]
    let distortionCenter: [Float]
    let lensDistortionTable: [Float]
    let depthAccuracy: String
    let depthQuality: String
}
struct FrameRecord: Codable {
    let number: Int
    let timestampSeconds: Double
    let poseRowMajor: [Float]
    let residualMM: Float
    let inlierRatio: Float
    let pointFile: String
    let depthFile: String
    let calibration: Calibration
}
struct ScanSnapshot {
    var points: [SoulPoint] = []
    var distanceCM: Float = 0
    var acceptedFrames = 0
    var rejectedFrames = 0
    var viewBins = 0
    var pointCount = 0
    var residualMM: Float = 0
    var elapsed: Double = 0
    var status = "Position the sole in front of the camera."
    var canCapture = false
    var isRecording = false
}
enum ScanFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}

enum PointFile {
    static func ply(_ points: [SoulPoint]) -> Data {
        let header = "ply\nformat binary_little_endian 1.0\ncomment SOUL Scan - units metres; unvalidated surface point cloud\nelement vertex \(points.count)\nproperty float x\nproperty float y\nproperty float z\nend_header\n"
        var data = Data(header.utf8)
        for p in points { for value in [p.x, p.y, p.z] { var bits = value.bitPattern.littleEndian; withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) } } }
        return data
    }
    static func readPLY(_ url: URL) throws -> [SoulPoint] {
        let data = try Data(contentsOf: url)
        guard let marker = data.range(of: Data("end_header\n".utf8)), let header = String(data: data[..<marker.upperBound], encoding: .utf8), header.contains("format binary_little_endian 1.0"), let line = header.split(separator: "\n").first(where: { $0.hasPrefix("element vertex ") }), let count = Int(line.split(separator: " ").last!), count >= 0, count <= 100_000, data.count - marker.upperBound == count * 12 else { throw ScanFailure.message("The saved point cloud is incomplete or unsupported.") }
        return data.withUnsafeBytes { raw in
            (0..<count).map { index in
                let offset = marker.upperBound + index * 12
                func number(_ n: Int) -> Float { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + n * 4, as: UInt32.self))) }
                return SoulPoint(x: number(0), y: number(1), z: number(2))
            }
        }
    }
}

final class ScanStorage: ObservableObject {
    @Published private(set) var records: [ScanRecord] = []
    @Published var error: String?
    let root: URL
    init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Scans", isDirectory: true)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete]); var folder = root; var values = URLResourceValues(); values.isExcludedFromBackup = true; try folder.setResourceValues(values); refresh() }
        catch { self.error = "Could not open your local scans: \(error.localizedDescription)" }
    }
    func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func refresh() {
        do { let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil); records = folders.compactMap { try? JSONDecoder().decode(ScanRecord.self, from: Data(contentsOf: $0.appendingPathComponent("scan.json"))) }.sorted { $0.createdAt > $1.createdAt } }
        catch { self.error = error.localizedDescription }
    }
    func delete(_ record: ScanRecord) throws { try FileManager.default.removeItem(at: directory(record.id)); refresh() }
    func points(_ record: ScanRecord) throws -> [SoulPoint] { try PointFile.readPLY(directory(record.id).appendingPathComponent("model.ply")) }
    func export(_ record: ScanRecord) throws -> URL {
        let source = directory(record.id)
        let files = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isRegularFileKey]).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let exportFolder = FileManager.default.temporaryDirectory.appendingPathComponent("SOUL-Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let url = exportFolder.appendingPathComponent("SOUL-\(record.side.rawValue)-\(record.id.uuidString.prefix(8)).zip")
        try ZipArchive.write(files: files, to: url)
        return url
    }
}

// ZIP store method, no third-party dependency. Streaming data keeps memory bounded.
enum ZipArchive {
    private static func le<T: FixedWidthInteger>(_ value: T) -> Data { var v = value.littleEndian; return withUnsafeBytes(of: &v) { Data($0) } }
    private static let table: [UInt32] = (0..<256).map { i in var c = UInt32(i); for _ in 0..<8 { c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1 }; return c }
    static func write(files: [URL], to destination: URL) throws {
        let partial = destination.appendingPathExtension("partial")
        FileManager.default.createFile(atPath: partial.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
        let output = try FileHandle(forWritingTo: partial)
        var central = Data(); var offset: UInt32 = 0
        do {
            for file in files {
                let body = try Data(contentsOf: file, options: .mappedIfSafe)
                guard body.count < Int(UInt32.max), UInt64(offset) + UInt64(body.count) + 4096 < UInt64(UInt32.max) else { throw ScanFailure.message("This scan exceeds the export size limit.") }
                let name = Data(file.lastPathComponent.utf8), size = UInt32(body.count)
                var crc: UInt32 = 0xffffffff; for byte in body { crc = table[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }; crc ^= 0xffffffff
                var local = Data(); local += le(UInt32(0x04034b50)); local += le(UInt16(20)); local += le(UInt16(0x0800)); local += le(UInt16(0)); local += le(UInt16(0)); local += le(UInt16(0x21)); local += le(crc); local += le(size); local += le(size); local += le(UInt16(name.count)); local += le(UInt16(0)); local += name
                try output.write(contentsOf: local); try output.write(contentsOf: body)
                central += le(UInt32(0x02014b50)); central += le(UInt16(20)); central += le(UInt16(20)); central += le(UInt16(0x0800)); central += le(UInt16(0)); central += le(UInt16(0)); central += le(UInt16(0x21)); central += le(crc); central += le(size); central += le(size); central += le(UInt16(name.count)); central += le(UInt16(0)); central += le(UInt16(0)); central += le(UInt16(0)); central += le(UInt16(0)); central += le(UInt32(0)); central += le(offset); central += name
                offset += UInt32(local.count) + size
            }
            try output.write(contentsOf: central)
            var end = Data(); end += le(UInt32(0x06054b50)); end += le(UInt16(0)); end += le(UInt16(0)); end += le(UInt16(files.count)); end += le(UInt16(files.count)); end += le(UInt32(central.count)); end += le(offset); end += le(UInt16(0)); try output.write(contentsOf: end); try output.close()
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }; try FileManager.default.moveItem(at: partial, to: destination)
        } catch { try? output.close(); try? FileManager.default.removeItem(at: partial); throw error }
    }
}
