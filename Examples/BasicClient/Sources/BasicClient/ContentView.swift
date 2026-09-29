import SwiftUI
import FADriverKit

/// Demonstrates the four core FADriverKit intent shapes — ping, send_message,
/// add_reminder, navigate — against a running FADriver daemon. No LLM wired up
/// here; for the generic `mac_drive` inner-loop planner see
/// `FADriverKit.InnerLoopPlanner` and supply an `LLMProtocol` from the host.
struct ContentView: View {
    @StateObject private var bridge = MacBridge.shared

    @State private var contact: String = "Kate Bell"
    @State private var messageBody: String = "testing FADriver"
    @State private var reminderTitle: String = "pick up milk"
    @State private var destination: String = "Market Street"

    @State private var status: String = "idle"
    @State private var lastReply: String = ""
    @State private var isSending: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Section(header: sectionHeader("Ping")) {
                Button("Send ping") { fire(.ping) }
                    .disabled(isSending || !bridge.isConnected)
            }

            Section(header: sectionHeader("Message")) {
                TextField("Contact (name or phone)", text: $contact)
                    .textFieldStyle(.roundedBorder)
                TextField("Body", text: $messageBody)
                    .textFieldStyle(.roundedBorder)
                Button("Send message") {
                    fire(.sendMessage(contact: contact, body: messageBody, displayName: nil))
                }
                .disabled(isSending || !bridge.isConnected || contact.isEmpty || messageBody.isEmpty)
            }

            Section(header: sectionHeader("Reminder")) {
                TextField("Title", text: $reminderTitle)
                    .textFieldStyle(.roundedBorder)
                Button("Add reminder") {
                    fire(.addReminder(title: reminderTitle))
                }
                .disabled(isSending || !bridge.isConnected || reminderTitle.isEmpty)
            }

            Section(header: sectionHeader("Navigate")) {
                TextField("Destination", text: $destination)
                    .textFieldStyle(.roundedBorder)
                Button("Navigate") {
                    fire(.navigate(destination: destination))
                }
                .disabled(isSending || !bridge.isConnected || destination.isEmpty)
            }

            Spacer()

            replyPanel
        }
        .padding(20)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("FADriver Example")
                .font(.title2)
                .bold()
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(bridge.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(bridge.isConnected ? "connected" : "daemon offline")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }

    private var replyPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status").font(.caption).foregroundStyle(.secondary)
            Text(status).font(.callout)
            if !lastReply.isEmpty {
                Text("Last reply").font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    Text(lastReply)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Actions

    private func fire(_ intent: Intent) {
        isSending = true
        status = "sending \(intent.wireName)…"
        Task {
            do {
                let reply = try await bridge.send(intent, options: .init(returnToCaller: false))
                await MainActor.run {
                    status = "\(intent.wireName): \(reply.status)"
                    lastReply = renderReply(reply)
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    status = "\(intent.wireName): \(error.localizedDescription)"
                    lastReply = ""
                    isSending = false
                }
            }
        }
    }

    private func renderReply(_ reply: IntentReply) -> String {
        var lines: [String] = []
        lines.append("id:      \(reply.id)")
        lines.append("status:  \(reply.status)")
        if !reply.summary.isEmpty {
            lines.append("summary: \(reply.summary)")
        }
        if let err = reply.error {
            lines.append("error:   \(err.code) — \(err.message)")
        }
        return lines.joined(separator: "\n")
    }
}
