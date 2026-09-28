import XCTest
@testable import SOULScan

final class ExportTests:XCTestCase {
    func testBinaryPLYRoundTripAndMetreScale() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let points=[SoulPoint(x:0.012,y:-0.02,z:-0.35),SoulPoint(x:0.003,y:0.12,z:-0.36)]
        let path=folder.appendingPathComponent("test.ply")
        try PointFile.ply(points).write(to:path)
        let read=try PointFile.readPLY(path)
        XCTAssertEqual(read.count,2);XCTAssertEqual(read[0].x,0.012,accuracy:0.000001);XCTAssertEqual(read[1].z,-0.36,accuracy:0.000001)
    }
    func testTruncatedPLYRejected() throws {
        let path=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:path)}
        try Data("ply\nformat binary_little_endian 1.0\nelement vertex 9000\nend_header\n".utf8).write(to:path)
        XCTAssertThrowsError(try PointFile.readPLY(path))
    }
    func testZIPSignaturesAndPayload() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:folder)}
        let file=folder.appendingPathComponent("hello.txt"),archive=folder.appendingPathComponent("export.zip")
        try Data("123456789".utf8).write(to:file)
        try ZipArchive.write(files:[file],to:archive)
        let bytes=try Data(contentsOf:archive)
        XCTAssertEqual(Array(bytes.prefix(4)),[0x50,0x4b,0x03,0x04])
        // Canonical CRC32 vector = CBF43926, little-endian at local-header byte 14.
        XCTAssertEqual(Array(bytes[14..<18]),[0x26,0x39,0xf4,0xcb])
        XCTAssertNotNil(bytes.range(of:Data("123456789".utf8)))
        XCTAssertEqual(Array(bytes.suffix(22).prefix(4)),[0x50,0x4b,0x05,0x06])
    }
}
