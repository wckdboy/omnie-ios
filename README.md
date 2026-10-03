# Omnie Agent

Omnie Agent is an iOS client for running an agent two ways: entirely on the
phone using Apple's on-device model, or connected to a self-hosted
[Hermes Agent](https://github.com/NousResearch/hermes-agent) gateway over
Tailscale, a local network, or a public VPS address. There is no bundled
account system and no Omnie-run backend — every conversation either stays on
the device or goes straight to a server the user points the app at.

Omnie Agent is an independent client. It is not affiliated with or endorsed
by Nous Research.

## What works today

- **On-device mode** — Apple's `FoundationModels` on-device model
  (`SystemLanguageModel` / `LanguageModelSession`), with a `currentDateTime`
  tool so it's a real tool-calling agent rather than a plain chatbot. Fully
  offline; the conversation is saved locally and never leaves the phone.
- **Remote mode** — talks to a Hermes Agent gateway's API server
  (`/health`, `/v1/models`, `/api/sessions*`, and the session chat SSE
  stream), reachable over Tailscale, local Wi-Fi, or a public address. The
  server's API key is stored in the Keychain, never in `UserDefaults` or on
  disk in plain text.
- A mode picker on first launch, switchable later from Settings without
  losing either the remote config or the on-device conversation.
- Markdown rendering, tool-use indicators, and a minimal Liquid Glass UI.

## Requirements

- Xcode 26 or later
- iOS 26 or later (on-device mode additionally needs Apple Intelligence
  enabled on supported hardware)

## Local development

1. Open `OmnieAgent.xcodeproj` in Xcode.
2. Select the `Omnie-Agent` scheme and an iPhone simulator or device.
3. Build and run.

No remote repository or hosted CI service is required.

## Architecture

- `OmnieAgent/Models/` — `ServerConfig` (+ Keychain-backed store), `AppMode`,
  and the `ChatSession` / `ChatMessage` / `ToolEvent` wire models.
- `OmnieAgent/Networking/` — `HermesClient` (the gateway's REST + SSE API)
  and `SSEParser`, a lenient Server-Sent Events parser.
- `OmnieAgent/Local/` — `LocalAgentClient` and `CurrentDateTimeTool`, the
  on-device agent.
- `OmnieAgent/AppModel.swift` — the single `@Observable` source of truth for
  both modes.
- `OmnieAgent/Views/` — SwiftUI views; `WelcomeView` is the mode picker,
  `SessionsView`/`ChatView` the remote flow, `LocalChatView` the on-device
  flow.

## Integrating with other tools and agents

Omnie Agent speaks the same conventions as the rest of the Omnie/WCKD.ai
family where they apply:

- Remote mode talks to anything exposing Hermes Agent's API server contract
  (`/health`, `/v1/models`, `/api/sessions*`). An
  [OMNIE-BOX](https://github.com/wckdboy/omnie) hub or any other
  Hermes-compatible gateway should work without client changes.
- No API keys or secrets are ever committed; the server's key lives only in
  the device Keychain.

Broader interop (Shortcuts/App Intents, a URL scheme, direct OMNIE-BOX hub
support, MCP) is tracked in `ROADMAP.md` and not yet built — see that file
before starting work in this area so efforts across the Omnie programs don't
duplicate or conflict.

## Contributing

See `CONTRIBUTING.md`. New behavior should have focused tests where
practical, descriptive names, and comments only where the reason isn't
obvious from the code.

## Privacy

See `PRIVACY.md`. Omnie Agent does not require an account and does not
include analytics or advertising SDKs.

## License

Omnie Agent is available under the MIT License. See `LICENSE`.

Part of [WCKD.ai](https://github.com/wckdboy/wckd.ai).
