# Omnie Agent Privacy

Omnie Agent is designed around a server or on-device model the user
explicitly chooses — there is no Omnie-run backend in between.

- No account is required.
- No advertising or analytics SDK is included.
- **On-device mode**: the conversation runs through Apple's on-device
  `FoundationModels` model entirely on the phone. Nothing is sent over the
  network. The transcript is saved locally in `UserDefaults` and can be
  cleared at any time from Settings or the chat toolbar.
- **Remote mode**: messages are sent only to the server URL the user enters.
  The server's API key is stored in the Keychain, not in `UserDefaults` or
  any plist. Signing out removes it from the Keychain.
- `NSLocalNetworkUsageDescription` is requested because remote mode supports
  connecting directly to a server on the same local network (for example, a
  Mac on the same Wi-Fi); no Bonjour browsing or multicast is performed.
- Whatever server the user points the app at is subject to that server's own
  privacy behavior — Omnie Agent does not control or inspect it.
