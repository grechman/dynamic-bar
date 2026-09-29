import QtQuick
import QtQuick.Effects

Item {
    id: root

    property var palette: ({
    })
    property real radius: 22
    property real depth: 1

    default property alias content: body.data

    readonly property color bg: palette.bg || "#181616"
    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color accent: palette.accent || "#658594"

    function light(amount) {
        return Qt.rgba(fg.r, fg.g, fg.b, amount);
    }

    function shade(amount) {
        return Qt.rgba(bg.r, bg.g, bg.b, amount);
    }

    Rectangle {
        id: slab

        anchors.fill: parent
        radius: root.radius
        antialiasing: true
        color: root.shade(0.5)
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: slab
        source: slab
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.55 * root.depth)
        shadowBlur: 1
        shadowVerticalOffset: 14 * root.depth
        shadowScale: 0.98
        autoPaddingEnabled: true
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        antialiasing: true

        gradient: Gradient {
            orientation: Gradient.Vertical

            GradientStop {
                position: 0
                color: root.shade(0.5)
            }

            GradientStop {
                position: 1
                color: root.shade(0.36)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        antialiasing: true

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: root.light(0.075)
            }

            GradientStop {
                position: 0.34
                color: root.light(0.012)
            }

            GradientStop {
                position: 0.52
                color: root.light(0.05)
            }

            GradientStop {
                position: 0.7
                color: root.light(0.008)
            }

            GradientStop {
                position: 1
                color: root.light(0.04)
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: root.radius - 1
        antialiasing: true
        color: "transparent"
        border.width: 1
        border.color: root.light(0.06)
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        antialiasing: true
        color: "transparent"
        border.width: 1
        border.color: root.light(0.2)
    }

    Rectangle {
        x: root.radius * 0.8
        y: 1
        width: parent.width - root.radius * 1.6
        height: 1
        radius: 0.5
        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: root.light(0)
            }

            GradientStop {
                position: 0.5
                color: root.light(0.5)
            }

            GradientStop {
                position: 1
                color: root.light(0)
            }
        }
    }

    Item {
        id: body

        anchors.fill: parent
    }
}
