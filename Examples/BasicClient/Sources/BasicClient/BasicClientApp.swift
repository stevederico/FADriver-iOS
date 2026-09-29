import SwiftUI
import FADriverKit

@main
struct BasicClientApp: App {
    init() {
        // Open the WebSocket to the FADriver daemon at ws://localhost:8090.
        // Host apps typically do this once at launch — MacBridge reconnects
        // with exponential backoff if the daemon goes down and comes back.
        MacBridge.shared.connect()
    }

    var body: some Scene {
        WindowGroup("FADriver Example Client") {
            ContentView()
                .frame(minWidth: 420, minHeight: 520)
        }
        .defaultSize(width: 460, height: 560)
    }
}
