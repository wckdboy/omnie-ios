import AppIntents

/// Lets Siri, Shortcuts, and other apps send a prompt to Omnie Agent —
/// whichever mode (on-device or remote Hermes gateway) is currently active —
/// and get the reply back, without opening the app.
struct AskOmnieIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Omnie"
    static let description = IntentDescription(
        "Sends a prompt to Omnie Agent — on-device or your configured Hermes server — and returns the reply."
    )

    @Parameter(title: "Prompt")
    var prompt: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Omnie \(\.$prompt)")
    }

    func perform() async throws -> some ReturnsValue<String> & ProvidesDialog {
        let reply = try await OmnieAgentBridge.ask(prompt)
        return .result(value: reply, dialog: IntentDialog(stringLiteral: reply))
    }
}

/// Registers `AskOmnieIntent` as a Siri/Shortcuts phrase.
struct OmnieAgentShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskOmnieIntent(),
            phrases: [
                "Ask \(.applicationName)"
            ],
            shortTitle: "Ask Omnie",
            systemImageName: "bubble.left.and.text.bubble.right"
        )
    }
}
