# Omnie Agent

Omnie Agent is an iOS client for running an agent three ways: entirely on the
phone using Apple's on-device model, connected to a self-hosted Hermes-style
agent server ([Hermes Agent](https://github.com/NousResearch/hermes-agent) or
[OpenCode](https://opencode.ai)) over Tailscale, a local network, or a public
VPS address, or directly against a cloud provider using your own API key
(DeepSeek, OpenAI, and most other OpenAI-compatible providers). There is no
bundled account system and no Omnie-run backend — every conversation either
stays on the device or goes straight to a server or provider the user points
the app at.

Omnie Agent is an independent client. It is not affiliated with or endorsed
by Nous Research.

## What works today

- **On-device mode** — Apple's `FoundationModels` on-device model
  (`SystemLanguageModel` / `LanguageModelSession`), with a `currentDateTime`
  tool so it's a real tool-calling agent rather than a plain chatbot. Fully
  offline; the conversation is saved locally and never leaves the phone.
- **Remote mode** — talks to a Hermes Agent gateway's API server
  (`/health`, `/v1/models`, `/api/sessions*`, and the session chat SSE
  stream) or an OpenCode server (`opencode serve`, HTTP Basic auth, its
  REST session + message endpoints), reachable over Tailscale, local Wi-Fi,
  or a public address. One `RemoteAgentClient` protocol covers both, so the
  rest of the app doesn't care which is active. The server's key is stored
  in the Keychain, never in `UserDefaults` or on disk in plain text.
- **Cloud mode (BYOK)** — a built-in catalog of OpenAI-compatible providers
  (DeepSeek, OpenAI, OpenRouter, Groq, Mistral, Together AI, Fireworks AI,
  xAI, Perplexity, Featherless AI) plus a "Custom" entry for anything else
  that speaks the same `/chat/completions` shape. One provider, one model,
  one key — sent straight to the provider, never through an Omnie-run
  server. The key is stored in the Keychain.
- A mode picker on first launch, switchable later from Settings without
  losing any of the three modes' saved state.
- Markdown rendering, tool-use indicators, and a minimal Liquid Glass UI.
- **Shortcuts / Siri** — "Ask Omnie" sends a prompt to whichever mode is
  active and returns the reply, without opening the app.
- **`omnie://` URL scheme** — `omnie://ask?text=...` from another app, a
  Shortcut, or a link, optionally forcing `mode=local` or `mode=remote`.
- **MCP client** (on-device mode only) — point it at an MCP server in
  Settings and its tools are added to the on-device agent's tool list,
  alongside the built-in `currentDateTime` tool.

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

- `OmnieAgent/Models/` — `ServerConfig`, `CloudProviderConfig`, `AIProvider`
  (the BYOK catalog), `AppMode` — all with Keychain-backed stores — and the
  `ChatSession` / `ChatMessage` / `ToolEvent` wire models.
- `OmnieAgent/Networking/` — `RemoteAgentClient` (the shared protocol),
  `HermesClient`, `OpenCodeClient`, `OpenAICompatibleClient` (the BYOK
  client), and `SSEParser`, a lenient Server-Sent Events parser shared by
  all three.
- `OmnieAgent/Local/` — `LocalAgentClient` and `CurrentDateTimeTool`, the
  on-device agent.
- `OmnieAgent/MCP/` — `MCPClient` (JSON-RPC over the Streamable HTTP
  transport), `MCPToolDefinition`, and `MCPDynamicTool`, the Foundation
  Models `Tool` bridge for MCP-discovered tools.
- `OmnieAgent/AppIntents/` — `AskOmnieIntent` and the bridge it uses to reach
  whichever agent is configured without the SwiftUI environment.
- `OmnieAgent/DeepLinking/` — `DeepLink`, the `omnie://` URL parser.
- `OmnieAgent/DesignSystem/` — `BrandPalette`, `BrandFont`, `BrandTheme`,
  `brandPrimaryAction`: the tokens and helpers from `BRANDING.md` (warm vs.
  monochrome neutrals, the Unbounded display font, the purple-to-orange
  accent gradient reserved for one primary action per screen).
- `OmnieAgent/AppModel.swift` — the single `@Observable` source of truth for
  all three modes.
- `OmnieAgent/Views/` — SwiftUI views; `WelcomeView` is the mode picker,
  `SessionsView`/`ChatView` the remote flow, `LocalChatView` the on-device
  flow, `CloudProviderSetupView`/`CloudChatView` the BYOK flow.

## Integrating with other tools and agents

Omnie Agent speaks the same conventions as the rest of the Omnie/WCKD.ai
family where they apply, and stays focused on Hermes-style agents for the
remote side rather than special-casing any one backend:

- Remote mode talks to anything exposing Hermes Agent's API server contract
  (`/health`, `/v1/models`, `/api/sessions*`), or an OpenCode server's REST
  API — one `RemoteAgentClient` protocol, two backends.
- Cloud mode talks directly to whichever OpenAI-compatible provider you
  bring a key for — one `OpenAICompatibleClient`, a growing provider catalog.
- **Shortcuts, Siri, and the `omnie://` URL scheme** let other apps and
  automations drive either mode without opening the app.
- **MCP client support** lets the on-device agent pull in tools from any
  MCP server over the Streamable HTTP transport — not wired into remote mode,
  since a Hermes gateway already manages its own tools server-side.
- No API keys or secrets are ever committed; the server's key and the MCP
  bearer token both live only in the device Keychain.

Right now this covers `omnie-edit` and `omnie-agent`; more Omnie programs are
expected to join this integration surface over time — check `ROADMAP.md`
before extending it so they don't grow incompatible answers to the same
question.

## Contributing

See `CONTRIBUTING.md`. New behavior should have focused tests where
practical, descriptive names, and comments only where the reason isn't
obvious from the code.

## Privacy

See `PRIVACY.md`. Omnie Agent does not require an account and does not
include analytics or advertising SDKs.

## License

Omnie Agent is available under the MIT License. See `LICENSE`. Third-party
assets (the Unbounded display font) are recorded in `THIRD_PARTY_NOTICES.md`.

Part of [WCKD.ai](https://github.com/wckdboy/wckd.ai).
