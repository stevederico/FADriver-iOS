import XCTest
@testable import FADriverKit

final class ChainSplitterTests: XCTestCase {
    func testEmptyInputProducesNoSegments() {
        XCTAssertEqual(ChainSplitter.split(""), [])
        XCTAssertEqual(ChainSplitter.split("   "), [])
    }

    func testSingleCommandPassesThrough() {
        XCTAssertEqual(ChainSplitter.split("text Alice"), ["text Alice"])
    }

    func testAndThenSplits() {
        XCTAssertEqual(
            ChainSplitter.split("text Alice and then open maps"),
            ["text Alice", "open maps"]
        )
    }

    func testThenSplits() {
        XCTAssertEqual(
            ChainSplitter.split("text Alice then open maps"),
            ["text Alice", "open maps"]
        )
    }

    func testSemicolonSplits() {
        XCTAssertEqual(
            ChainSplitter.split("text Alice; open maps"),
            ["text Alice", "open maps"]
        )
    }

    func testBareAndDoesNotSplit() {
        XCTAssertEqual(
            ChainSplitter.split("text Alice and Bob"),
            ["text Alice and Bob"]
        )
    }

    func testMultipleSegments() {
        XCTAssertEqual(
            ChainSplitter.split("do a and then do b and then do c"),
            ["do a", "do b", "do c"]
        )
    }

    func testCasePreservedOnSplit() {
        XCTAssertEqual(
            ChainSplitter.split("Text Alice And Then Open Maps"),
            ["Text Alice", "Open Maps"]
        )
    }

    func testMixedMarkers() {
        XCTAssertEqual(
            ChainSplitter.split("a and then b; c then d"),
            ["a", "b", "c", "d"]
        )
    }
}
