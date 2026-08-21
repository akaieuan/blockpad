import XCTest
@testable import BlockpadKit

final class DeliveryStrategyTests: XCTestCase {
    func testOnlyImageAndPathStrategiesCarryAnImage() {
        XCTAssertFalse(DeliveryStrategy.pasteText.carriesImage)
        XCTAssertTrue(DeliveryStrategy.pasteImage.carriesImage)
        XCTAssertTrue(DeliveryStrategy.pastePath.carriesImage)
        XCTAssertFalse(DeliveryStrategy.manual.carriesImage)
    }

    func testStrategyRoundTripsThroughItsRawValue() {
        for strategy in DeliveryStrategy.allCases {
            XCTAssertEqual(DeliveryStrategy(rawValue: strategy.rawValue), strategy)
        }
    }
}
