import QtQuick

Item {
    id: root
    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var palette: ({})
    property string text: ""
    property bool active: false
    property real anchorX: 0
    property real anchorY: 0

    readonly property color bgAlt: palette.bg_alt || "#282727"
    readonly property color fg: palette.fg || "#c5c9c5"

    visible: opacity > 0.01
    opacity: active && text !== "" ? 1 : 0
    width: body.width
    height: body.height
    x: Math.round(anchorX - width / 2)
    y: anchorY + 8 + (active ? 0 : -6)

    Behavior on opacity {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }
    Behavior on y {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: body
        width: label.implicitWidth + 28
        height: label.implicitHeight + 20
        radius: 14
        color: root.bgAlt
        border.width: 1
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

        Text {
            id: label
            anchors.centerIn: parent
            text: root.text
            textFormat: Text.RichText
            horizontalAlignment: root.text.indexOf("<pre") === 0 ? Text.AlignLeft : Text.AlignHCenter
            font.family: root.fontFamily
            font.pixelSize: 14
            color: root.fg
        }
    }
}
