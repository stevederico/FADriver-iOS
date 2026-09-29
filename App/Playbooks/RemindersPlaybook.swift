import Foundation

/// Drives iOS Reminders.app: dismiss the onboarding sheet if present, tap
/// "New Reminder", type the title, commit, and optionally auto-return to the
/// caller. Lean — no list/due-date support; the sim MVP just proves the bridge
/// can drive Reminders end-to-end.
struct RemindersPlaybook: Playbook {
    let intent = "add_reminder"

    func run(args: [String: String], wda: WDAClient, returnToCaller: Bool, returnDelaySeconds: Double, callerBundleId: String?) async throws -> String {
        guard let title = args["title"], !title.isEmpty else { throw PlaybookError.missingArg("title") }

        NSLog("[fadriver-mac] rem_playbook step=activate")
        try await wda.activate(bundleId: "com.apple.reminders")

        if let continueId = try? await wda.findElement(predicate: "name == 'Continue' AND type == 'XCUIElementTypeButton'") {
            NSLog("[fadriver-mac] rem_playbook step=dismiss_onboarding")
            try await wda.click(elementId: continueId)
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        NSLog("[fadriver-mac] rem_playbook step=new_reminder")
        let newId = try await wda.waitFor(
            predicate: "name == 'New Reminder' AND type == 'XCUIElementTypeButton'",
            timeout: 6
        )
        try await wda.click(elementId: newId)

        NSLog("[fadriver-mac] rem_playbook step=type_title")
        try await wda.typeText(title)

        NSLog("[fadriver-mac] rem_playbook step=commit")
        if let returnId = try? await wda.findElement(predicate: "name == 'return' AND type == 'XCUIElementTypeKey'") {
            try await wda.click(elementId: returnId)
        } else {
            try await wda.typeText("\n")
        }

        try await autoReturn(wda: wda, enabled: returnToCaller, delaySeconds: returnDelaySeconds, callerBundleId: callerBundleId)
        NSLog("[fadriver-mac] rem_playbook step=done")
        return "Added reminder: \(title)"
    }
}
