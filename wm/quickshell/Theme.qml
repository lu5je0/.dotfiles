pragma Singleton
import QtQuick

QtObject {
    // ── Active theme name ──────────────────────────────────────────
    property string currentTheme: "md3-cobalt-night"

    // ── Theme definitions ──────────────────────────────────────────
    readonly property var _themes: ({
        "md3-cobalt-night": {
            name: "Cobalt Night",
            panelBg: "#0F1117", panelBorder: "#252740", surface: "#1A1C28",
            surfaceContainer: "#252740", surfaceContainerHigh: "#2E3148", surfaceBright: "#3A3E60",
            primary: "#9BBDE8", primaryContainer: "#1E3058", onPrimaryContainer: "#C8D8F5",
            tileActive: "#9BBDE8", tileActiveText: "#0F1117",
            tileInactive: "#2E3148", tileInactiveText: "#E0E2F0",
            sliderTrack: "#2E3148", sliderActiveTrack: "#9BBDE8", sliderThumb: "#9BBDE8",
            textPrimary: "#E0E2F0", textSecondary: "#8E90A8",
            toggleOff: "#404460", connected: "#86D5A0", error: "#F2A8B8",
            secondaryContainer: "#1E3058", textOnSecondaryContainer: "#C8D8F5",
            shelfBg: "#0F1117"
        }
    })

    // ── Active theme reference ─────────────────────────────────────
    readonly property var _t: _themes[currentTheme] || _themes["md3-cobalt-night"]

    // ── Themed color properties ────────────────────────────────────
    // Surface colors
    readonly property color panelBg: _t.panelBg
    readonly property color panelBorder: _t.panelBorder
    readonly property color surface: _t.surface
    readonly property color surfaceContainer: _t.surfaceContainer
    readonly property color surfaceContainerHigh: _t.surfaceContainerHigh
    readonly property color surfaceBright: _t.surfaceBright

    // Primary colors
    readonly property color primary: _t.primary
    readonly property color primaryContainer: _t.primaryContainer
    readonly property color textOnPrimaryContainer: _t.onPrimaryContainer

    // Secondary colors
    readonly property color secondaryContainer: _t.secondaryContainer
    readonly property color textOnSecondaryContainer: _t.textOnSecondaryContainer

    // Tile states
    readonly property color tileActive: _t.tileActive
    readonly property color tileActiveText: _t.tileActiveText
    readonly property color tileInactive: _t.tileInactive
    readonly property color tileInactiveText: _t.tileInactiveText

    // Slider colors
    readonly property color sliderTrack: _t.sliderTrack
    readonly property color sliderActiveTrack: _t.sliderActiveTrack
    readonly property color sliderThumb: _t.sliderThumb

    // Text colors
    readonly property color textPrimary: _t.textPrimary
    readonly property color textSecondary: _t.textSecondary

    // Semantic colors
    readonly property color connected: _t.connected
    readonly property color error: _t.error
    readonly property color toggleOff: _t.toggleOff

    // Shelf
    readonly property color _shelfBgColor: _t.shelfBg
    readonly property color shelfBg: Qt.rgba(_shelfBgColor.r, _shelfBgColor.g, _shelfBgColor.b, 0.85)

    // ── Backward-compatible aliases ────────────────────────────────
    // Used by shelf, controlcenter, and other modules
    readonly property color bg: panelBg
    readonly property color accent: primary
    readonly property color surfaceHigh: surfaceBright
    readonly property color hoverOverlay: Qt.rgba(1, 1, 1, 0.08)
    readonly property color textDisabled: Qt.rgba(textSecondary.r, textSecondary.g, textSecondary.b, 0.35)

    // ── Font properties ────────────────────────────────────────────
    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontSizeNormal: 12
    readonly property int fontSizeLarge: 16
    readonly property int fontSizeXL: 24
    readonly property int fontSizeSmall: 10
    readonly property int fontSizeXS: 9

    // ── Spacing ────────────────────────────────────────────────────
    readonly property int radiusSmall: 8
    readonly property int radiusLarge: 14
    readonly property int paddingNormal: 12
    readonly property int paddingLarge: 20
    readonly property int padding: 16
    readonly property int paddingSmall: 8

    // ── Shelf-specific ─────────────────────────────────────────────
    readonly property int shelfHeight: 48

    // ── Layout constants ───────────────────────────────────────────
    readonly property int panelWidth: 360
    readonly property int panelRadius: 24
    readonly property int tileRadius: 20
    readonly property int tileHeight: 64
    readonly property int sliderHeight: 44

    // ── Spacing scale ──────────────────────────────────────────────
    readonly property int spacingSmall: 8
    readonly property int spacingMedium: 12
    readonly property int spacingLarge: 16

     // ── Animation durations (ms) ───────────────────────────────────
    readonly property int animDuration: 200
    readonly property int animDurationFast: 120

    // ── Theme metadata access ──────────────────────────────────────
    readonly property string themeName: _t.name
    readonly property var themeKeys: Object.keys(_themes)
}
