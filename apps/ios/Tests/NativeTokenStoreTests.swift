// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import GridSpaceCore
import Security
import XCTest
@testable import GridSpace

final class NativeTokenStoreTests: XCTestCase {
    func testTokenIsDeviceOnlyAndIsolatedByExactOriginIncludingPort() throws {
        let host = "synthetic-" + UUID().uuidString.lowercased() + ".invalid"
        let first = try ServerOrigin("https://" + host)
        let otherPort = try ServerOrigin("https://" + host + ":8443")
        defer { try? NativeTokenStore.remove(origin: first); try? NativeTokenStore.remove(origin: otherPort) }
        #if targetEnvironment(simulator)
        do { _ = try NativeTokenStore.read(origin: first) }
        catch ClientAPIError.keychain(let status) where status == -34018 {
            throw XCTSkip("The unsigned Simulator test host has no Keychain entitlement; the signed device test covers actual storage")
        }
        #endif
        XCTAssertNil(try NativeTokenStore.read(origin: first))
        try NativeTokenStore.write("synthetic-one", origin: first)
        try NativeTokenStore.write("synthetic-two", origin: otherPort)
        try NativeTokenStore.write("synthetic-replaced", origin: first)
        XCTAssertEqual(try NativeTokenStore.read(origin: first), "synthetic-replaced")
        XCTAssertEqual(try NativeTokenStore.read(origin: otherPort), "synthetic-two")
        var attributes: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: "dev.gridspace.ios.miauth.v1",
                                   kSecAttrAccount as String: first.url.absoluteString,
                                   kSecReturnAttributes as String: true]
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &attributes), errSecSuccess)
        let result = try XCTUnwrap(attributes as? [String: Any])
        XCTAssertEqual(result[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertNotEqual(result[kSecAttrSynchronizable as String] as? Bool, true)
        try NativeTokenStore.remove(origin: first)
        XCTAssertNil(try NativeTokenStore.read(origin: first))
        XCTAssertEqual(try NativeTokenStore.read(origin: otherPort), "synthetic-two")
    }
}
