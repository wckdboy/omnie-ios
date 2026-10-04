# Omnie Privacy

Omnie talks only to the agents you add. There is no Omnie server.

- No account, no analytics, no advertising SDKs.
- Agent addresses and settings are stored on the device. API keys,
  passwords and tokens are stored in the Keychain
  (`AfterFirstUnlockThisDeviceOnly`) and are removed when you remove the
  agent.
- Conversations with Dashboard and Gateway agents are stored by the agent
  itself. Conversations with OpenAI-compatible endpoints are stored on the
  iPhone in the app's Application Support folder and deleted with the agent.
- Photos you attach are sent only to the agent you're talking to.
- Notifications for finished replies are local; nothing goes through
  Apple's push service.
- Local network access is used to reach agents on your network. The camera
  is used only to scan connection codes.
