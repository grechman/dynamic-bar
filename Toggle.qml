import QtQuick

Item {
    id: root
    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var palette: ({
    })
    property string label: ""
    property bool on: false

    signal flipped

    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color accent: palette.accent || "#658594"

    height: 32

    Rectangle {
        anchors.fill: parent
        anchors.rightMargin: 6
        radius: 9
        antialiasing: true
        color: hit.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : "transparent"

        Behavior on color {
            ColorAnimation {
                duration: 130
            }
        }
    }

    Text {
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 62
        elide: Text.ElideRight
        text: root.label
        font.family: root.fontFamily
        font.pixelSize: 13
        color: root.on ? root.fg : root.fgAlt

        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }
    }

    Rectangle {
        id: track

        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 30
        height: 16
        radius: 8
        antialiasing: true
        color: root.on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

        Behavior on color {
            ColorAnimation {
                duration: 180
            }
        }

        Rectangle {
            y: 3
            x: root.on ? track.width - width - 3 : 3
            width: 10
            height: 10
            radius: 5
            antialiasing: true
            color: root.on ? root.fg : root.muted

            Behavior on x {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: 180
                }
            }
        }
    }

    MouseArea {
        id: hit

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.flipped()
    }
}
