import SwiftUI

struct MenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FADriver").font(.headline)
            Divider()
            HStack { Text("WDA:"); Spacer(); Text(state.wdaReady ? "ready" : "waiting…").foregroundStyle(state.wdaReady ? .green : .orange) }
            HStack { Text("WebSocket:"); Spacer(); Text(state.wsListening ? "listening :8090" : "offline").foregroundStyle(state.wsListening ? .green : .red) }
            HStack { Text("Intents served:"); Spacer(); Text("\(state.intentCount)") }
            HStack { Text("Last:"); Spacer(); Text(state.lastEvent).lineLimit(1).truncationMode(.middle) }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 300)
    }
}
