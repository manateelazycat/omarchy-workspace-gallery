pragma Singleton
import QtQuick
import Quickshell

QtObject {
    function expandHomePath(path) {
        const value = String(path || "")
        if (value === "~") return Quickshell.env("HOME") || ""
        if (value.startsWith("~/")) return `${Quickshell.env("HOME")}/${value.slice(2)}`
        return value
    }

    function trimFileProtocol(path) {
        const value = String(path || "")
        return value.startsWith("file://") ? value.slice(7) : value
    }
}
