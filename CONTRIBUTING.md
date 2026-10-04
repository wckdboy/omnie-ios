# Contributing to Omnie

1. Read `BRANDING.md` before changing UI. One gradient element per screen;
   everything else neutral. System font for body text, Unbounded for headers.
2. Keep `OmnieAgent/Core` Foundation-only. It must keep compiling on Linux so
   `Tools/ProtocolHarness` can test it against a real Hermes.
3. New Hermes features go through `AgentBackend` + `AgentEvent`; views never
   parse wire formats.
4. Never commit secrets or real server addresses. Secrets go in the Keychain.
5. Run the protocol harness after changing anything in `Core/Hermes`.
