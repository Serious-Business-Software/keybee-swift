import XCTest
@testable import Keybee

final class Base64URLTests: XCTestCase {
    func test_base64url_roundTripAndRejectsPadding() {
        XCTAssertEqual(Base64URL.decode("AQID"), Data([1, 2, 3]))
        XCTAssertEqual(Base64URL.decode("AQI"), Data([1, 2]))
        XCTAssertNil(Base64URL.decode("AQI="))
        XCTAssertNil(Base64URL.decode("A+I/"))
        XCTAssertNil(Base64URL.decode("A"))
        XCTAssertEqual(Base64URL.encode(Data([0xfb, 0xff])), "-_8")
        XCTAssertEqual(Base64URL.decode("-_8"), Data([0xfb, 0xff]))
    }
}
