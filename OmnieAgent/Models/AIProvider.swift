import Foundation

/// A known OpenAI-compatible provider: just a name, base URL, and a model
/// placeholder to show in the UI. The model field is always free text — new
/// model IDs ship constantly, so this never hardcodes a default that could
/// go stale, except where noted.
struct AIProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: URL
    let modelPlaceholder: String
    /// Only set when verified recently; most presets leave this nil and show
    /// `modelPlaceholder` as placeholder text instead of a prefilled value.
    let defaultModel: String?

    static let custom = AIProviderPreset(
        id: "custom",
        name: "Custom (OpenAI-compatible)",
        baseURL: URL(string: "https://")!,
        modelPlaceholder: "model id",
        defaultModel: nil
    )
}

enum AIProviderCatalog {
    /// Covers the common OpenAI-compatible providers with one shared client
    /// (`OpenAICompatibleClient`) rather than bespoke code per provider.
    /// Anthropic is deliberately omitted: its native API has a different
    /// shape (`x-api-key`, `/v1/messages`) rather than `/chat/completions`;
    /// pick "Custom" and point it at an OpenAI-compatible shim if one is
    /// available instead of assuming this app speaks Anthropic's own API.
    static let presets: [AIProviderPreset] = [
        AIProviderPreset(
            id: "deepseek",
            name: "DeepSeek",
            baseURL: URL(string: "https://api.deepseek.com")!,
            modelPlaceholder: "deepseek-flash",
            defaultModel: "deepseek-flash"
        ),
        AIProviderPreset(
            id: "openai",
            name: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            modelPlaceholder: "e.g. gpt-4o-mini",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "openrouter",
            name: "OpenRouter",
            baseURL: URL(string: "https://openrouter.ai/api/v1")!,
            modelPlaceholder: "e.g. openai/gpt-4o-mini",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "groq",
            name: "Groq",
            baseURL: URL(string: "https://api.groq.com/openai/v1")!,
            modelPlaceholder: "e.g. llama-3.3-70b-versatile",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "mistral",
            name: "Mistral",
            baseURL: URL(string: "https://api.mistral.ai/v1")!,
            modelPlaceholder: "e.g. mistral-small-latest",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "together",
            name: "Together AI",
            baseURL: URL(string: "https://api.together.xyz/v1")!,
            modelPlaceholder: "e.g. meta-llama/Llama-3.3-70B-Instruct-Turbo",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "fireworks",
            name: "Fireworks AI",
            baseURL: URL(string: "https://api.fireworks.ai/inference/v1")!,
            modelPlaceholder: "e.g. accounts/fireworks/models/llama-v3p3-70b-instruct",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "xai",
            name: "xAI (Grok)",
            baseURL: URL(string: "https://api.x.ai/v1")!,
            modelPlaceholder: "e.g. grok-4",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "perplexity",
            name: "Perplexity",
            baseURL: URL(string: "https://api.perplexity.ai")!,
            modelPlaceholder: "e.g. sonar",
            defaultModel: nil
        ),
        AIProviderPreset(
            id: "featherless",
            name: "Featherless AI",
            baseURL: URL(string: "https://api.featherless.ai/v1")!,
            modelPlaceholder: "e.g. mistralai/Mistral-Nemo-Instruct-2407",
            defaultModel: nil
        )
    ]

    static let all = presets + [AIProviderPreset.custom]

    static func preset(withID id: String) -> AIProviderPreset? {
        all.first { $0.id == id }
    }
}
