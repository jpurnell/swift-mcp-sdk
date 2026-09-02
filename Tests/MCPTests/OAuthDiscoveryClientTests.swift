@preconcurrency import Foundation
import Testing

@testable import MCP

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if swift(>=6.1) && !os(Linux)

    @Suite("OAuthDiscoveryClient", .serialized)
    struct OAuthDiscoveryClientTests {

        let urlValidator = OAuthURLValidator(allowLoopbackHTTPForAuthorizationServer: true)
        let metadataDiscovery = DefaultOAuthMetadataDiscovery()

        func makeClient() -> OAuthDiscoveryClient {
            OAuthDiscoveryClient(metadataDiscovery: metadataDiscovery, urlValidator: urlValidator)
        }

        func makeProtectedResourceBody(authorizationServers: [String]) throws -> Data {
            let dict: [String: Any] = ["authorization_servers": authorizationServers]
            return try JSONSerialization.data(withJSONObject: dict)
        }

        func makeASMetadataBody(issuer: String) throws -> Data {
            let dict: [String: Any] = [
                "issuer": issuer,
                "token_endpoint": "https://auth.example.com/token",
                "code_challenge_methods_supported": ["S256"],
            ]
            return try JSONSerialization.data(withJSONObject: dict)
        }

        // MARK: - fetchProtectedResourceMetadata

        @Test("Returns metadata from first successful candidate")
        func testFetchProtectedResourceMetadataSuccess() async throws {
            let body = try makeProtectedResourceBody(
                authorizationServers: ["https://auth.example.com"])
            let (session, key) = makeIsolatedSession()
            await IsolatedMockURLProtocol.setHandler(key: key) { _ in
                let response = testHTTPResponse(url: testURL("https://example.com/.well-known/oauth-protected-resource"), statusCode: 200)
                return (response, body)
            }

            let metadata = try await makeClient().fetchProtectedResourceMetadata(
                candidates: [testURL("https://example.com/.well-known/oauth-protected-resource")],
                fallbackIssuer: nil,
                session: session
            )
            let expected = OAuthProtectedResourceMetadata(
                resource: nil,
                authorizationServers: [testURL("https://auth.example.com")],
                scopesSupported: nil)
            #expect(metadata == expected)
        }

        @Test("Skips candidates that return non-2xx status")
        func testFetchProtectedResourceMetadataSkipsNon2xx() async throws {
            let body = try makeProtectedResourceBody(
                authorizationServers: ["https://auth.example.com"])
            let (session, key) = makeIsolatedSession()
            await IsolatedMockURLProtocol.setHandler(key: key) { request in
                let statusCode = request.url?.lastPathComponent == "mcp" ? 404 : 200
                let response = testHTTPResponse(url: testRequestURL(request), statusCode: statusCode)
                return (response, statusCode == 200 ? body : Data())
            }

            let metadata = try await makeClient().fetchProtectedResourceMetadata(
                candidates: [
                    testURL("https://example.com/.well-known/oauth-protected-resource/mcp"),
                    testURL("https://example.com/.well-known/oauth-protected-resource"),
                ],
                fallbackIssuer: nil,
                session: session
            )
            let expected = OAuthProtectedResourceMetadata(
                resource: nil,
                authorizationServers: [testURL("https://auth.example.com")],
                scopesSupported: nil)
            #expect(metadata == expected)
        }

        @Test("Skips candidates with empty authorizationServers array")
        func testFetchProtectedResourceMetadataSkipsEmptyAuthServers() async throws {
            let emptyBody = try makeProtectedResourceBody(authorizationServers: [])
            let validBody = try makeProtectedResourceBody(
                authorizationServers: ["https://auth.example.com"])
            let (session, key) = makeIsolatedSession()
            await IsolatedMockURLProtocol.setHandler(key: key) { request in
                let body = request.url?.lastPathComponent == "mcp" ? emptyBody : validBody
                let response = testHTTPResponse(url: testRequestURL(request), statusCode: 200)
                return (response, body)
            }

            let metadata = try await makeClient().fetchProtectedResourceMetadata(
                candidates: [
                    testURL("https://example.com/.well-known/oauth-protected-resource/mcp"),
                    testURL("https://example.com/.well-known/oauth-protected-resource"),
                ],
                fallbackIssuer: nil,
                session: session
            )
            let expected = OAuthProtectedResourceMetadata(
                resource: nil,
                authorizationServers: [testURL("https://auth.example.com")],
                scopesSupported: nil)
            #expect(metadata == expected)
        }

        @Test("Throws metadataDiscoveryFailed when all candidates fail and no fallback issuer")
        func testFetchProtectedResourceMetadataThrowsWhenAllFail() async throws {
            let (session, key) = makeIsolatedSession()
            await IsolatedMockURLProtocol.setHandler(key: key) { request in
                let response = testHTTPResponse(url: testRequestURL(request), statusCode: 404)
                return (response, Data())
            }

            await #expect(throws: OAuthAuthorizationError.self) {
                try await makeClient().fetchProtectedResourceMetadata(
                    candidates: [
                        testURL("https://example.com/.well-known/oauth-protected-resource")
                    ],
                    fallbackIssuer: nil,
                    session: session
                )
            }
        }

        @Test("Returns synthetic metadata with fallback issuer when all candidates fail")
        func testFetchProtectedResourceMetadataUsesFallbackIssuer() async throws {
            let fallback = testURL("https://example.com")
            let (session, key) = makeIsolatedSession()
            await IsolatedMockURLProtocol.setHandler(key: key) { request in
                let response = testHTTPResponse(url: testRequestURL(request), statusCode: 404)
                return (response, Data())
            }

            let metadata = try await makeClient().fetchProtectedResourceMetadata(
                candidates: [testURL("https://example.com/.well-known/oauth-protected-resource")],
                fallbackIssuer: fallback,
                session: session
            )
            let expected = OAuthProtectedResourceMetadata(
                resource: nil,
                authorizationServers: [fallback],
                scopesSupported: nil)
            #expect(metadata == expected)
        }

        // MARK: - fetchAuthorizationServerMetadata

        @Test("Returns server and metadata when issuer matches")
        func testFetchAuthorizationServerMetadataSuccess() async throws {
            let issuer = "https://auth.example.com"
            let body = try makeASMetadataBody(issuer: issuer)
            let (session, key) = makeIsolatedSession()
            await IsolatedMockURLProtocol.setHandler(key: key) { _ in
                let response = testHTTPResponse(url: testURL("\(issuer)/.well-known/oauth-authorization-server"), statusCode: 200)
                return (response, body)
            }

            let (server, metadata) = try await makeClient().fetchAuthorizationServerMetadata(
                candidates: [testURL(issuer)],
                session: session
            )
            let expectedServer = testURL(issuer)
            let expectedMetadata = OAuthAuthorizationServerMetadata(
                issuer: URL(string: issuer),
                authorizationEndpoint: nil,
                tokenEndpoint: URL(string: "https://auth.example.com/token"),
                registrationEndpoint: nil,
                codeChallengeMethodsSupported: ["S256"],
                tokenEndpointAuthMethodsSupported: nil,
                clientIDMetadataDocumentSupported: nil)
            #expect(server == expectedServer)
            #expect(metadata == expectedMetadata)
        }

        @Test("Uses metadata issuer as server identity when it differs from candidate URL")
        func testFetchAuthorizationServerMetadataUsesMetadataIssuer() async throws {
            let metadataIssuer = "https://other.example.com"
            let body = try makeASMetadataBody(issuer: metadataIssuer)
            let (session, key) = makeIsolatedSession()
            await IsolatedMockURLProtocol.setHandler(key: key) { _ in
                let response = testHTTPResponse(url: testURL("https://auth.example.com"), statusCode: 200)
                return (response, body)
            }

            let (server, _) = try await makeClient().fetchAuthorizationServerMetadata(
                candidates: [testURL("https://auth.example.com")],
                session: session
            )
            #expect(server == testURL(metadataIssuer))
        }

        @Test("Skips private IP candidates without making HTTP calls")
        func testFetchAuthorizationServerMetadataSkipsPrivateIP() async throws {
            let (session, _) = makeIsolatedSession()
            await #expect(throws: OAuthAuthorizationError.self) {
                try await makeClient().fetchAuthorizationServerMetadata(
                    candidates: [testURL("https://10.0.0.1")],
                    session: session
                )
            }
        }

        @Test("Throws when all candidates return non-2xx")
        func testFetchAuthorizationServerMetadataThrowsWhenAllFail() async throws {
            let (session, key) = makeIsolatedSession()
            await IsolatedMockURLProtocol.setHandler(key: key) { request in
                let response = testHTTPResponse(url: testRequestURL(request), statusCode: 500)
                return (response, Data())
            }

            await #expect(throws: OAuthAuthorizationError.self) {
                try await makeClient().fetchAuthorizationServerMetadata(
                    candidates: [testURL("https://auth.example.com")],
                    session: session
                )
            }
        }
    }

#endif
