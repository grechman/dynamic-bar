import QtQuick

Item {
    id: root
    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var palette: ({
    })
    property string label: ""
    property string detail: ""
    property bool busy: false
    property bool toggled: false
    property bool switchable: true

    signal flipped

    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color accent: palette.accent || "#658594"

    height: 36

    Text {
        id: title

        x: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.family: root.fontFamily
        font.pixelSize: 12
        font.letterSpacing: 1.1
        color: root.fgAlt
    }

    Text {
        x: title.x + title.width + 10
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - (root.switchable ? 62 : 12)
        elide: Text.ElideRight
        text: root.detail
        font.family: root.fontFamily
        font.pixelSize: 13
        color: root.toggled ? root.fg : root.fgAlt
        opacity: root.busy ? dim.value : 1
    }

    QtObject {
        id: dim

        property real value: 1
    }

    SequentialAnimation {
        running: root.busy
        loops: Animation.Infinite

        NumberAnimation {
            target: dim
            property: "value"
            to: 0.35
            duration: 620
            easing.type: Easing.InOutSine
        }

        NumberAnimation {
            target: dim
            property: "value"
            to: 1
            duration: 620
            easing.type: Easing.InOutSine
        }

        onStopped: dim.value = 1
    }

    Rectangle {
        id: track

        visible: root.switchable
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        width: 36
        height: 19
        radius: 9.5
        antialiasing: true
        color: root.toggled ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

        Behavior on color {
            ColorAnimation {
                duration: 180
            }
        }

        Rectangle {
            y: 3.5
            x: root.toggled ? track.width - width - 3.5 : 3.5
            width: 12
            height: 12
            radius: 6
            antialiasing: true
            color: root.toggled ? root.fg : root.muted

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

        MouseArea {
            anchors.fill: parent
            anchors.margins: -5
            cursorShape: Qt.PointingHandCursor
            onClicked: root.flipped()
        }
    }
}
