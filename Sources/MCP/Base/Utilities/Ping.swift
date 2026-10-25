/// The `ping` request, an optional liveness check either side may send to verify the peer is still
/// responsive. The receiver replies promptly with an empty result.
///
/// - SeeAlso: https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/utilities/ping
public enum Ping: Method {
    /// The JSON-RPC method name for this request: `ping`.
    public static let name: String = "ping"
}
