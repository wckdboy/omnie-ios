import FoundationModels

/// Wraps one MCP-discovered tool so Apple's on-device model can call it.
///
/// Foundation Models' `Tool` protocol needs a static `Arguments` type to
/// describe a parameter schema to the model. MCP tools only have a runtime
/// JSON Schema, so arguments are accepted as free-form `GeneratedContent`
/// (itself a valid `Tool.Arguments`), and the tool's real schema is spelled
/// out in its description text instead — the framework still injects that
/// description into the model's prompt, so the model sees the shape it
/// needs to produce even though it isn't statically enforced.
struct MCPDynamicTool: Tool {
    let name: String
    let description: String

    typealias Arguments = GeneratedContent

    private let client: MCPClient

    init(definition: MCPToolDefinition, client: MCPClient) {
        self.name = definition.name
        self.description = """
        \(definition.description)

        Call with a JSON object matching this schema:
        \(definition.inputSchemaJSON)
        """
        self.client = client
    }

    func call(arguments: GeneratedContent) async throws -> String {
        try await client.callTool(name: name, argumentsJSON: arguments.jsonString)
    }
}
