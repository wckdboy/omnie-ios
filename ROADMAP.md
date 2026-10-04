# Omnie Agent Roadmap

| | milestone | status |
|---|---|---|
| M1 | Remote mode: Hermes Agent gateway client (sessions, SSE streaming, Keychain-backed key storage) | ✅ |
| M2 | On-device mode: Foundation Models agent with tool calling, local transcript | ✅ |
| M3 | Mode switching without losing either side's state | ✅ |
| M4 | App icon (light/dark/tinted), local network + Tailscale/VPS connectivity | ✅ |
| M5 | Shortcuts/Siri (`AskOmnieIntent`), `omnie://` URL scheme, MCP client for on-device tools | ✅ |
| M6 | `BRANDING.md` adopted: design tokens, Unbounded display font, accent gradient on primary actions, selectable monochrome theme | ✅ |
| M7 | OpenCode as a second remote backend; Cloud mode (BYOK) with a provider catalog | ✅ |
| M8 | Unified Provider system: one picker/setup screen/Settings section for Hermes, OpenCode, and every cloud preset; `AppMode` collapsed from three cases to two | ✅ |
| M9 | Further cross-program integration (see below) | open |

## M7 notes — OpenCode and BYOK

- **OpenCode** (`opencode serve`) is documented well enough for its REST
  session/message endpoints (`GET/POST /session`, `GET/POST /session/:id/message`)
  but its token-by-token streaming goes through a *global* SSE endpoint
  (`/event`) with payload shapes that aren't fully published. Rather than
  guess at filtering/parsing that correctly, `OpenCodeClient` uses the
  documented synchronous message endpoint — replies arrive all at once
  instead of token-by-token. Revisit if the `/event` shapes get confirmed
  against a live server.
- **Cloud provider model IDs are never hardcoded as real defaults** except
  where explicitly verified (DeepSeek's current model is `deepseek-flash` —
  confirmed live; note `deepseek-chat`/`deepseek-reasoner` are retired as of
  July 2026, and there's no literal `"deepseek-v4.1-flash"` string). Every
  other preset shows its model as placeholder text only, since model
  catalogs change constantly and a stale hardcoded default is worse than an
  empty field.
- Anthropic is deliberately not in the built-in provider catalog — its
  native API has a different shape (`x-api-key`, `/v1/messages`) than the
  `/chat/completions` contract `OpenAICompatibleClient` speaks. Use "Custom"
  if an OpenAI-compatible shim is available.

## M8 notes — the unified Provider system

- `AppMode` is now just `local` / `provider` (was `local` / `remote` /
  `cloud`). `ProviderConfig` replaced the separate `ServerConfig` and
  `CloudProviderConfig`; `ProviderTransport` (`hermes` / `opencode` /
  `openAICompatible`) decides which fields the setup screen shows and
  which chat UI (`SessionsView`+`ChatView` vs. `ProviderChatView`) the root
  view routes to.
- OpenCode no longer exposes a separate Username field — the UI shows one
  "API Key" field like every other provider; it's mapped internally to
  HTTP Basic auth with the fixed default username (`opencode`).
- Only one provider connection can be configured at a time (switching
  providers means re-entering details). Multiple saved connections you can
  switch between without re-entering anything — closer to Hermes Desktop's
  own "Settings → Connections" list — is a natural next step, not yet built.

## M9 — further cross-program integration

Scope right now is `omnie-edit` and `omnie-agent`; more Omnie programs are
expected to join over time. Candidate next steps, in no particular order —
check in before starting one, since this is shared surface across programs:

- **Multiple saved provider connections**, selectable without re-entering
  credentials (see M8 notes above).
- **OMNIE-BOX hub as a fourth provider.** The [omnie](https://github.com/wckdboy/omnie)
  hub exposes its own `/api/chat` (SSE) and `/api/about`. `RemoteAgentClient`
  already supports multiple session-based backends (Hermes, OpenCode) —
  adding this one would follow the same pattern.
- **MCP for provider mode.** Not done: a Hermes/OpenCode server manages its
  own tools server-side, so the client has no tool list to extend there
  today. If that changes, MCP wiring should follow the same
  `MCPDynamicTool` pattern used on-device.
- **Richer Shortcuts**: `AskOmnieIntent` only exposes a `prompt: String`
  parameter today (Siri phrase parameters are restricted to `AppEntity`/
  `AppEnum`, so a spoken "Ask Omnie such-and-such" phrase isn't available —
  only the dialog-prompted form is). An entity-backed parameter (e.g. a
  fixed set of saved prompts) could unlock that if it's worth the surface.
- **omnie-edit integration.** Nothing built yet connecting the two apps
  directly (e.g. asking Omnie Agent about a file open in Omnie Edit). The
  `omnie://ask` URL scheme is the likely entry point once there's a concrete
  use case.
