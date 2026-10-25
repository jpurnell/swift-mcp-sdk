import Foundation
import Testing

@testable import MCP

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Suite("OAuthURLValidator")
struct OAuthURLValidatorTests {

    // MARK: - validateHTTPSOrLoopback

    @Test("Accepts HTTPS URL")
    func testValidateHTTPSOrLoopbackAcceptsHTTPS() {
        #expect(throws: Never.self) {
            try OAuthURLValidator().validateHTTPSOrLoopback(
                testURL("https://example.com/mcp"), context: "test")
        }
    }

    @Test("Accepts loopback HTTP")
    func testValidateHTTPSOrLoopbackAcceptsLoopback() {
        #expect(throws: Never.self) {
            try OAuthURLValidator().validateHTTPSOrLoopback(
                testURL("http://localhost:8080/mcp"), context: "test")
            try OAuthURLValidator().validateHTTPSOrLoopback(
                testURL("http://127.0.0.1:9000/mcp"), context: "test")
        }
    }

    @Test("Rejects remote HTTP")
    func testValidateHTTPSOrLoopbackRejectsRemoteHTTP() {
        #expect(throws: OAuthAuthorizationError.self) {
            try OAuthURLValidator().validateHTTPSOrLoopback(
                cleartextTestURL(host: "example.com", path: "/mcp"), context: "test")
        }
    }

    @Test("Rejects URL with fragment")
    func testValidateHTTPSOrLoopbackRejectsFragment() {
        #expect(throws: OAuthAuthorizationError.self) {
            try OAuthURLValidator().validateHTTPSOrLoopback(
                testURL("https://example.com/mcp#frag"), context: "test")
        }
    }

    // MARK: - validateAuthorizationServer

    @Test("Accepts HTTPS authorization server")
    func testValidateAuthorizationServerAcceptsHTTPS() {
        #expect(throws: Never.self) {
            try OAuthURLValidator().validateAuthorizationServer(
                testURL("https://auth.example.com"), context: "test")
        }
    }

    @Test("Rejects HTTP authorization server by default")
    func testValidateAuthorizationServerRejectsHTTP() {
        #expect(throws: OAuthAuthorizationError.self) {
            try OAuthURLValidator().validateAuthorizationServer(
                cleartextTestURL(host: "auth.example.com"), context: "test")
        }
    }

    @Test("Accepts loopback HTTP when flag is set")
    func testValidateAuthorizationServerAcceptsLoopbackWhenAllowed() {
        #expect(throws: Never.self) {
            let v = OAuthURLValidator(allowLoopbackHTTPForAuthorizationServer: true)
            try v.validateAuthorizationServer(
                testURL("http://localhost:8080"), context: "test")
        }
    }

    @Test("Rejects loopback HTTP when flag is not set")
    func testValidateAuthorizationServerRejectsLoopbackWhenNotAllowed() {
        #expect(throws: OAuthAuthorizationError.self) {
            try OAuthURLValidator().validateAuthorizationServer(
                testURL("http://localhost:8080"), context: "test")
        }
    }

    // MARK: - validateRedirectURI

    @Test("Accepts HTTPS redirect URI")
    func testValidateRedirectURIAcceptsHTTPS() {
        #expect(throws: Never.self) {
            try OAuthURLValidator().validateRedirectURI(
                testURL("https://app.example.com/callback"))
        }
    }

    @Test("Accepts loopback HTTP redirect URI")
    func testValidateRedirectURIAcceptsLoopback() {
        #expect(throws: Never.self) {
            try OAuthURLValidator().validateRedirectURI(
                testURL("http://localhost:8080/callback"))
        }
    }

    @Test("Rejects remote HTTP redirect URI")
    func testValidateRedirectURIRejectsRemoteHTTP() {
        #expect(throws: OAuthAuthorizationError.self) {
            try OAuthURLValidator().validateRedirectURI(
                cleartextTestURL(host: "app.example.com", path: "/callback"))
        }
    }

    @Test("Rejects redirect URI with fragment")
    func testValidateRedirectURIRejectsFragment() {
        #expect(throws: OAuthAuthorizationError.self) {
            try OAuthURLValidator().validateRedirectURI(
                testURL("https://app.example.com/callback#section"))
        }
    }

    // MARK: - isPrivateIPHost

    @Test("Identifies private IPv4 ranges")
    func testIsPrivateIPHostIPv4() {
        let v = OAuthURLValidator()
        #expect(v.isPrivateIPHost("10.0.0.1"))
        #expect(v.isPrivateIPHost("172.16.0.1"))
        #expect(v.isPrivateIPHost("172.31.255.255"))
        #expect(v.isPrivateIPHost("192.168.1.1"))
        #expect(v.isPrivateIPHost("169.254.169.254"))
        #expect(v.isPrivateIPHost("100.64.0.1"))
    }

    @Test("Does not block public IPv4 addresses")
    func testIsPrivateIPHostPublicIPv4() {
        let v = OAuthURLValidator()
        #expect(!v.isPrivateIPHost("1.2.3.4"))
        #expect(!v.isPrivateIPHost("8.8.8.8"))
        #expect(!v.isPrivateIPHost("203.0.113.1"))
    }

    @Test("Identifies private IPv6 ULA and link-local addresses")
    func testIsPrivateIPHostIPv6() {
        let v = OAuthURLValidator()
        #expect(v.isPrivateIPHost("fc00::1"))
        #expect(v.isPrivateIPHost("fd12:3456::1"))
        #expect(v.isPrivateIPHost("fe80::1"))
    }

    @Test("Does not block public hostnames")
    func testIsPrivateIPHostPublicHostname() {
        let v = OAuthURLValidator()
        #expect(!v.isPrivateIPHost("example.com"))
        #expect(!v.isPrivateIPHost("localhost"))
    }
}
