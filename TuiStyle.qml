pragma Singleton
import QtQuick
import qs.Commons

QtObject {
    readonly property color bg: Color.background
    readonly property color panel: Color.background
    readonly property color fg: Color.foreground
    readonly property color dim: Color.muted
    readonly property color line: Color.muted
    readonly property color accent: Color.accent
    readonly property color selection: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22)
    readonly property color inactiveBorder: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.32)
    readonly property color controlActiveBorder: Color.accent
    readonly property color surfaceRaised: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.10)
    readonly property color surfaceHover: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
    readonly property color surfaceSubtle: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
    readonly property color menuBorder: inactiveBorder
    readonly property color surfacePressed: surfaceHover
    readonly property color shellBorder: inactiveBorder
    readonly property color lineColor: line
    readonly property real dividerOpacity: 0.28
    function accentWash(color) { return Qt.rgba(color.r, color.g, color.b, 0.14) }
}
