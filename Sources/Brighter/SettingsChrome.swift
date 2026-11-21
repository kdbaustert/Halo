import AppKit
import SwiftUI

// The Settings window's building blocks, matching Cmd-Tab's: a sidebar of tabs with gradient icon
// badges, and pages built from titled sections whose rows sit inside a rounded card on glass.

enum SettingsChrome {
    static let cardCorner: CGFloat = 14
    static let hairline: CGFloat = 0.5

    /// Heavier than a card on an opaque window would need: a fainter fill over glass that is
    /// itself showing the desktop doesn't read as a card at all.
    static let cardFill = Color.primary.opacity(0.05)
    static let cardBorder = Color.primary.opacity(0.09)
    static let divider = Color.primary.opacity(0.07)

    static let rowInset: CGFloat = 14
    static let pageInset: CGFloat = 18
}

/// A tab's content: a scrolling column of sections under the tab's title.
struct SettingsPage<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 21, weight: .bold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 2)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, SettingsChrome.pageInset)
            .padding(.top, 15)
            .padding(.bottom, 24)
        }
    }
}

/// A titled group of rows inside a rounded card. Each row draws its own top divider, and the
/// first one lands under the card's border, so rows need no idea of which one is last.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content

    private var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: SettingsChrome.cardCorner, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) { content }
                .background(card.fill(SettingsChrome.cardFill))
                .clipShape(card)
                .overlay {
                    card.strokeBorder(SettingsChrome.cardBorder, lineWidth: SettingsChrome.hairline)
                }

            if let footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// Label and optional explanation on the left, control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control
                // Controls are built with hidden labels so they line up down the card's edge,
                // which also hides them from VoiceOver. This puts the row's title back.
                .accessibilityLabel(Text(title))
                .accessibilityHint(Text(subtitle ?? ""))
        }
        .padding(.horizontal, SettingsChrome.rowInset)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(SettingsChrome.divider)
                .frame(height: SettingsChrome.hairline)
        }
    }
}

struct SettingsToggle: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A tab's icon in the sidebar: a white SF Symbol on a rounded gradient badge.
struct SettingsTabIcon: View {
    let symbol: String
    let gradient: [Color]
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundStyle(.white)
            }
    }
}

/// Glass that blurs the desktop behind the window.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        if view.material != material { view.material = material }
    }
}
