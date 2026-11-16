// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import Foundation
import GridSpaceCore

/// Only the user's own editor fields. Never store fetched reply/quote bodies.
struct NativeDraft: Codable, Equatable {
    var text = ""
    var cw = ""
    var useCW = false
    var visibility = "public"
    var outcomeUnknown = false
    var attachments: [NativeAttachmentDraft] = []

    // Drafts written before native attachments remain readable.
    enum CodingKeys: String, CodingKey { case text, cw, useCW, visibility, outcomeUnknown, attachments }
    init(text: String = "", cw: String = "", useCW: Bool = false, visibility: String = "public", outcomeUnknown: Bool = false, attachments: [NativeAttachmentDraft] = []) {
        self.text = text; self.cw = cw; self.useCW = useCW; self.visibility = visibility
        self.outcomeUnknown = outcomeUnknown; self.attachments = attachments
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text); cw = try c.decode(String.self, forKey: .cw)
        useCW = try c.decode(Bool.self, forKey: .useCW); visibility = try c.decode(String.self, forKey: .visibility)
        outcomeUnknown = try c.decode(Bool.self, forKey: .outcomeUnknown)
        attachments = try c.decodeIfPresent([NativeAttachmentDraft].self, forKey: .attachments) ?? []
    }
}

struct NativeDraftStore {
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    @MainActor static func current() -> NativeDraftStore {
        #if DEBUG
        if AppSession.isTesting {
            let scope = LocalParityServer.current?.storeID.uuidString ?? (NativeComposerFixture.enabled ? ProcessInfo.processInfo.environment["GRIDSPACE_COMPOSER_TEST_STORE"] ?? "composer" : "unit")
            return NativeDraftStore(defaults: UserDefaults(suiteName: "GridSpaceNativeDraftUITests." + scope)!)
        }
        #endif
        return NativeDraftStore()
    }
    private func key(origin: ServerOrigin, account: String, reply: String?, renote: String?) -> String {
        var components = [origin.url.absoluteString, account, reply ?? ""]
        if let renote { components.append(renote) }
        let scope = try! JSONEncoder().encode(components)
        return "gridspace.nativeDraft.v1." + scope.base64EncodedString()
    }
    func read(origin: ServerOrigin, account: String, reply: String?, renote: String? = nil) -> NativeDraft? {
        guard let data = defaults.data(forKey: key(origin: origin, account: account, reply: reply, renote: renote)),
              let draft = try? JSONDecoder().decode(NativeDraft.self, from: data),
              ["public", "home", "followers"].contains(draft.visibility) else { return nil }
        return draft
    }
    func contains(origin: ServerOrigin, account: String, reply: String?, renote: String? = nil) -> Bool {
        defaults.object(forKey: key(origin: origin, account: account, reply: reply, renote: renote)) != nil
    }
    @discardableResult func write(_ draft: NativeDraft, origin: ServerOrigin, account: String, reply: String?, renote: String? = nil) -> Bool {
        // A newer or damaged record must not silently become a blank draft.
        if contains(origin: origin, account: account, reply: reply, renote: renote), read(origin: origin, account: account, reply: reply, renote: renote) == nil { return false }
        guard let data = try? JSONEncoder().encode(draft) else { return false }
        defaults.set(data, forKey: key(origin: origin, account: account, reply: reply, renote: renote))
        return true
    }
    func remove(origin: ServerOrigin, account: String, reply: String?, renote: String? = nil) {
        defaults.removeObject(forKey: key(origin: origin, account: account, reply: reply, renote: renote))
    }
    func attachmentIDs() -> Set<UUID>? {
        var ids = Set<UUID>()
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("gridspace.nativeDraft.v1.") {
            guard let data = value as? Data, let draft = try? JSONDecoder().decode(NativeDraft.self, from: data) else { return nil }
            ids.formUnion(draft.attachments.map(\.id))
        }
        return ids
    }
}
