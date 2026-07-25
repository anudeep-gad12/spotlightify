import XCTest
@testable import Spotlightify

final class PKCETests: XCTestCase {
    func testGeneratedPKCEVerifierAndChallengeArePopulated() {
        let pair = PKCEPair.generate()

        XCTAssertEqual(pair.codeVerifier.count, 64)
        XCTAssertFalse(pair.codeChallenge.isEmpty)
        XCTAssertFalse(pair.codeChallenge.contains("+"))
        XCTAssertFalse(pair.codeChallenge.contains("/"))
        XCTAssertFalse(pair.codeChallenge.contains("="))
    }

    func testCodeChallengeMatchesRFCTransformation() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

        let challenge = PKCEPair.codeChallenge(for: verifier)

        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
}
