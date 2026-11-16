// SPDX-FileCopyrightText: syuilo and misskey-project
// SPDX-License-Identifier: AGPL-3.0-only

import SwiftUI
import GridSpaceCore

enum ClientStyle {
    static let accent = Color(red: 0.11, green: 0.61, blue: 0.94)
}

struct ClientFeedTabs: View {
    @Binding var selection: String
    let tabs: [ClientFeedTab]
    let edit: () -> Void
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(tabs) { tab in
                                Button { withAnimation(.easeInOut(duration: 0.22)) { selection = tab.id } } label: {
                                    VStack(spacing: 13) {
                                        Text(tab.title).lineLimit(1)
                                            .font(.subheadline.weight(selection == tab.id ? .bold : .medium))
                                            .foregroundStyle(selection == tab.id ? .primary : .secondary)
                                        Capsule().fill(selection == tab.id ? ClientStyle.accent : .clear).frame(width: 42, height: 4)
                                    }.frame(width: max(90, (geometry.size.width - 44) / CGFloat(min(3, max(1, tabs.count))))).padding(.top, 14).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityAddTraits(selection == tab.id ? .isSelected : [])
                                    .accessibilityIdentifier("native-feed-tab:" + tab.id).id(tab.id)
                            }
                        }
                    }
                    .onChange(of: selection) { value in withAnimation(.easeInOut(duration: 0.22)) { proxy.scrollTo(value, anchor: .center) } }
                }
                Button(action: edit) { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 50).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("タブを編集").accessibilityIdentifier("native-feed-edit")
            }
        }.frame(height: 52).background(.bar).overlay(alignment: .bottom) { Divider() }
    }
}
