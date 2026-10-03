# Contributing to Omnie Agent

Omnie Agent is developed locally with Xcode. A hosted repository is not
required to build, test, or contribute.

## Before changing code

1. Read `README.md` for scope, and `ROADMAP.md` before starting on any
   cross-program integration work (Shortcuts, a URL scheme, OMNIE-BOX hub
   support, MCP) — that surface is shared across the Omnie programs and is
   tracked there to avoid duplicated or conflicting designs.
2. Never commit API keys, server URLs that aren't placeholders, or any other
   secret. The server API key belongs in the Keychain only
   (`ServerConfigStore`); don't add a path that writes it to `UserDefaults`
   or a plist.
3. Keep the on-device and remote code paths independent. `LocalAgentClient`
   must not require network access, and `HermesClient` must not depend on
   `FoundationModels`.
4. Preserve the "no alpha channel" requirement on any app icon asset —
   App Store validation rejects icons with transparency.

## Code style

- Prefer small Swift types with one clear responsibility.
- Use four-space indentation and descriptive names.
- Use Swift concurrency (`async`/`await`, actors) rather than Combine for new
  asynchronous work.
- Explain non-obvious constraints and decisions, not syntax.
- Avoid force unwraps and hidden global state.
- Match the project's existing `nonisolated` annotations on plain value types
  — this project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so model
  types used off the main actor (e.g. inside `HermesClient`) need it
  explicitly.

## Tests

Run Product > Test in Xcode before sharing a change. Networking and parsing
code (`SSEParser`, `HermesClient`) should be tested against recorded or
synthetic responses rather than a live server. UI changes should be checked
on an iPhone simulator in both light and dark appearance.

## Changes that need extra care

Keychain handling, the SSE parser, session persistence for the on-device
transcript, and anything touching `Info.plist`/build settings (app icon
wiring, `ASSETCATALOG_COMPILER_APPICON_NAME`, `INFOPLIST_FILE`) can be easy to
get subtly wrong without it showing up until a real device run. Keep these
changes focused and document the verification performed.
