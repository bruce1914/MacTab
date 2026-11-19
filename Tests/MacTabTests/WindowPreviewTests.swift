import XCTest
import CoreGraphics
@testable import MacTab

final class WindowPreviewTests: XCTestCase {
    private let frame = CGRect(x: 30, y: 40, width: 800, height: 600)

    func testSameTitleInDifferentApplicationsDoesNotCrossMatch() {
        let candidates = [WindowPreviewCandidate(id: 1, pid: 10, title: "Document", frame: frame),
                          WindowPreviewCandidate(id: 2, pid: 20, title: "Document", frame: frame)]
        XCTAssertEqual(WindowPreviewMatching.match(pid: 20, title: "Document", frame: frame, candidates: candidates), 2)
    }

    func testDuplicateTitlesInOneAppMatchByGeometry() {
        let other = frame.offsetBy(dx: 300, dy: 80)
        let candidates = [WindowPreviewCandidate(id: 1, pid: 10, title: "Document", frame: frame),
                          WindowPreviewCandidate(id: 2, pid: 10, title: "Document", frame: other)]
        XCTAssertEqual(WindowPreviewMatching.match(pid: 10, title: "Document", frame: other, candidates: candidates), 2)
    }

    func testAmbiguousWindowsUseIconFallback() {
        let candidates = [WindowPreviewCandidate(id: 1, pid: 10, title: "Document", frame: frame),
                          WindowPreviewCandidate(id: 2, pid: 10, title: "Document", frame: frame)]
        XCTAssertNil(WindowPreviewMatching.match(pid: 10, title: "Document", frame: frame, candidates: candidates))
        XCTAssertNil(WindowPreviewMatching.match(pid: 10, title: "Document", frame: nil, candidates: candidates))
    }

    func testChangedGeometryDoesNotGuessFromAnOldTitle() {
        let candidates = [WindowPreviewCandidate(id: 1, pid: 10, title: "Document", frame: frame.offsetBy(dx: 100, dy: 0))]
        XCTAssertNil(WindowPreviewMatching.match(pid: 10, title: "Document", frame: frame, candidates: candidates))
    }

    func testUniqueTitleWorksWhenAnApplicationOmitsGeometry() {
        let candidates = [WindowPreviewCandidate(id: 1, pid: 10, title: "Document", frame: frame)]
        XCTAssertEqual(WindowPreviewMatching.match(pid: 10, title: "Document", frame: nil, candidates: candidates), 1)
        XCTAssertNil(WindowPreviewMatching.match(pid: 10, title: "Untitled window", frame: nil, candidates: candidates))
    }

    private func image(_ width: Int = 16, _ height: Int = 16) -> CGImage {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    func testCacheRespectsBothCountAndBytesDuringLongNavigation() {
        let image = image()
        let bytes = image.bytesPerRow * image.height
        var cache = WindowPreviewCache(maximumCount: 4, maximumBytes: bytes * 3)
        for _ in 0..<2000 {
            XCTAssertTrue(cache.insert(image, for: UUID()))
            XCTAssertLessThanOrEqual(cache.count, 3)
            XCTAssertLessThanOrEqual(cache.byteCount, bytes * 3)
        }
        cache.removeAll()
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.byteCount, 0)
    }

    func testCurrentPageCanProtectAnOlderPreviewFromEviction() {
        var cache = WindowPreviewCache(maximumCount: 2)
        let a = UUID(), b = UUID(), c = UUID()
        let image = image()
        cache.insert(image, for: a)
        cache.insert(image, for: b)
        cache.touch(a)
        cache.insert(image, for: c)
        XCTAssertNotNil(cache.image(for: a))
        XCTAssertNil(cache.image(for: b))
        XCTAssertNotNil(cache.image(for: c))
    }

    func testOversizedPreviewCannotReplaceAValidCachedImage() {
        let small = image()
        var cache = WindowPreviewCache(maximumBytes: small.bytesPerRow * small.height)
        let id = UUID()
        XCTAssertTrue(cache.insert(small, for: id))
        XCTAssertFalse(cache.insert(image(64, 64), for: id))
        XCTAssertEqual(cache.image(for: id)?.width, 16)
    }

    func testRepeatedGesturesReleaseTheirCaches() {
        var cache = WindowPreviewCache()
        let image = image(448, 280)
        for _ in 0..<100 {
            for _ in 0..<30 { cache.insert(image, for: UUID()) }
            XCTAssertLessThanOrEqual(cache.count, 16)
            XCTAssertLessThanOrEqual(cache.byteCount, 8 * 1024 * 1024)
            cache.removeAll()
            XCTAssertEqual(cache.byteCount, 0)
        }
    }

    func testSmallAndLargeScreenLayoutsFitAndBoundVisibleImages() {
        for screen in [CGSize(width: 640, height: 480), CGSize(width: 1440, height: 900), CGSize(width: 2560, height: 1440)] {
            let layout = WindowPreviewLayout(count: 70, selectedIndex: 60, screen: screen)
            XCTAssertLessThanOrEqual(layout.size.width, screen.width - 48)
            XCTAssertLessThanOrEqual(layout.size.height, screen.height - 80)
            XCTAssertLessThanOrEqual(layout.capacity, 15)
            XCTAssertTrue(layout.range.contains(60))
        }
    }

    func testEveryCandidateCanBeReachedAcrossPages() {
        for index in 0..<73 {
            let layout = WindowPreviewLayout(count: 73, selectedIndex: index, screen: CGSize(width: 1440, height: 900))
            XCTAssertTrue(layout.range.contains(index))
            XCTAssertLessThanOrEqual(layout.range.upperBound, 73)
        }
    }

    func testPointerGeometryMatchesBalancedRowsAndIgnoresGaps() {
        let six = WindowPreviewLayout(count: 6, selectedIndex: 1, screen: CGSize(width: 1440, height: 900))
        XCTAssertEqual(six.columns, 3)
        XCTAssertEqual(six.index(at: CGPoint(x: 128, y: 136), count: 6), 0)
        XCTAssertEqual(six.index(at: CGPoint(x: 128, y: 328), count: 6), 3)
        XCTAssertNil(six.index(at: CGPoint(x: 128, y: 230), count: 6))
        XCTAssertNil(six.index(at: CGPoint(x: 720, y: 10), count: 6))
        let seven = WindowPreviewLayout(count: 7, selectedIndex: 1, screen: CGSize(width: 1440, height: 900))
        XCTAssertNil(seven.index(at: CGPoint(x: 20, y: 328), count: 7))
        XCTAssertEqual(seven.index(at: CGPoint(x: 246, y: 328), count: 7), 4)
    }

    func testEmptyAndSingleWindowLayoutsRemainValid() {
        let empty = WindowPreviewLayout(count: 0, selectedIndex: 0, screen: CGSize(width: 1440, height: 900))
        XCTAssertTrue(empty.range.isEmpty)
        let single = WindowPreviewLayout(count: 1, selectedIndex: 100, screen: CGSize(width: 1440, height: 900))
        XCTAssertEqual(single.columns, 1)
        XCTAssertEqual(single.range, 0..<1)
    }
}
