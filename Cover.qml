import QtQuick
import QtQuick.Effects

Item {
    id: root

    property string path: ""
    property real curve: 0
    property real haze: 0

    readonly property int pixels: Math.max(16, Math.round(width * Screen.devicePixelRatio))
    readonly property bool shaped: curve > 0 || haze > 0
    readonly property bool ready: path !== "" && art.status === Image.Ready

    Image {
        id: art

        anchors.fill: parent
        visible: !root.shaped && status === Image.Ready
        source: root.path ? "file://" + root.path : ""
        sourceSize.width: root.pixels
        sourceSize.height: root.pixels
        smooth: true
        cache: true
    }

    Item {
        id: stencil

        anchors.fill: parent
        visible: false
        layer.enabled: root.shaped

        Rectangle {
            anchors.fill: parent
            radius: root.curve
            antialiasing: true
            color: "white"
        }
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.shaped && art.status === Image.Ready
        source: art
        maskEnabled: true
        maskSource: stencil
        maskSpreadAtMin: 1
        maskThresholdMin: 0.5
        blurEnabled: root.haze > 0
        blur: root.haze
        blurMax: 40
    }
}
