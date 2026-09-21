pragma Singleton
import QtQuick

QtObject {
    signal dismissed()
    property var currentWindow: null

    function addDismissable(window) { currentWindow = window }
    function dismiss() { currentWindow = null; dismissed() }
}
