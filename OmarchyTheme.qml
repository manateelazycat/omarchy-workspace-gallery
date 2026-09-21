pragma Singleton
import QtQuick
import qs.Commons

QtObject {
    readonly property color accent: Color.accent
    readonly property color accentSoft: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18)
    readonly property color accentBorder: Color.accent
    readonly property color accentActiveBorder: Color.accent
    readonly property color tintedBackground: Color.background
}
