import QtQuick

Text {
    renderType: Text.NativeRendering
    // Window titles/classes come from hyprctl and are not trusted markup.
    // Keep them as literal text so Qt does not interpret rich-text/resource
    // URLs supplied by a local application.
    textFormat: Text.PlainText
}
