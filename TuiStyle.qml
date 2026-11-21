pragma Singleton
import QtQuick
import qs.Commons as Commons
QtObject {
    readonly property color bg: Commons.Color.background
    readonly property color panel: Commons.Color.background
    readonly property color fg: Commons.Color.foreground
    readonly property color dim: Commons.Color.muted
    readonly property color line: Commons.Color.muted
    readonly property color accent: Commons.Color.accent
    readonly property color urgent: Commons.Color.urgent
    readonly property color selection: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22)
    readonly property color inactiveBorder: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.32)
    readonly property color controlActiveBorder: Commons.Color.accent
    readonly property color surfaceRaised: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.10)
    readonly property color surfaceHover: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.18)
    readonly property color surfaceSubtle: Qt.rgba(Commons.Color.foreground.r, Commons.Color.foreground.g, Commons.Color.foreground.b, 0.06)
    readonly property color menuBorder: inactiveBorder
    readonly property color surfacePressed: surfaceHover
    readonly property color shellBorder: inactiveBorder
    readonly property color lineColor: line
    readonly property real dividerOpacity: 0.28
    function accentWash(color) { return Qt.rgba(color.r, color.g, color.b, 0.14) }
}
