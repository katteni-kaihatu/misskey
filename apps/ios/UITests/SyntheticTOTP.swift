// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

#if DEBUG
import CryptoKit
import Foundation
import XCTest

/// Test-only prover for the isolated server. Never reads a real account secret.
enum SyntheticTOTP {
    enum InvalidFixture: Error { case secret }

    static func code(secret: String, at time: TimeInterval) throws -> String {
        guard (16...128).contains(secret.count), time >= 0 else { throw InvalidFixture.secret }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        var accumulator: UInt32 = 0
        var bits = 0
        var bytes = Data()
        for character in secret.utf8 {
            guard let value = alphabet.firstIndex(of: character) else { throw InvalidFixture.secret }
            accumulator = ((accumulator << 5) | UInt32(value)) & 0xffff
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((accumulator >> bits) & 0xff))
            }
        }
        var counter = UInt64(time / 30).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let digest = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: bytes)))
        let offset = Int(digest[digest.count - 1] & 0x0f)
        let value = digest[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } & 0x7fffffff
        return String(format: "%06u", value % 1_000_000)
    }
}

final class SyntheticTOTPTests: XCTestCase {
    func testRFC6238SHA1VectorsIncludingLeadingZerosAndBeyond2038() throws {
        // RFC 6238 Appendix B's public SHA-1 vectors, reduced to six digits.
        // https://www.rfc-editor.org/rfc/rfc6238#appendix-B
        let key = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
        let vectors: [(TimeInterval, String)] = [(59, "287082"), (1_111_111_109, "081804"),
            (1_111_111_111, "050471"), (1_234_567_890, "005924"), (2_000_000_000, "279037"), (20_000_000_000, "353130")]
        for (time, expected) in vectors { XCTAssertEqual(try SyntheticTOTP.code(secret: key, at: time), expected) }
        XCTAssertThrowsError(try SyntheticTOTP.code(secret: "invalid", at: 59))
    }
}
#endif
