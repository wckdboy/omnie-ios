import Foundation

/// A link into the app from the `omnie://` URL scheme — opened by the
/// system, a Shortcut, or another app.
///
/// `omnie://ask?text=What's%20the%20weather&mode=local` sends `text` to
/// the on-device agent, switching into local mode first if needed. Omit
/// `mode` to use whichever mode is currently active; `mode=remote` needs a
/// server already configured (it won't trigger onboarding).
enum DeepLink {
    case ask(text: String, mode: AppMode?)

    init?(url: URL) {
        guard url.scheme?.lowercased() == "omnie", url.host?.lowercased() == "ask" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let text = components.queryItems?.first(where: { $0.name == "text" })?.value,
              !text.isEmpty else { return nil }
        let modeString = components.queryItems?.first(where: { $0.name == "mode" })?.value?.lowercased()
        self = .ask(text: text, mode: modeString.flatMap(AppMode.init(rawValue:)))
    }
}
