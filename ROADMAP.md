# Omnie Agent Roadmap

| | milestone | status |
|---|---|---|
| M1 | Remote mode: Hermes Agent gateway client (sessions, SSE streaming, Keychain-backed key storage) | ✅ |
| M2 | On-device mode: Foundation Models agent with tool calling, local transcript | ✅ |
| M3 | Mode switching without losing either side's state | ✅ |
| M4 | App icon (light/dark/tinted), local network + Tailscale/VPS connectivity | ✅ |
| M5 | Shortcuts/Siri (`AskOmnieIntent`), `omnie://` URL scheme, MCP client for on-device tools | ✅ |
| M6 | Further cross-program integration (see below) | open |

## M6 — further cross-program integration

Scope right now is `omnie-edit` and `omnie-agent`; more Omnie programs are
expected to join over time. Candidate next steps, in no particular order —
check in before starting one, since this is shared surface across programs:

- **OMNIE-BOX hub as a second remote backend.** The [omnie](https://github.com/wckdboy/omnie)
  hub exposes its own `/api/chat` (SSE) and `/api/about`. Remote mode
  currently assumes a Hermes Agent gateway specifically — the project's
  explicit focus is Hermes-style agents, so this is deliberately not
  generalized yet; revisit only if a concrete need shows up.
- **MCP for remote mode.** Not done: a Hermes gateway manages its own tools
  server-side, so the client has no tool list to extend there today. If that
  changes (e.g. Hermes exposes a client-contributed tool list), MCP wiring
  should follow the same `MCPDynamicTool` pattern used on-device.
- **Richer Shortcuts**: `AskOmnieIntent` only exposes a `prompt: String`
  parameter today (Siri phrase parameters are restricted to `AppEntity`/
  `AppEnum`, so a spoken "Ask Omnie such-and-such" phrase isn't available —
  only the dialog-prompted form is). An entity-backed parameter (e.g. a
  fixed set of saved prompts) could unlock that if it's worth the surface.
- **omnie-edit integration.** Nothing built yet connecting the two apps
  directly (e.g. asking Omnie Agent about a file open in Omnie Edit). The
  `omnie://ask` URL scheme is the likely entry point once there's a concrete
  use case.
