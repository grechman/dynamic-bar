import QtQuick
import QtQuick.Effects

Item {
    id: root

    property var bubble: null
    property var lastBubble: null
    property var palette: ({})
    property real restX: 0
    property real mergeX: 0
    property bool merging: false
    property bool exchanging: false
    property var rendered: null

    signal activated(int half)

    readonly property var view: rendered || lastBubble
    readonly property var second: view && view.second ? view.second : null
    readonly property color secondTint: Qt.lighter(tintFor(second), 1.3)
    readonly property bool present: !!bubble
    readonly property color bg: palette.bg || "#181616"
    readonly property color bgAlt: palette.bg_alt || "#282727"
    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color ok: palette.ok || "#87a987"
    readonly property color crit: palette.crit || "#c4746e"
    readonly property color claude: palette.claude || "#D97757"

    function mix(base, tint, amount) {
        return Qt.rgba(base.r + (tint.r - base.r) * amount, base.g + (tint.g - base.g) * amount, base.b + (tint.b - base.b) * amount, 1);
    }

    function tintFor(entry) {
        if (!entry)
            return bgAlt;
        if (entry.kind === "done")
            return mix(bgAlt, ok, 0.25);
        if (entry.kind === "blocked")
            return mix(bgAlt, crit, 0.22);
        return bgAlt;
    }

    function edgeFor(entry) {
        if (entry && entry.kind === "done")
            return Qt.rgba(ok.r, ok.g, ok.b, 0.48);
        if (entry && entry.kind === "blocked")
            return Qt.rgba(crit.r, crit.g, crit.b, 0.48);
        return Qt.rgba(fg.r, fg.g, fg.b, 0.16);
    }

    function inkFor(entry) {
        if (!entry)
            return fg;
        if (entry.kind === "done")
            return ok;
        if (entry.kind === "blocked")
            return crit;
        return entry.provider === "claude" ? claude : fg;
    }

    onBubbleChanged: {
        if (!bubble)
            return;
        lastBubble = bubble;
        if (!rendered || vis < 0.25 || merging) {
            rendered = bubble;
            return;
        }
        if (rendered.provider !== bubble.provider) {
            exchange.restart();
            return;
        }
        rendered = bubble;
    }

    property real merged: 1
    property real vis: 0
    property real split: second ? 1 : 0

    Behavior on split {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutCubic
        }
    }

    width: 27 + 17 * split
    height: 27
    transformOrigin: Item.Center
    x: restX + (mergeX - (width - 27) / 2 - restX) * merged
    scale: 1 - 0.58 * merged
    opacity: vis

    function surface(delay) {
        dive.stop();
        emergePause.duration = delay;
        emerge.restart();
    }

    onPresentChanged: {
        if (present) {
            merged = 1;
            vis = 0;
            surface(110);
        } else if (merged < 0.5) {
            fade.restart();
        } else {
            vis = 0;
        }
    }

    onMergingChanged: {
        if (merging)
            dive.restart();
        else if (present && !exchanging)
            surface(0);
    }

    onExchangingChanged: {
        if (exchanging)
            dive.restart();
        else if (present && !merging)
            surface(0);
    }

    SequentialAnimation {
        id: emerge
        PauseAnimation {
            id: emergePause
            duration: 110
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "merged"
                to: 0
                duration: 280
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: root
                property: "vis"
                to: 1
                duration: 170
                easing.type: Easing.OutCubic
            }
        }
    }

    ParallelAnimation {
        id: dive
        NumberAnimation {
            target: root
            property: "merged"
            to: 1
            duration: 200
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: root
            property: "vis"
            to: 0
            duration: 190
            easing.type: Easing.InQuad
        }
    }

    NumberAnimation {
        id: fade
        target: root
        property: "vis"
        to: 0
        duration: 160
        easing.type: Easing.InCubic
    }

    SequentialAnimation {
        id: exchange
        ScriptAction {
            script: root.exchanging = true
        }
        PauseAnimation {
            duration: 210
        }
        ScriptAction {
            script: {
                root.rendered = root.bubble;
                root.exchanging = false;
            }
        }
    }

    Rectangle {
        id: base
        anchors.fill: parent
        radius: height / 2
        antialiasing: true
        color: root.tintFor(root.view)
        border.width: 1
        border.color: root.edgeFor(root.view)

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 200
            }
        }
    }

    Item {
        id: tintSource
        anchors.fill: parent
        visible: false
        layer.enabled: root.split > 0.01

        Rectangle {
            x: parent.width / 2 - 6.06
            y: parent.height / 2 - 103.5
            width: 200
            height: 200
            transformOrigin: Item.Left
            rotation: 30

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Qt.rgba(root.secondTint.r, root.secondTint.g, root.secondTint.b, 0)
                }
                GradientStop {
                    position: 0.07
                    color: root.secondTint
                }
                GradientStop {
                    position: 1
                    color: root.secondTint
                }
            }
        }
    }

    Item {
        id: tintMask
        anchors.fill: parent
        visible: false
        layer.enabled: root.split > 0.01

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            antialiasing: true
            color: "white"
        }
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.split > 0.01
        opacity: root.split
        source: tintSource
        maskEnabled: true
        maskSource: tintMask
    }

    Text {
        textFormat: Text.PlainText
        id: glyphA
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -3 * root.split
        x: 13.5 - width / 2 + (root.view && root.view.provider === "claude" ? -1 : 0)
        text: root.view ? (root.view.icon || "") : ""
        font.family: "Actions Island"
        font.pixelSize: (root.view && root.view.provider === "claude" ? 18 - 2 * root.split : 14 - root.split)
        font.weight: Font.ExtraBold
        renderType: Text.QtRendering
        color: root.inkFor(root.view)

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
    }

    Text {
        textFormat: Text.PlainText
        id: glyphB
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 3 * root.split
        x: root.width - 13.5 - width / 2 + (root.second && root.second.provider === "claude" ? -1 : 0)
        opacity: root.split
        text: root.second ? (root.second.icon || "") : ""
        font.family: "Actions Island"
        font.pixelSize: (root.second && root.second.provider === "claude" ? 18 - 2 * root.split : 14 - root.split)
        font.weight: Font.ExtraBold
        renderType: Text.QtRendering
        color: root.inkFor(root.second)

        Behavior on color {
            ColorAnimation {
                duration: 200
            }
        }
    }

    property bool hovered: pointer.containsMouse

    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.present
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            var far = 0.866 * (mouse.x - root.width / 2) + 0.5 * (mouse.y - root.height / 2);
            root.activated(root.split > 0.5 && far > 0 ? 1 : 0);
        }
    }
}
