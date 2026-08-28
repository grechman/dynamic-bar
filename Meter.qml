import QtQuick

Item {
    id: root

    property real level: 0
    property color tint: "#87a987"
    property color rail: "#625e5a"
    property real thickness: 5

    implicitHeight: thickness

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: root.thickness
        radius: height / 2
        antialiasing: true
        color: Qt.rgba(root.rail.r, root.rail.g, root.rail.b, 0.35)

        Rectangle {
            width: Math.max(height, parent.width * Math.max(0, Math.min(1, root.level)))
            height: parent.height
            radius: parent.radius
            antialiasing: true
            color: root.tint

            Behavior on width {
                NumberAnimation {
                    duration: 450
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on color {
                ColorAnimation {
                    duration: 250
                }
            }
        }
    }
}
