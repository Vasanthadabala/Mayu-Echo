import SwiftUI
import AppKit

extension Color {
    // Warm neutral surfaces — cream in light mode, warm charcoal in dark mode.
    static let mayuChatBackground = adaptive(
        light: NSColor(srgbRed: 0.980, green: 0.976, blue: 0.965, alpha: 1), // #FAF9F6
        dark: NSColor(srgbRed: 0.098, green: 0.086, blue: 0.078, alpha: 1)   // #191614
    )
    static let mayuSidebarBackground = adaptive(
        light: NSColor(srgbRed: 0.953, green: 0.945, blue: 0.918, alpha: 1), // #F3F1EA
        dark: NSColor(srgbRed: 0.125, green: 0.110, blue: 0.098, alpha: 1)   // #201C19
    )
    static let mayuPanelBackground = adaptive(
        light: NSColor(srgbRed: 1.000, green: 0.996, blue: 0.984, alpha: 0.90),
        dark: NSColor(srgbRed: 0.149, green: 0.133, blue: 0.125, alpha: 0.92)
    )
    static let mayuElevatedBackground = adaptive(
        light: NSColor(srgbRed: 0.937, green: 0.929, blue: 0.894, alpha: 1), // #EFEDE4
        dark: NSColor(srgbRed: 0.173, green: 0.153, blue: 0.141, alpha: 1)   // #2C2724
    )
    static let mayuSelection = adaptive(
        light: NSColor(srgbRed: 0.918, green: 0.902, blue: 0.855, alpha: 1), // #EAE6DA
        dark: NSColor(srgbRed: 0.200, green: 0.176, blue: 0.161, alpha: 1)   // #332D29
    )
    static let mayuUserBubble = adaptive(
        light: NSColor(srgbRed: 0.937, green: 0.918, blue: 0.882, alpha: 1), // #EFEAE1
        dark: NSColor(srgbRed: 0.180, green: 0.161, blue: 0.145, alpha: 1)   // #2E2925
    )
    static let mayuCodeBackground = adaptive(
        light: NSColor(srgbRed: 0.925, green: 0.910, blue: 0.867, alpha: 1), // #ECE8DD
        dark: NSColor(srgbRed: 0.129, green: 0.114, blue: 0.102, alpha: 1)   // #211D1A
    )
    static let mayuComposerBackground = adaptive(
        light: NSColor(srgbRed: 0.988, green: 0.984, blue: 0.973, alpha: 1), // #FCFBF8
        dark: NSColor(srgbRed: 0.141, green: 0.122, blue: 0.110, alpha: 1)   // #241F1C
    )

    static let mayuBorder = adaptive(light: NSColor(white: 0.0, alpha: 0.07), dark: NSColor(white: 1.0, alpha: 0.065))
    static let mayuStrongBorder = adaptive(light: NSColor(white: 0.0, alpha: 0.13), dark: NSColor(white: 1.0, alpha: 0.11))

    // Signature terracotta accent (Claude-inspired), tuned per appearance for legible icon/text tinting.
    static let mayuAccent = adaptive(
        light: NSColor(srgbRed: 0.757, green: 0.376, blue: 0.239, alpha: 1), // #C1603D
        dark: NSColor(srgbRed: 0.886, green: 0.537, blue: 0.373, alpha: 1)  // #E2895F
    )
    static let mayuAccentSoft = adaptive(
        light: NSColor(srgbRed: 0.757, green: 0.376, blue: 0.239, alpha: 0.13),
        dark: NSColor(srgbRed: 0.886, green: 0.537, blue: 0.373, alpha: 0.17)
    )

    /// Fixed-brightness accent for solid fills (primary buttons). Always pair with `mayuOnAccent`
    /// so contrast holds regardless of the surrounding light/dark appearance.
    static let mayuAccentSolid = Color(NSColor(srgbRed: 0.741, green: 0.357, blue: 0.224, alpha: 1)) // #BD5B39
    /// Foreground for content drawn on top of `mayuAccentSolid` / `mayuWarning`.
    static let mayuOnAccent = Color(NSColor(srgbRed: 1.0, green: 0.973, blue: 0.949, alpha: 1)) // #FFF8F2

    /// Fixed warm red for destructive/stop states, always paired with `mayuOnAccent`.
    static let mayuWarning = Color(NSColor(srgbRed: 0.722, green: 0.251, blue: 0.165, alpha: 1)) // #B8402A

    // Git-diff semantics, tuned warm so they sit naturally on the cream/charcoal surfaces.
    static let mayuDiffAdded = adaptive(
        light: NSColor(srgbRed: 0.267, green: 0.498, blue: 0.220, alpha: 1), // #447F38
        dark: NSColor(srgbRed: 0.463, green: 0.702, blue: 0.396, alpha: 1)  // #76B365
    )
    static let mayuDiffRemoved = adaptive(
        light: NSColor(srgbRed: 0.722, green: 0.251, blue: 0.165, alpha: 1), // #B8402A
        dark: NSColor(srgbRed: 0.847, green: 0.408, blue: 0.318, alpha: 1)  // #D86851
    )

    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? dark : light
        })
    }
}
