import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Shotkeeper

final class ImageIODownscalerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageIODownscalerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDownscalesLongSideAndKeepsAspectAsPNG() throws {
        let url = try writeImage(width: 3000, height: 1500, type: .png, name: "wide.png")
        let payload = try ImageIODownscaler().prepare(url)
        XCTAssertEqual(payload.mimeType, "image/png")
        XCTAssertEqual(payload.pixelWidth, 1280)
        XCTAssertEqual(payload.pixelHeight, 640)
        XCTAssertEqual(Array(payload.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG signature")
        XCTAssertEqual(try decodedSize(payload.data), CGSize(width: 1280, height: 640))
    }

    func testDoesNotUpscaleSmallImages() throws {
        let url = try writeImage(width: 400, height: 300, type: .png, name: "small.png")
        let payload = try ImageIODownscaler(maxLongSide: 1280).prepare(url)
        XCTAssertEqual(payload.pixelWidth, 400)
        XCTAssertEqual(payload.pixelHeight, 300)
    }

    func testAppliesEXIFOrientation() throws {
        // Orientation 6 = rotate 90° clockwise to display: stored 400×200 displays as 200×400.
        let url = try writeImage(width: 400, height: 200, type: .jpeg, name: "rotated.jpg",
                                 properties: [kCGImagePropertyOrientation: 6])
        let payload = try ImageIODownscaler(maxLongSide: 100).prepare(url)
        XCTAssertEqual(payload.pixelWidth, 50)
        XCTAssertEqual(payload.pixelHeight, 100)
    }

    func testFallsBackToJPEGWhenPNGTooLarge() throws {
        let url = try writeImage(width: 800, height: 600, type: .png, name: "big.png")
        let payload = try ImageIODownscaler(pngByteLimit: 1).prepare(url)
        XCTAssertEqual(payload.mimeType, "image/jpeg")
        XCTAssertEqual(Array(payload.data.prefix(2)), [0xFF, 0xD8], "JPEG SOI marker")
        XCTAssertEqual(payload.pixelWidth, 800)
        XCTAssertEqual(payload.pixelHeight, 600)
    }

    func testUnreadableFileThrows() throws {
        let url = directory.appendingPathComponent("not-an-image.png")
        try Data("hello".utf8).write(to: url)
        XCTAssertThrowsError(try ImageIODownscaler().prepare(url))
    }

    // MARK: Helpers

    /// A gradient with some "text-like" stripes, so encoders have real content.
    private func writeImage(width: Int, height: Int, type: UTType, name: String,
                            properties: [CFString: Any]? = nil) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for x in stride(from: 0, to: width, by: 8) {
            context.setFillColor(CGColor(red: CGFloat(x) / CGFloat(width), green: 0.4, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: x, y: 0, width: 4, height: height))
        }
        let image = try XCTUnwrap(context.makeImage())
        let url = directory.appendingPathComponent(name)
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func decodedSize(_ data: Data) throws -> CGSize {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return CGSize(width: image.width, height: image.height)
    }
}
