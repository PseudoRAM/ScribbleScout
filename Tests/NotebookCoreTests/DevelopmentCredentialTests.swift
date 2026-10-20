import Testing
@testable import NotebookCore

@Suite("Development credentials")
struct DevelopmentCredentialTests {
    @Test func missingAndBlankKeysUseManualEntry() {
        #expect(DevelopmentCredential.apiKey(in: [:]).isEmpty)
        #expect(DevelopmentCredential.apiKey(in: ["OPENAI_API_KEY": " \n "]).isEmpty)
        #expect(DevelopmentCredential.apiKey(in: ["OPENAI_API_KEY": "invalid\nheader"]).isEmpty)
    }

    @Test func environmentCredentialsAreDebugOnly() {
        let result = DevelopmentCredential.apiKey(in: ["OPENAI_API_KEY": "  synthetic-development-value  "])
        #if DEBUG
        #expect(result == "synthetic-development-value")
        #else
        #expect(result.isEmpty)
        #endif
    }
}
