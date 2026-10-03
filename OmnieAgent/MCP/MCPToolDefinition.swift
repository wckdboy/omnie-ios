import Foundation

/// One tool discovered from an MCP server's `tools/list` response.
///
/// `inputSchemaJSON` is kept as raw JSON text rather than a parsed value
/// type: Foundation Models' `Tool` protocol wants a static `Arguments` type
/// with a compile-time schema, but MCP tool schemas are only known at
/// runtime, so the raw schema gets embedded as text in the tool's
/// description instead (see `MCPDynamicTool`).
struct MCPToolDefinition: Sendable, Equatable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String
    let inputSchemaJSON: String
}
