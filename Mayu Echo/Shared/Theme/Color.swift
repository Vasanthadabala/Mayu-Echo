import SwiftUI
import AppKit

extension Color {
    // Neutral gray surfaces — near-white in light mode, near-black in dark mode.
    static let mayuChatBackground = adaptive(
        light: NSColor(srgbRed: 0.976, green: 0.976, blue: 0.976, alpha: 1), // #F9F9F9
        dark: NSColor(srgbRed: 0.090, green: 0.090, blue: 0.090, alpha: 1)   // #171717
    )
    static let mayuSidebarBackground = adaptive(
        light: NSColor(srgbRed: 0.939, green: 0.939, blue: 0.939, alpha: 1), // #F0F0F0
        dark: NSColor(srgbRed: 0.114, green: 0.114, blue: 0.114, alpha: 1)   // #1D1D1D
    )
    static let mayuPanelBackground = adaptive(
        light: NSColor(srgbRed: 0.993, green: 0.993, blue: 0.993, alpha: 0.90),
        dark: NSColor(srgbRed: 0.136, green: 0.136, blue: 0.136, alpha: 0.92)
    )
    static let mayuElevatedBackground = adaptive(
        light: NSColor(srgbRed: 0.920, green: 0.920, blue: 0.920, alpha: 1), // #EBEBEB
        dark: NSColor(srgbRed: 0.156, green: 0.156, blue: 0.156, alpha: 1)   // #282828
    )
    static let mayuSelection = adaptive(
        light: NSColor(srgbRed: 0.892, green: 0.892, blue: 0.892, alpha: 1), // #E3E3E3
        dark: NSColor(srgbRed: 0.179, green: 0.179, blue: 0.179, alpha: 1)   // #2E2E2E
    )
    static let mayuUserBubble = adaptive(
        light: NSColor(srgbRed: 0.912, green: 0.912, blue: 0.912, alpha: 1), // #E9E9E9
        dark: NSColor(srgbRed: 0.162, green: 0.162, blue: 0.162, alpha: 1)   // #292929
    )
    static let mayuCodeBackground = adaptive(
        light: NSColor(srgbRed: 0.901, green: 0.901, blue: 0.901, alpha: 1), // #E6E6E6
        dark: NSColor(srgbRed: 0.115, green: 0.115, blue: 0.115, alpha: 1)   // #1D1D1D
    )
    static let mayuComposerBackground = adaptive(
        light: NSColor(srgbRed: 0.982, green: 0.982, blue: 0.982, alpha: 1), // #FAFAFA
        dark: NSColor(srgbRed: 0.124, green: 0.124, blue: 0.124, alpha: 1)   // #1F1F1F
    )

    static let mayuBorder = adaptive(light: NSColor(white: 0.0, alpha: 0.07), dark: NSColor(white: 1.0, alpha: 0.065))
    static let mayuStrongBorder = adaptive(light: NSColor(white: 0.0, alpha: 0.13), dark: NSColor(white: 1.0, alpha: 0.11))

    // Neutral gray accent — light gray on dark backgrounds, dark gray on light
    // backgrounds. No hue at all, so icon/text tinting reads as black-and-gray, not colored.
    static let mayuAccent = adaptive(
        light: NSColor(white: 0.35, alpha: 1),
        dark: NSColor(white: 0.80, alpha: 1)
    )
    static let mayuAccentSoft = adaptive(
        light: NSColor(white: 0.0, alpha: 0.06),
        dark: NSColor(white: 1.0, alpha: 0.10)
    )

    /// Fixed-brightness accent for solid fills (primary buttons). Always pair with `mayuOnAccent`
    /// so contrast holds regardless of the surrounding light/dark appearance.
    static let mayuAccentSolid = Color(NSColor(white: 0.20, alpha: 1))
    /// Foreground for content drawn on top of `mayuAccentSolid` / `mayuWarning`.
    static let mayuOnAccent = Color(NSColor(white: 0.97, alpha: 1))

    /// Fixed medium gray for destructive/stop states, always paired with `mayuOnAccent`.
    /// Distinct from `mayuAccentSolid` by lightness only — no hue, so it stays legible as
    /// both a plain icon (on either light or dark backgrounds) and a solid fill (under
    /// `mayuOnAccent`'s near-white text/icon) without needing to be red.
    static let mayuWarning = Color(NSColor(white: 0.40, alpha: 1))

    // Diff add/remove — distinguished by weight (bold vs muted), not hue, matching the
    // "+"/"-" prefix that already carries the meaning.
    static let mayuDiffAdded = Color.primary
    static let mayuDiffRemoved = Color.secondary

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        })
    }
}
