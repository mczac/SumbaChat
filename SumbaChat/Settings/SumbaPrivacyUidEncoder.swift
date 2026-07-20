//
// SPDX-FileCopyrightText: 2026 Peter Zakharov
// SPDX-License-Identifier: GPL-3.0-or-later
//

import Foundation

/// Privacy-policy `uid` encoding: UTF-8 bytes of `userId` XOR a fixed key, then lowercase hex.
///
/// Properties (for a non-empty fixed key):
/// - Invertible with the same key (server un-XOR after hex-decode).
/// - 1:1 for a given byte length (repeating-key XOR is bijective per position).
/// - Different UTF-8 lengths produce different hex lengths, so they cannot collide.
enum SumbaPrivacyUidEncoder {

    /// Hex-encoded XOR of `userId`. Empty if `userId` or key is missing/invalid.
    static func encode(_ userId: String) -> String {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let key = xorKeyBytes(), !key.isEmpty else { return "" }

        let plain = Array(trimmed.utf8)
        let xored = plain.enumerated().map { index, byte in
            byte ^ key[index % key.count]
        }
        return xored.map { String(format: "%02x", $0) }.joined()
    }

    /// Full privacy URL with `?uid=` when an active account user id can be encoded.
    static func privacyPolicyURL(baseURL: String, userId: String?) -> URL? {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmedBase) else { return nil }

        if let userId {
            let encoded = encode(userId)
            if !encoded.isEmpty {
                var items = components.queryItems ?? []
                items.removeAll { $0.name == "uid" }
                items.append(URLQueryItem(name: "uid", value: encoded))
                components.queryItems = items
            }
        }

        return components.url
    }

    private static func xorKeyBytes() -> [UInt8]? {
        let hex = brandingUidXorKeyHex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !hex.isEmpty, hex.count % 2 == 0 else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
