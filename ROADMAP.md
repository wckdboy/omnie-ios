# Omnie Agent Roadmap

| | milestone | status |
|---|---|---|
| M1 | Remote mode: Hermes Agent gateway client (sessions, SSE streaming, Keychain-backed key storage) | ✅ |
| M2 | On-device mode: Foundation Models agent with tool calling, local transcript | ✅ |
| M3 | Mode switching without losing either side's state | ✅ |
| M4 | App icon (light/dark/tinted), local network + Tailscale/VPS connectivity | ✅ |
| M5 | Cross-program integration (see below) | open |

## M5 — integrating with other Omnie programs and tools

Not yet built. Candidate surfaces, in no particular order — pick up only
after checking with the other Omnie repos involved, since this is shared
surface:

- **OMNIE-BOX hub as a second remote backend.** The [omnie](https://github.com/wckdboy/omnie)
  hub exposes its own `/api/chat` (SSE) and `/api/about`. Remote mode
  currently assumes a Hermes Agent gateway specifically; generalizing it to
  either backend needs a small capability-detection step (hit `/api/about`
  vs `/v1/models`) rather than a user-facing "backend type" toggle.
- **Shortcuts / App Intents**, so Siri and other apps on the phone can send
  a prompt to Omnie Agent (either mode) and get a result back.
- **A URL scheme** (`omnie://`) for deep links from other apps or the web —
  e.g. opening straight into a new chat with a prefilled prompt.
- **MCP.** [nextcloud-mcp](https://github.com/wckdboy/nextcloud-mcp) shows
  the family already leans on MCP for tool integration. Whether Omnie Agent
  should act as an MCP *client* (talking to MCP servers from the phone) is
  an open design question, not just an implementation detail — MCP's
  primary transports don't map cleanly onto a sandboxed iOS app.

None of these are committed designs yet. Open an issue or check in before
starting one, so two Omnie programs don't grow incompatible answers to the
same integration question.
