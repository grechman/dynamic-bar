import QtQuick

Item {
    id: root
    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var state: null
    property var palette: ({
    })
    property color accent: "#8a8a8a"
    property real elapsed: 0
    property real span: 0
    property real level: 0
    property int drift: 0
    property int tick: 0

    signal previous
    signal toggle
    signal next
    signal mute
    signal like
    signal reveal
    signal fold
    signal seek(real seconds)

    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color crit: palette.crit || "#c4746e"
    readonly property bool playing: !!(state && state.playing)
    property int wish: -1
    readonly property bool liked: wish >= 0 ? wish === 1 : !!(state && state.liked)

    onStateChanged: {
        if (wish >= 0 && !!(state && state.liked) === (wish === 1))
            wish = -1;
    }

    Timer {
        id: wishHold

        interval: 7000
        repeat: false
        onTriggered: root.wish = -1
    }
    readonly property bool hushed: !!(state && state.muted)
    readonly property bool timed: span > 0
    readonly property string artPath: state && state.cover ? state.cover : ""
    readonly property string roughPath: state && state.raw ? state.raw : (state && state.art ? state.art : "")


    readonly property string source: {
        var name = state && state.service ? state.service : "";
        if (name === "yandex")
            return "Yandex Music";
        if (name === "youtube")
            return "YouTube";
        if (name === "spotify")
            return "Spotify";
        if (name === "apple")
            return "Apple Music";
        if (name === "deezer")
            return "Deezer";
        if (name === "tidal")
            return "TIDAL";
        if (name === "soundcloud")
            return "SoundCloud";
        if (name === "bandcamp")
            return "Bandcamp";
        if (state && state.album)
            return state.album;
        return "now playing";
    }

    implicitWidth: 312
    implicitHeight: 206



    function clock(seconds) {
        if (!seconds || seconds < 0)
            return "0:00";
        var total = Math.floor(seconds);
        var mins = Math.floor(total / 60);
        var rest = total % 60;
        return mins + ":" + (rest < 10 ? "0" + rest : rest);
    }

    Rectangle {
        id: cover

        width: 104
        height: 104
        radius: 27
        antialiasing: true
        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07)

        Cover {
            id: rough

            anchors.fill: parent
            curve: parent.radius
            haze: 1
            path: root.roughPath
            opacity: root.artPath === "" && root.roughPath !== "" ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
        }

        Cover {
            id: sharp

            anchors.fill: parent
            curve: parent.radius
            path: root.artPath
            opacity: ready ? 1 : 0
            scale: ready ? 1 : 1.06

            Behavior on opacity {
                NumberAnimation {
                    duration: 420
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on scale {
                NumberAnimation {
                    duration: 520
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.fold()
        }
    }

    Item {
        id: column

        x: 120
        width: parent.width - 120
        height: 104

        Text {
            y: 6
            width: parent.width
            elide: Text.ElideRight
            text: root.source
            font.family: root.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 1
            color: root.muted
        }

        Text {
            y: 24
            width: parent.width
            elide: Text.ElideRight
            text: root.state && root.state.title ? root.state.title : "nothing playing"
            font.family: root.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: root.fg
        }

        Text {
            y: 46
            width: parent.width
            elide: Text.ElideRight
            text: root.state && root.state.artist ? root.state.artist : ""
            font.family: root.fontFamily
            font.pixelSize: 13
            color: root.fgAlt
        }

        Row {
            id: bars

            y: 74
            width: parent.width
            height: 26
            spacing: (parent.width - 26 * 2) / 25
            Repeater {
                model: 26

                Item {
                    id: slot

                    required property int index

                    property real share: 0.6
                    property real aim: 0.6
                    readonly property real pace: 0.15 + 0.065 * ((index * 11 + 5) % 6)
                    property real raw: 26 * (0.06 + 0.94 * root.level * slot.share)
                    property real held: 4

                    onRawChanged: {
                        var span = 3;
                        var k = Math.round(held / span);
                        if (raw > (k + 0.56) * span || raw < (k - 0.56) * span)
                            held = Math.max(4, Math.round(raw / span) * span);
                    }

                    width: 2
                    height: 26



                    Connections {
                        target: root

                        function onTickChanged() {
                            slot.aim = 0.34 + 0.66 * Math.random();
                        }

                        function onDriftChanged() {
                            slot.share = slot.share + (slot.aim - slot.share) * slot.pace;
                            if (Math.abs(slot.aim - slot.share) < 0.04)
                                slot.aim = 0.34 + 0.66 * Math.random();
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 2
                        height: slot.held
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
    }

    Item {
        id: track

        y: 122
        width: parent.width
        height: 20
        opacity: root.timed ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: 200
            }
        }

        Rectangle {
            id: rail

            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            antialiasing: true
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)

            Rectangle {
                width: parent.width * (root.timed ? Math.max(0, Math.min(1, root.elapsed / root.span)) : 0)
                height: parent.height
                radius: parent.radius
                antialiasing: true
                color: root.accent

                Behavior on width {
                    NumberAnimation {
                        duration: scrub.pressed ? 0 : 400
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: rail.width * (root.timed ? Math.max(0, Math.min(1, root.elapsed / root.span)) : 0) - width / 2
            width: scrub.containsMouse || scrub.pressed ? 14 : 11
            height: width
            radius: width / 2
            antialiasing: true
            color: root.fg

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

            enabled: root.timed
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: mouse => root.seek(root.span * Math.max(0, Math.min(1, (mouse.x - 6) / rail.width)))
            onPositionChanged: mouse => {
                if (pressed)
                    root.seek(root.span * Math.max(0, Math.min(1, (mouse.x - 6) / rail.width)));
            }
        }
    }

    Text {
        y: 144
        text: root.clock(root.elapsed)
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.muted
        opacity: track.opacity
    }

    Text {
        anchors.right: parent.right
        y: 144
        text: "-" + root.clock(root.span - root.elapsed)
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.muted
        opacity: track.opacity
    }

    component Knob: Item {
        id: knob

        property string glyph: ""
        property int weight: 18
        property color ink: root.fg

        signal hit

        width: 40
        height: 40

        Rectangle {
            anchors.fill: parent
            radius: 20
            antialiasing: true
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, press.containsMouse ? 0.12 : 0)

            Behavior on color {
                ColorAnimation {
                    duration: 140
                }
            }
        }

        Text {
            anchors.centerIn: parent
            text: knob.glyph
            font.family: root.fontFamily
            font.pixelSize: knob.weight
            color: knob.ink

            Behavior on color {
                ColorAnimation {
                    duration: 160
                }
            }
        }

        MouseArea {
            id: press

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: knob.hit()
        }
    }

    Knob {
        anchors.left: parent.left
        y: 162
        glyph: root.liked ? "󰋑" : "󰋕"
        weight: 19
        ink: root.liked ? root.crit : Qt.rgba(root.fgAlt.r, root.fgAlt.g, root.fgAlt.b, 0.6)
        onHit: {
            root.wish = root.liked ? 0 : 1;
            wishHold.restart();
            root.like();
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 162
        spacing: 22

        Knob {
            glyph: "\uf04a"
            onHit: root.previous()
        }

        Knob {
            glyph: root.playing ? "\uf04c" : "\uf04b"
            weight: 24
            onHit: root.toggle()
        }

        Knob {
            glyph: "\uf04e"
            onHit: root.next()
        }
    }

    Knob {
        anchors.right: parent.right
        y: 162
        glyph: root.hushed ? "󰖁" : "󰕾"
        weight: 19
        ink: root.hushed ? root.crit : Qt.rgba(root.fgAlt.r, root.fgAlt.g, root.fgAlt.b, 0.6)
        onHit: root.mute()
    }
}
