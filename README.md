# Omnie

A native iPhone client for [Hermes Agent](https://github.com/NousResearch/hermes-agent).
One app for every way a Hermes agent can be reached, with the Omnie brand
(`BRANDING.md`) applied throughout.

## What it connects to

| Type | Hermes side | Port | What you get |
|---|---|---|---|
| **Dashboard** | `hermes serve` / `hermes dashboard` | 9119 | The Hermes Desktop protocol (JSON-RPC over `/api/ws`). Streaming, tool cards, approvals, clarify questions, sudo and secret prompts, todos, steering, slash commands, model and reasoning switches, cron, skills, tools, logs. |
| **Gateway** | `hermes gateway` with `API_SERVER_KEY` | 8642 | The API server. Sessions, streaming tools, approvals, steer and stop, model lock, branching, cron, skills, toolsets. Profiles via `/p/<profile>`. |
| **OpenAI-compatible** | any `/v1/chat/completions` | — | Plain chat with history on the iPhone. Against a Hermes gateway, tool progress and approvals still show. |

Save as many agents as you like and switch between them from the title bar.
Secrets live in the Keychain.

### Setting up a dashboard agent

```sh
# ~/.hermes/.env
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=me
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=choose-a-password
HERMES_DASHBOARD_BASIC_AUTH_SECRET=$(openssl rand -hex 32)

hermes serve --host 0.0.0.0 --port 9119
```

Add it in Omnie with the address, username and password. Use HTTPS (a
reverse proxy) or a private network such as Tailscale outside your LAN.

### Setting up a gateway agent

```sh
# ~/.hermes/.env
API_SERVER_ENABLED=true
API_SERVER_KEY=$(openssl rand -hex 24)
API_SERVER_HOST=0.0.0.0

hermes gateway restart
```

### Connection links

`omnie://connect?kind=dashboard&url=http://studio.local:9119&name=Studio&user=me`
adds an agent (as a link or QR code). `kind` is `dashboard`, `gateway` or
`openAI`; optional `profile`, `model`, `provider` and a secret as
`password`, `key` or `token`. Prefer leaving the secret out of shared codes.

Other links: `omnie://chat?text=…` starts a chat, `omnie://agent?name=…`
switches agents. Shortcuts and Siri get an **Ask Omnie** action.

## Layout

```
OmnieAgent/
  Core/        Foundation-only protocol layer (no UI). Compiles on Linux.
    Networking/  HTTP + SSE streaming, SSE parser, WebSocket abstraction
    Hermes/      Backends: Dashboard (JSON-RPC), Gateway (REST+SSE), OpenAI
    Chat/        Transcript reducer, Markdown block parser
    Store/       Saved connection model, connection links
  App/         App entry, AppModel, AgentConnection, ChatModel, Keychain
  Brand/       Palette, theme, typography, components (BRANDING.md)
  Features/    Chats, Chat, Agent (jobs/skills/tools/logs), Connections, Settings
  Intents/     Shortcuts / Siri
Tools/ProtocolHarness/  Live end-to-end tests of Core against a real Hermes
```

Every backend turns its wire format into one `AgentEvent` stream; the chat
UI only knows `AgentEvent` and `Transcript`.

## Building

Xcode 26 or later, iOS 26 deployment target. Open `OmnieAgent.xcodeproj`,
pick the `Omnie-Agent` scheme, run. The project uses folder-synchronized
groups, so new files under `OmnieAgent/` are picked up automatically.

CI (`.github/workflows/build.yml`) builds for the simulator on every push.

## Testing the protocol layer

`Tools/ProtocolHarness/run.sh` starts a scripted fake model, a Hermes
gateway and a password-protected dashboard, then drives all three backends
through streaming, tool calls, approvals, clarify questions, interrupts,
history reload, rename, delete and bad credentials.

## License

See `LICENSE`. Unbounded is used under the SIL Open Font License
(`OmnieAgent/Resources/Fonts/Unbounded-OFL.txt`).
