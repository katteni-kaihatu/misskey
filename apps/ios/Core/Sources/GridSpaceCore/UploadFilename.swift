// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

public enum UploadFilename {
    /// A display name from a provider is never a path. Bound UTF-8 bytes, not
    /// characters, so emoji names also fit the filesystem's component limit.
    public static func sanitized(_ suggestedName: String) -> String {
        let leaf = (suggestedName.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        var name = String(String.UnicodeScalarView(leaf.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && $0 != "/" && $0 != "\\"
        }))
        let ext = (name as NSString).pathExtension
        let suffix = !ext.isEmpty && ext.utf8.count <= 32 ? "." + ext : ""
        if !suffix.isEmpty { name.removeLast(suffix.count) }
        while (name + suffix).utf8.count > 180 { name.removeLast() }
        name += suffix
        return name.isEmpty || name == "." || name == ".." ? "attachment" : name
    }
}
