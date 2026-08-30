import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property real level: 0
    property bool charging: false
    property color tint: "#a6a69c"
    property color shell: "#a6a69c"
    property color hollow: "#282727"
    property color chargeMark: "#f4f4ef"
    property real unit: 1

    readonly property real stroke: 1.3 * unit
    readonly property real inset: stroke + 1.1 * unit
    readonly property real bodyWidth: Math.round(24 * unit)
    readonly property real bodyHeight: Math.round(12 * unit)
    readonly property real capWidth: 2.4 * unit

    implicitWidth: bodyWidth + capWidth + 1.1 * unit
    implicitHeight: bodyHeight

    Rectangle {
        id: body

        width: root.bodyWidth
        height: root.bodyHeight
        radius: 3.6 * root.unit
        antialiasing: true
        color: "transparent"
        border.width: root.stroke
        border.color: root.shell

        Rectangle {
            x: root.inset
            y: root.inset
            width: Math.max(0, (body.width - 2 * root.inset) * Math.max(0, Math.min(1, root.level)))
            height: body.height - 2 * root.inset
            radius: 1.8 * root.unit
            antialiasing: true
            color: root.tint

            Behavior on width {
                NumberAnimation {
                    duration: 400
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

    Rectangle {
        x: root.bodyWidth + 1.1 * root.unit
        anchors.verticalCenter: body.verticalCenter
        width: root.capWidth
        height: 5.4 * root.unit
        radius: width / 2
        antialiasing: true
        color: root.shell
    }

    Shape {
        id: bolt

        anchors.centerIn: body
        height: root.bodyHeight - 0.4 * root.unit
        width: height * 0.72
        visible: root.charging
        antialiasing: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.chargeMark
            strokeColor: root.hollow
            strokeWidth: Math.max(1, root.unit)
            joinStyle: ShapePath.MiterJoin
            startX: bolt.width * 0.62
            startY: 0

            PathLine {
                x: bolt.width * 0.06
                y: bolt.height * 0.57
            }

            PathLine {
                x: bolt.width * 0.44
                y: bolt.height * 0.57
            }

            PathLine {
                x: bolt.width * 0.34
                y: bolt.height
            }

            PathLine {
                x: bolt.width * 0.96
                y: bolt.height * 0.42
            }

            PathLine {
                x: bolt.width * 0.56
                y: bolt.height * 0.42
            }

            PathLine {
                x: bolt.width * 0.62
                y: 0
            }
        }
    }
}
