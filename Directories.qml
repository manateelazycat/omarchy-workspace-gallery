pragma Singleton
import QtQuick
import Quickshell

QtObject {
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string stateHome: `${Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"}/omarchy-workspace-gallery`
}
