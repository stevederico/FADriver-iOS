import Foundation

/// Drives iOS Maps.app: search for a destination, tap the top result, trigger
/// the Directions action. Auto-returns to the caller when done.
struct MapsPlaybook: Playbook {
    let intent = "navigate"

    func run(args: [String: String], wda: WDAClient, returnToCaller: Bool, returnDelaySeconds: Double, callerBundleId: String?) async throws -> String {
        guard let destination = args["destination"], !destination.isEmpty else {
            throw PlaybookError.missingArg("destination")
        }

        NSLog("[fadriver-mac] maps_playbook step=activate")
        try await wda.activate(bundleId: "com.apple.Maps")

        NSLog("[fadriver-mac] maps_playbook step=find_search")
        let searchId = try await wda.waitFor(
            predicate: "name == 'MapsSearchTextField' AND type == 'XCUIElementTypeSearchField'",
            timeout: 6
        )
        try await wda.click(elementId: searchId)

        NSLog("[fadriver-mac] maps_playbook step=type_destination")
        try await wda.typeText(destination)

        NSLog("[fadriver-mac] maps_playbook step=pick_first_result")
        if let cellId = try? await wda.waitFor(
            predicate: "(type == 'XCUIElementTypeCell' OR name == 'PlaceCell' OR name == 'SuggestionCell') AND label CONTAINS[c] '\(destination)'",
            timeout: 4
        ) {
            try await wda.click(elementId: cellId)
        } else if let anyCell = try? await wda.findElement(predicate: "type == 'XCUIElementTypeCell'") {
            try await wda.click(elementId: anyCell)
        } else if let returnId = try? await wda.findElement(predicate: "name == 'return' AND type == 'XCUIElementTypeKey'") {
            try await wda.click(elementId: returnId)
        }

        NSLog("[fadriver-mac] maps_playbook step=find_directions")
        if let directionsId = try? await wda.waitFor(
            predicate: "(name CONTAINS[c] 'Directions' OR label CONTAINS[c] 'Directions') AND type == 'XCUIElementTypeButton'",
            timeout: 4
        ) {
            try await wda.click(elementId: directionsId)
        }

        try await autoReturn(wda: wda, enabled: returnToCaller, delaySeconds: returnDelaySeconds, callerBundleId: callerBundleId)
        NSLog("[fadriver-mac] maps_playbook step=done")
        return "Showed directions to \(destination)"
    }
}
