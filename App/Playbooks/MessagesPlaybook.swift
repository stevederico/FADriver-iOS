import Foundation

/// Drives iOS Messages.app: compose a new message, type recipient, type body, tap Send.
/// Auto-returns to the caller so the user can chain commands.
struct MessagesPlaybook: Playbook {
    let intent = "send_message"

    func run(args: [String: String], wda: WDAClient, returnToCaller: Bool, returnDelaySeconds: Double, callerBundleId: String?) async throws -> String {
        guard let contact = args["contact"], !contact.isEmpty else { throw PlaybookError.missingArg("contact") }
        guard let body = args["body"], !body.isEmpty else { throw PlaybookError.missingArg("body") }

        NSLog("[fadriver-mac] msg_playbook step=terminate")
        try await wda.terminate(bundleId: "com.apple.MobileSMS")
        NSLog("[fadriver-mac] msg_playbook step=activate")
        try await wda.activate(bundleId: "com.apple.MobileSMS")

        // Prefer an existing conversation whose label matches the contact
        // (phone digits or name). Fastest + most reliable path.
        let digits = contact.filter(\.isNumber)
        if let existingId = try? await findExistingConversation(wda: wda, contact: contact, digits: digits) {
            NSLog("[fadriver-mac] msg_playbook step=use_existing contact=\(contact)")
            try await wda.click(elementId: existingId)
        } else {
            // New conversation via compose. iOS Messages disables the body
            // field until a recipient is committed — so: To: first, commit to
            // a chip, body becomes editable.
            NSLog("[fadriver-mac] msg_playbook step=compose contact=\(contact)")
            let composeId = try await wda.waitFor(predicate: "name == 'composeButton' AND type == 'XCUIElementTypeButton'", timeout: 6)
            try await wda.click(elementId: composeId)

            NSLog("[fadriver-mac] msg_playbook step=to_field")
            let toField = try await wda.waitFor(
                predicate: "name == 'To:' AND type == 'XCUIElementTypeTextField'",
                timeout: 6
            )
            try await wda.click(elementId: toField)
            try? await wda.clear(elementId: toField)
            try await wda.typeText(contact)

            try? await Task.sleep(nanoseconds: 1_200_000_000)

            let displayName = args["displayName"] ?? ""
            let last4 = String(digits.suffix(4))
            var clauses: [String] = []
            if !last4.isEmpty { clauses.append("label CONTAINS '\(last4)'") }
            if !contact.isEmpty { clauses.append("label CONTAINS[c] '\(contact)'") }
            if !displayName.isEmpty {
                let safe = displayName.replacingOccurrences(of: "'", with: "''")
                clauses.append("label CONTAINS[c] '\(safe)'")
            }
            let suggestionPredicate = "type == 'XCUIElementTypeCell' AND (" + clauses.joined(separator: " OR ") + ")"
            if let suggestionId = try? await wda.waitFor(
                predicate: suggestionPredicate,
                timeout: 3
            ) {
                NSLog("[fadriver-mac] msg_playbook step=commit_via_suggestion")
                try await wda.click(elementId: suggestionId)
            } else {
                NSLog("[fadriver-mac] msg_playbook step=commit_via_comma")
                try await wda.typeText(",")
            }

            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        NSLog("[fadriver-mac] msg_playbook step=find_body")
        let bodyField = try await wda.waitFor(
            predicate: "name == 'messageBodyField' AND (type == 'XCUIElementTypeTextField' OR type == 'XCUIElementTypeTextView')",
            timeout: 6
        )
        try await wda.click(elementId: bodyField)
        try? await wda.clear(elementId: bodyField)
        try await wda.typeText(body)

        NSLog("[fadriver-mac] msg_playbook step=find_send")
        let sendId = try await wda.waitFor(
            predicate: "(name CONTAINS[c] 'send' OR label CONTAINS[c] 'send' OR name == 'arrow.up.circle.fill') AND type == 'XCUIElementTypeButton'",
            timeout: 6
        )
        try await wda.click(elementId: sendId)

        try await autoReturn(wda: wda, enabled: returnToCaller, delaySeconds: returnDelaySeconds, callerBundleId: callerBundleId)
        NSLog("[fadriver-mac] msg_playbook step=done")
        return "Sent to \(contact)"
    }

    private func findExistingConversation(wda: WDAClient, contact: String, digits: String) async throws -> String? {
        if !digits.isEmpty {
            if let id = try? await wda.findElement(
                predicate: "type == 'XCUIElementTypeCell' AND label CONTAINS '\(digits.suffix(7))'"
            ) { return id }
        }
        if let id = try? await wda.findElement(
            predicate: "type == 'XCUIElementTypeCell' AND label CONTAINS[c] '\(contact)'"
        ) { return id }
        return nil
    }
}
