import QtQuick
import Quickshell.Services.Pipewire

Item {
    id: root
    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var state: null
    property var palette: ({
    })
    readonly property bool present: !!state
    readonly property bool playing: !!(state && state.playing)
    readonly property string service: state && state.service ? state.service : ""
    readonly property string artPath: state && state.raw ? state.raw : (state && state.art ? state.art : "")
    readonly property real span: state && state.length ? state.length : 0
    readonly property color bg: palette.bg || "#181616"
    readonly property color bgAlt: palette.bg_alt || "#282727"
    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color youtube: "#e8453c"
    readonly property color accentTarget: {
        if (state && state.accent)
            return state.accent;

        if (!artPath && service === "youtube")
            return youtube;

        return Qt.rgba(fg.r, fg.g, fg.b, 0.55);
    }
    property color accentFrom: "#8a8a8a"
    property color accentTo: "#8a8a8a"
    property real accentMix: 1
    readonly property color accent: root.blend(accentFrom, accentTo, accentMix)

    function blend(from, to, amount) {
        if (amount <= 0)
            return from;
        if (amount >= 1)
            return to;
        var sa = from.hslSaturation;
        var sb = to.hslSaturation;
        var ha = sa < 0.06 ? to.hslHue : from.hslHue;
        var hb = sb < 0.06 ? from.hslHue : to.hslHue;
        var step = hb - ha;
        if (step > 0.5)
            step -= 1;
        else if (step < -0.5)
            step += 1;
        var hue = (ha + step * amount + 1) % 1;
        var sat = Math.max(sa + (sb - sa) * amount, Math.min(sa, sb));
        var light = from.hslLightness + (to.hslLightness - from.hslLightness) * amount;
        return Qt.hsla(hue, Math.min(1, sat), light, 1);
    }

    NumberAnimation {
        id: accentAnim

        target: root
        property: "accentMix"
        from: 0
        to: 1
        duration: 650
        easing.type: Easing.InOutCubic
    }
    readonly property real progress: span > 0 ? Math.max(0, Math.min(1, elapsed / span)) : 0
    property real elapsed: 0
    property real lastStamp: 0

    signal previous()
    signal toggle()
    signal next()
    signal art()
    signal seek(real seconds)
    signal mute()
    signal like()

    property real level: 0

    property int tick: 0
    property real centre: -8
    property real spread: 4
    property real crest: 0.4
    property real energy: 0.25
    property real lastBeat: 0
    readonly property real drive: Math.max(0, Math.min(1, level / Math.max(0.22, crest)))
    property real meter: 0

    Timer {
        interval: 1600
        running: true
        repeat: true
        onTriggered: root.tick++
    }

    function absorb(peak) {
        var value = Math.max(0.0001, Math.min(1.6, peak));
        var db = 20 * Math.log(value) / Math.LN10;
        if (db < -34) {
            level = level * 0.86;
            crest = Math.max(0.22, crest * 0.985);
            meter = meter * 0.9;
            return;
        }
        centre = centre * 0.94 + db * 0.06;
        var swing = Math.abs(db - centre);
        spread = Math.max(0.55, spread * 0.955 + swing * 0.045);
        var next = Math.max(0, Math.min(1, 0.5 + (db - centre) / (spread * 2.2)));
        level = level * 0.28 + next * 0.72;
        var now = Date.now();
        if (level > energy * 1.55 + 0.14 && now - lastBeat > 750) {
            lastBeat = now;
            tick++;
        }
        energy = energy * 0.93 + level * 0.07;
        var aim = Math.max(0, Math.min(1, level / Math.max(0.22, crest)));
        if (Math.abs(aim - meter) > 0.025)
            meter = aim > meter ? meter + (aim - meter) * 0.42 : meter + (aim - meter) * 0.09;
        crest = level > crest ? level : Math.max(0.22, crest * 0.9955);
    }

    function share() {
        return 0.34 + 0.66 * Math.random();
    }

    function step(value, span) {
        return Math.round(value / span) * span;
    }

    property int drift: 0

    Timer {
        interval: 85
        running: root.playing
        repeat: true
        onTriggered: root.drift++
    }

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    PwNodePeakMonitor {
        node: Pipewire.defaultAudioSink
        enabled: root.playing
        onPeakChanged: root.absorb(peak)
    }

    onPlayingChanged: {
        if (!playing) {
            level = 0;
            centre = -8;
            spread = 4;
            crest = 0.4;
            energy = 0.25;
            meter = 0;
        }
    }
    signal expand()

    property bool open: false
    property bool shape: false
    property bool content: false
    property alias pillItem: shell
    readonly property int panelWidth: 360
    readonly property int panelHeight: 22 + panel.implicitHeight + 22
    property int openHeight: 27

    onPanelHeightChanged: {
        if (open)
            openHeight = panelHeight;
    }

    onOpenChanged: {
        if (open) {
            fold.stop();
            settle.stop();
            folding = false;
            openHeight = panelHeight;
            shape = true;
            reveal.restart();
        } else {
            reveal.stop();
            content = false;
            folding = true;
            fold.restart();
            settle.restart();
        }
    }

    Timer {
        id: reveal

        interval: 300
        repeat: false
        onTriggered: root.content = true
    }

    property bool folding: false

    property real glass: shape ? 1 : 0

    readonly property color glassTint: Qt.rgba(bgAlt.r + (bg.r - bgAlt.r) * glass * 0.55, bgAlt.g + (bg.g - bgAlt.g) * glass * 0.55, bgAlt.b + (bg.b - bgAlt.b) * glass * 0.55, 1)

    Behavior on glass {
        NumberAnimation {
            duration: root.shape ? 320 : 360
            easing.type: Easing.InOutCubic
        }
    }

    Timer {
        id: fold

        interval: 90
        repeat: false
        onTriggered: root.shape = false
    }

    Timer {
        id: settle

        interval: 380
        repeat: false
        onTriggered: root.folding = false
    }

    Component.onCompleted: {
        accentFrom = accentTarget;
        accentTo = accentTarget;
        accentMix = 1;
    }
    onAccentTargetChanged: {
        accentFrom = accent;
        accentTo = accentTarget;
        accentMix = 0;
        accentAnim.restart();
    }
    onStateChanged: {
        var stamp = state && state.stamp ? state.stamp : 0;
        if (stamp === lastStamp)
            return ;

        lastStamp = stamp;
        elapsed = state && state.position ? state.position : 0;
        clock.base = Date.now();
    }
    implicitWidth: 249
    implicitHeight: 27
    width: present ? (shape ? panelWidth : implicitWidth) : 0
    height: shape ? openHeight : implicitHeight

    Behavior on height {
        NumberAnimation {
            duration: root.shape ? 320 : 360
            easing.type: Easing.InOutCubic
        }
    }
    clip: true

    Timer {
        id: clock

        property real base: 0

        running: root.playing && root.span > 0
        repeat: true
        interval: 500
        onTriggered: {
            var at = (root.state ? root.state.position : 0) + (Date.now() - base) / 1000;
            root.elapsed = Math.min(root.span, at);
        }
    }

    Rectangle {
        id: shell

        anchors.fill: parent
        radius: root.shape ? 26 : height / 2
        color: Qt.rgba(root.glassTint.r, root.glassTint.g, root.glassTint.b, 1 - 0.38 * root.glass)
        border.width: 1 + root.glass

        Behavior on radius {
            NumberAnimation {
                duration: 320
                easing.type: Easing.InOutCubic
            }
        }

        border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7 + 0.25 * root.glass)
        antialiasing: true
    }

    Item {
        id: body


        anchors.right: parent.right
        y: root.shape ? 22 - height / 2 : 0
        width: root.implicitWidth
        height: root.implicitHeight
        opacity: root.shape || root.folding ? 0 : 1
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        Behavior on y {
            NumberAnimation {
                duration: root.shape ? 320 : 360
                easing.type: Easing.InOutCubic
            }
        }

        Item {
            id: cover

            x: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 19
            height: 19

            Rectangle {
                anchors.fill: parent
                radius: 6
                antialiasing: true
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)
                visible: root.artPath === ""
            }

            Cover {
                id: coverImage

                anchors.fill: parent
                curve: 6
                path: root.artPath
            }

        }

        MouseArea {
            x: 5
            width: 72
            height: 23
            anchors.verticalCenter: parent.verticalCenter
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expand()
        }

        Row {
            id: bars

            x: 42
            anchors.verticalCenter: parent.verticalCenter
            height: 19
            spacing: 3.5

            Repeater {
                model: 6

                Item {
                    id: mini

                    required property int index

                    property real share: 0.6
                    property real aim: 0.6
                    readonly property real pace: 0.16 + 0.07 * ((index * 7 + 3) % 5)
                    property real raw: 17 * (0.06 + 0.94 * root.meter * mini.share)
                    property real held: 3

                    onRawChanged: {
                        var span = 2.4;
                        var k = Math.round(held / span);
                        if (raw > (k + 0.56) * span || raw < (k - 0.56) * span)
                            held = Math.max(3, Math.round(raw / span) * span);
                    }

                    width: 2
                    height: 19



                    Connections {
                        target: root

                        function onTickChanged() {
                            mini.aim = root.share();
                        }

                        function onDriftChanged() {
                            mini.share = mini.share + (mini.aim - mini.share) * mini.pace;
                            if (Math.abs(mini.aim - mini.share) < 0.04)
                                mini.aim = root.share();
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 2
                        height: mini.held
                        radius: 1
                        antialiasing: true
                        color: root.accent

                        Behavior on height {
                            NumberAnimation {
                                duration: 130
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
        }

        Row {
            id: controls

            x: 157
            anchors.verticalCenter: parent.verticalCenter
            height: 23
            spacing: 0
            opacity: root.shape ? 0 : 1
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: root.shape ? 140 : 220
                    easing.type: Easing.OutCubic
                }
            }

            Key {
                glyph: "\uf04a"
                onHit: root.previous()
            }

            Key {
                glyph: root.playing ? "\uf04c" : "\uf04b"
                size: 17
                onHit: root.toggle()
            }

            Key {
                glyph: "\uf04e"
                onHit: root.next()
            }

            component Key: Item {
                property string glyph: ""
                property real size: 16

                signal hit()

                width: 30
                height: 23

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: parent.glyph
                    font.family: root.fontFamily
                    font.pixelSize: parent.size
                    color: press.containsMouse ? root.fg : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.72)

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }

                    }

                }

                MouseArea {
                    id: press

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: parent.hit()
                }

            }

        }

        Item {
            id: track

            x: 80
            width: 70
            height: 27
            opacity: root.shape ? 0 : 1
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: root.shape ? 140 : 220
                    easing.type: Easing.OutCubic
                }
            }
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: rail

                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 3
                radius: 1.5
                antialiasing: true
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16)

                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height
                    radius: parent.radius
                    antialiasing: true
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, scrub.containsMouse || scrub.pressed ? 0.78 : 0.5)

                    Behavior on width {
                        NumberAnimation {
                            duration: scrub.pressed ? 0 : 400
                            easing.type: Easing.OutCubic
                        }

                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: 150
                        }

                    }

                }

            }

            Rectangle {
                id: handle

                anchors.verticalCenter: parent.verticalCenter
                x: rail.width * root.progress - width / 2
                width: scrub.containsMouse || scrub.pressed ? 9 : 7
                height: width
                radius: width / 2
                antialiasing: true
                color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, scrub.containsMouse || scrub.pressed ? 1 : 0.8)

                Behavior on width {
                    NumberAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }

                }

                Behavior on x {
                    NumberAnimation {
                        duration: scrub.pressed ? 0 : 400
                        easing.type: Easing.OutCubic
                    }

                }

            }

            MouseArea {
                id: scrub

                enabled: root.span > 0
                anchors.fill: parent
                anchors.margins: -5
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPressed: (mouse) => {
                    return root.seek(root.span * Math.max(0, Math.min(1, (mouse.x - 5) / rail.width)));
                }
                onPositionChanged: (mouse) => {
                    if (pressed)
                        root.seek(root.span * Math.max(0, Math.min(1, (mouse.x - 5) / rail.width)));

                }
            }

        }

    }


    MusicPanel {
        id: panel

        anchors.right: parent.right
        anchors.rightMargin: 24
        y: 22
        width: root.panelWidth - 48
        opacity: root.content ? 1 : 0
        visible: opacity > 0.01
        state: root.state
        palette: root.palette
        accent: root.accent
        elapsed: root.elapsed
        level: root.meter
        drift: root.drift
        tick: root.tick
        span: root.span
        onPrevious: root.previous()
        onToggle: root.toggle()
        onNext: root.next()
        onMute: root.mute()
        onLike: root.like()
        onReveal: root.art()
        onFold: root.expand()
        onSeek: seconds => root.seek(seconds)

        Behavior on opacity {
            NumberAnimation {
                duration: root.content ? 200 : 90
                easing.type: Easing.OutCubic
            }
        }
    }

    Behavior on width {
        NumberAnimation {
            duration: 340
            easing.type: Easing.InOutCubic
        }

    }

}
