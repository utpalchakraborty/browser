import XCTest
@testable import Browser

final class PageZoomTests: XCTestCase {
    func testIncreaseAndDecreaseUseBrowserStyleSteps() {
        XCTAssertEqual(PageZoom.increased(from: 1.0), 1.10)
        XCTAssertEqual(PageZoom.increased(from: 1.10), 1.25)
        XCTAssertEqual(PageZoom.decreased(from: 1.0), 0.90)
        XCTAssertEqual(PageZoom.decreased(from: 0.90), 0.80)
    }

    func testIncreaseAndDecreaseNormalizeArbitraryValues() {
        XCTAssertEqual(PageZoom.increased(from: 1.18), 1.25)
        XCTAssertEqual(PageZoom.decreased(from: 1.18), 1.10)
    }

    func testIncreaseAndDecreaseClampAtLimits() {
        XCTAssertEqual(PageZoom.increased(from: PageZoom.maximum), PageZoom.maximum)
        XCTAssertEqual(PageZoom.decreased(from: PageZoom.minimum), PageZoom.minimum)
        XCTAssertFalse(PageZoom.canIncrease(PageZoom.maximum))
        XCTAssertFalse(PageZoom.canDecrease(PageZoom.minimum))
    }

    func testActualSizeComparisonAllowsFloatingPointNoise() {
        XCTAssertTrue(PageZoom.isActualSize(1.0))
        XCTAssertTrue(PageZoom.isActualSize(1.00001))
        XCTAssertFalse(PageZoom.isActualSize(1.10))
    }
}
