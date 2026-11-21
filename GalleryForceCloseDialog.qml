pragma ComponentBehavior: Bound
import "."
import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts

Item {
    id: root

    required property string windowTitle
    readonly property bool chinese: Qt.locale().name.startsWith("zh")
    property bool confirmSelected: false
    signal canceled()
    signal confirmed()

    onVisibleChanged: if (root.visible) root.confirmSelected = false

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Left:
            root.confirmSelected = false;
            break;
        case Qt.Key_Right:
            root.confirmSelected = true;
            break;
        case Qt.Key_Tab:
        case Qt.Key_Backtab:
            root.confirmSelected = !root.confirmSelected;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            if (root.confirmSelected)
                root.confirmed();
            else
                root.canceled();
            break;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#99000000"

        MouseArea {
            anchors.fill: parent
            onClicked: root.canceled()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 420)
        height: content.implicitHeight + 40
        radius: 12
        color: TuiStyle.panel
        border.color: TuiStyle.accent

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

            Text {
                Layout.fillWidth: true
                text: (root.chinese ? "强制关闭“%1”？" : qsTr("Force close “%1”?")).arg(root.windowTitle)
                textFormat: Text.PlainText
                color: TuiStyle.fg
                font.pixelSize: 16
                font.bold: true
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: root.chinese ? "未保存的内容将丢失，同一进程的其他窗口也可能关闭。"
                    : qsTr("Unsaved changes will be lost. Other windows from the same process may also close.")
                textFormat: Text.PlainText
                color: TuiStyle.fg
                font.pixelSize: 14
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8

                DialogButton {
                    text: root.chinese ? "取消" : qsTr("Cancel")
                    highlighted: !root.confirmSelected
                    onClicked: root.canceled()
                }

                DialogButton {
                    text: root.chinese ? "强制关闭" : qsTr("Force close")
                    highlighted: root.confirmSelected
                    outline: TuiStyle.urgent
                    onClicked: root.confirmed()
                }
            }
        }
    }

    component DialogButton: Controls.Button {
        id: button
        property color outline: button.highlighted ? TuiStyle.accent : TuiStyle.inactiveBorder
        focusPolicy: Qt.NoFocus
        horizontalPadding: 14
        verticalPadding: 8

        contentItem: Text {
            text: button.text
            textFormat: Text.PlainText
            color: TuiStyle.fg
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        background: Rectangle {
            radius: 6
            border.color: button.outline
            color: button.hovered || button.highlighted ? TuiStyle.accentWash(button.outline) : "transparent"
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
    }
}
