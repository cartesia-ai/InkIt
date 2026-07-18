import XCTest
@testable import InkIt

final class DictionaryTermsTests: XCTestCase {

    func testTrimsAndCollapsesInternalWhitespace() {
        let out = SettingsStore.validatedDictionaryTerms(["  Ink   2  "])
        XCTAssertEqual(out, ["Ink 2"], "ends trimmed, internal run collapsed to one space")
    }

    func testStripsNewlinesTabsAndControlChars() {
        let out = SettingsStore.validatedDictionaryTerms(["Cartesia\n\tAI\r"])
        XCTAssertEqual(out, ["Cartesia AI"], "newline/tab/CR become a single separating space")
    }

    func testDropsBlankAndWhitespaceOnlyTerms() {
        let out = SettingsStore.validatedDictionaryTerms(["", "   ", "\n\t", "Kubernetes"])
        XCTAssertEqual(out, ["Kubernetes"])
    }

    func testDedupeIsCaseSensitive() {
        let out = SettingsStore.validatedDictionaryTerms(["aiqi", "AIQI", "aiqi", "nginx"])
        XCTAssertEqual(out, ["aiqi", "AIQI", "nginx"], "case variants are distinct; only exact repeats drop")
    }

    func testClampsToMaxTerms() {
        let raw = (0..<(DictionaryLimits.maxTerms + 25)).map { "term\($0)" }
        let out = SettingsStore.validatedDictionaryTerms(raw)
        XCTAssertEqual(out.count, DictionaryLimits.maxTerms)
        XCTAssertEqual(out.first, "term0")
        XCTAssertEqual(out.last, "term\(DictionaryLimits.maxTerms - 1)")
    }

    func testClampsToCharacterBudget() {
        let big = String(repeating: "a", count: 700)
        let big2 = String(repeating: "b", count: 700)
        let out = SettingsStore.validatedDictionaryTerms([big, big2, "ok"])
        XCTAssertEqual(out, [big, "ok"])
        XCTAssertLessThanOrEqual(out.reduce(0) { $0 + $1.count }, DictionaryLimits.maxCharacters)
    }

    func testNormalizedTermReturnsNilForBlank() {
        XCTAssertNil(SettingsStore.normalizedDictionaryTerm("   \n\t "))
        XCTAssertEqual(SettingsStore.normalizedDictionaryTerm("  hi  there "), "hi there")
    }

    private func queryString(for terms: [String]) -> String {
        let client = CartesiaStreamingClient(apiKey: "test-key", keyterms: terms)
        return client.makeConnectionURL()?.query ?? ""
    }

    func testMultiWordTermPercentEncodesSpaceOnce() {
        let q = queryString(for: ["Ink 2", "Cartesia"])
        XCTAssertTrue(q.contains("keyterm=Ink%202"), "space encodes to %20, not %2520: \(q)")
        XCTAssertTrue(q.contains("keyterm=Cartesia"))
        XCTAssertFalse(q.contains("%2520"), "must not double-encode")
    }

    func testEmptyKeytermsAppendsNoItems() {
        let q = queryString(for: [])
        XCTAssertFalse(q.contains("keyterm"), "no keyterm items for an empty list: \(q)")
    }

    func testRepeatedKeytermParameterPerTerm() {
        let q = queryString(for: ["a", "b", "c"])
        let count = q.components(separatedBy: "keyterm=").count - 1
        XCTAssertEqual(count, 3, "one keyterm= per term")
    }

    func testAmpersandIsEncoded() {
        let client = CartesiaStreamingClient(apiKey: "k", keyterms: ["A & B"])
        let url = client.makeConnectionURL()
        XCTAssertNotNil(url)
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let keyterms = items.filter { $0.name == "keyterm" }.compactMap(\.value)
        XCTAssertEqual(keyterms, ["A & B"], "round-trips back to the original after decoding")
        XCTAssertTrue(url!.absoluteString.contains("A%20%26%20B"), "raw string encodes & as %26: \(url!.absoluteString)")
    }

    func testUnicodeTermRoundTrips() {
        let client = CartesiaStreamingClient(apiKey: "k", keyterms: ["Beyoncé", "北京"])
        let url = client.makeConnectionURL()
        let items = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let keyterms = items.filter { $0.name == "keyterm" }.compactMap(\.value)
        XCTAssertEqual(keyterms, ["Beyoncé", "北京"], "unicode survives encode → decode")
    }

    func testLiteralPlusIsNotPercentEncoded() {
        let client = CartesiaStreamingClient(apiKey: "k", keyterms: ["C++"])
        let raw = client.makeConnectionURL()!.absoluteString
        XCTAssertTrue(raw.contains("keyterm=C++"), "URLComponents leaves '+' literal: \(raw)")
        XCTAssertFalse(raw.contains("%2B"))
    }
}
