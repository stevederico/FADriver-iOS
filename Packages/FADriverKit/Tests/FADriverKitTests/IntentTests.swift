import XCTest
@testable import FADriverKit

final class IntentTests: XCTestCase {
    func testPing() {
        let intent: Intent = .ping
        XCTAssertEqual(intent.wireName, "ping")
        XCTAssertTrue(intent.wireArgs.isEmpty)
    }

    func testSendMessageAllFields() {
        let intent: Intent = .sendMessage(contact: "+14155551212", body: "hi", displayName: "Kate Bell")
        XCTAssertEqual(intent.wireName, "send_message")
        XCTAssertEqual(intent.wireArgs["contact"] as? String, "+14155551212")
        XCTAssertEqual(intent.wireArgs["body"] as? String, "hi")
        XCTAssertEqual(intent.wireArgs["displayName"] as? String, "Kate Bell")
    }

    func testSendMessageNoDisplayName() {
        let intent: Intent = .sendMessage(contact: "555", body: "x")
        XCTAssertNil(intent.wireArgs["displayName"])
    }

    func testNavigate() {
        let intent: Intent = .navigate(destination: "Market Street")
        XCTAssertEqual(intent.wireName, "navigate")
        XCTAssertEqual(intent.wireArgs["destination"] as? String, "Market Street")
    }

    func testAddReminder() {
        let intent: Intent = .addReminder(title: "pick up milk")
        XCTAssertEqual(intent.wireName, "add_reminder")
        XCTAssertEqual(intent.wireArgs["title"] as? String, "pick up milk")
    }

    func testOpenURL() {
        let intent: Intent = .openURL("calshow:123")
        XCTAssertEqual(intent.wireName, "mac_open_url")
        XCTAssertEqual(intent.wireArgs["url"] as? String, "calshow:123")
    }

    func testDriveActivate() {
        let intent: Intent = .driveActivate(bundleId: "com.whatsapp.WhatsApp")
        XCTAssertEqual(intent.wireName, "drive_activate")
        XCTAssertEqual(intent.wireArgs["bundleId"] as? String, "com.whatsapp.WhatsApp")
    }

    func testDriveSnapshot() {
        let intent: Intent = .driveSnapshot
        XCTAssertEqual(intent.wireName, "drive_snapshot")
        XCTAssertTrue(intent.wireArgs.isEmpty)
    }

    func testDriveClickLabelOnly() {
        let intent: Intent = .driveClick(label: "Send")
        XCTAssertEqual(intent.wireName, "drive_click")
        XCTAssertEqual(intent.wireArgs["label"] as? String, "Send")
        XCTAssertNil(intent.wireArgs["predicate"])
    }

    func testDriveClickPredicateOnly() {
        let intent: Intent = .driveClick(predicate: "name == 'send'")
        XCTAssertNil(intent.wireArgs["label"])
        XCTAssertEqual(intent.wireArgs["predicate"] as? String, "name == 'send'")
    }

    func testDriveType() {
        let intent: Intent = .driveType(text: "hello")
        XCTAssertEqual(intent.wireName, "drive_type")
        XCTAssertEqual(intent.wireArgs["text"] as? String, "hello")
    }

    func testSendOptionsIntermediate() {
        let opts = SendOptions.intermediate
        XCTAssertFalse(opts.returnToCaller)
        XCTAssertEqual(opts.returnDelaySeconds, 0)
    }

    func testSendOptionsDefaults() {
        let opts = SendOptions()
        XCTAssertTrue(opts.returnToCaller)
        XCTAssertEqual(opts.returnDelaySeconds, 2.5)
        XCTAssertNil(opts.callerBundleId)
        XCTAssertEqual(opts.timeout, 45)
    }
}
