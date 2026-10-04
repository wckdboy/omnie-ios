import Foundation

/// Which wire protocol a provider preset speaks. The setup screen shows or
/// hides fields based on this: session-based transports don't need a model
/// field (the server picks), OpenAI-compatible ones do.
enum ProviderTransport: String, Codable {
    /// Hermes Agent's API server: bearer token, `/api/sessions*` + SSE.
    case hermes
    /// An OpenCode server (`opencode serve`): HTTP Basic auth under the
    /// hood, exposed in the UI as a single API key.
    case opencode
    /// Any provider speaking the OpenAI `/chat/completions` shape: bearer
    /// token, a model you choose, stateless per call.
    case openAICompatible

    /// Session-based transports (Hermes, OpenCode) get the sessions-list +
    /// `ChatView` UI; OpenAI-compatible ones get the single-thread UI.
    var isSessionBased: Bool { self != .openAICompatible }
}

/// A known provider: a name, transport, base URL (always editable, just
/// prefilled), and a model placeholder to show in the UI. The model field is
/// always free text — new model IDs ship constantly, so this never
/// hardcodes a default that could go stale, except where noted.
struct AIProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let transport: ProviderTransport
    let baseURL: URL
    let modelPlaceholder: String
    /// Only set when verified recently; most presets leave this nil and show
    /// `modelPlaceholder` as placeholder text instead of a prefilled value.
    let defaultModel: String?

    static let custom = AIProviderPreset(
        id: "custom",
        name: "Custom (OpenAI-compatible)",
        transport: .openAICompatible,
        baseURL: URL(string: "https://")!,
        modelPlaceholder: "model id",
        defaultModel: nil
    )
}

enum AIProviderCatalog {
    /// Self-hosted, session-based agent servers.
    static let agentServers: [AIProviderPreset] = [
        AIProviderPreset(
            id: "hermes",
            name: "Hermes Agent",
            transport: .hermes,
            baseURL: URL(string: "http://100.x.x.x:8642")!,
            modelPlaceholder: "",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "opencode",
            name: "OpenCode",
            transport: .opencode,
            baseURL: URL(string: "http://100.x.x.x:4096")!,
            modelPlaceholder: "",
            defaultModel: nil
        )
    ]

    /// Direct, BYOK cloud providers — one shared `OpenAICompatibleClient`
    /// covers all of them rather than bespoke code per provider. Anthropic
    /// is deliberately omitted: its native API has a different shape
    /// (`x-api-key`, `/v1/messages`) rather than `/chat/completions`; pick
    /// "Custom" and point it at an OpenAI-compatible shim if one exists
    /// instead of assuming this app speaks Anthropic's own API.
    static let cloudPresets: [AIProviderPreset] = [
        AIProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            transport: .openAICompatible,
            baseURL: URL(string: "https://api.deepseek.com")!,
            modelPlaceholder: "deepseek-flash",
            defaultModel: "deepseek-flash"
        ),
        AIProviderPreset(
            id: "openai",
            name: "OpenAI",
            transport: .openAICompatible,
            baseURL: URL(string: "https://api.openai.com/v1")!,
            modelPlaceholder: "e.g. gpt-4o-mini",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            transport: .openAICompatible,
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            modelPlaceholder: "e.g. openai/gpt-4o-mini",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "groq",
            name: "Groq",
            transport: .openAICompatible,
            baseURL: URL(string: "https://api.groq.com/openai/v1")!,
            modelPlaceholder: "e.g. llama-3.3-70b-versatile",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "mistral",
            name: "Mistral",
            transport: .openAICompatible,
            baseURL: URL(string: "https://api.mistral.ai/v1")!,
            modelPlaceholder: "e.g. mistral-small-latest",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "together",
            name: "Together AI",
            transport: .openAICompatible,
            baseURL: URL(string: "https://api.together.xyz/v1")!,
            modelPlaceholder: "e.g. meta-llama/Llama-3.3-70B-Instruct-Turbo",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "fireworks",
            name: "Fireworks AI",
            transport: .openAICompatible,
            baseURL: URL(string: "https://api.fireworks.ai/inference/v1")!,
            modelPlaceholder: "e.g. accounts/fireworks/models/llama-v3p3-70b-instruct",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "xai",
            name: "xAI (Grok)",
            transport: .openAICompatible,
            baseURL: URL(string: "https://api.x.ai/v1")!,
            modelPlaceholder: "e.g. grok-4",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "perplexity",
            name: "Perplexity",
            transport: .openAICompatible,
            baseURL: URL(string: "https://api.perplexity.ai")!,
            modelPlaceholder: "e.g. sonar",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "featherless",
            name: "Featherless AI",
            transport: .openAICompatible,
            baseURL: URL(string: "https://api.featherless.ai/v1")!,
            modelPlaceholder: "e.g. mistralai/Mistral-Nemo-Instruct-2407",
            defaultModel: nil
        )
    ]

    /// Agent servers first, then cloud providers, then Custom — the order
    /// the picker shows them in.
    static let all = agentServers + cloudPresets + [AIProviderPreset.custom]

    static func preset(withID id: String) -> AIProviderPreset? {
        all.first { $0.id == id }
    }
}
