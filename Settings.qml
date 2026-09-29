import QtQuick
import Quickshell.Io

Item {
    id: root

    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var palette: ({
    })
    property var settings: null
    property var missing: []
    property string pluginDir: ""
    property bool active: false

    signal flip(string key)

    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color accent: palette.accent || "#658594"
    readonly property color warn: palette.warn || "#c4b28a"

    readonly property var producers: settings && settings.producers ? settings.producers : ({})
    property var providers: []
    property var local: ({})

    readonly property var sources: [
        {
            "key": "t3",
            "label": "T3 Code"
        },
        {
            "key": "claude",
            "label": "Claude Code"
        },
        {
            "key": "codex",
            "label": "Codex"
        },
        {
            "key": "telegram",
            "label": "Telegram"
        },
        {
            "key": "github",
            "label": "GitHub"
        },
        {
            "key": "music",
            "label": "music"
        },
        {
            "key": "wifi",
            "label": "wi-fi"
        },
        {
            "key": "bluetooth",
            "label": "bluetooth"
        },
        {
            "key": "tailnet",
            "label": "probe host"
        },
        {
            "key": "ram",
            "label": "memory"
        },
        {
            "key": "charging",
            "label": "charging"
        },
        {
            "key": "battery_full",
            "label": "battery full"
        },
        {
            "key": "low",
            "label": "battery low"
        },
        {
            "key": "critical",
            "label": "battery critical"
        },
        {
            "key": "external",
            "label": "scripts"
        }
    ]

    readonly property var fields: [
        {
            "key": "remote",
            "label": "remote host",
            "hint": "ssh alias for remote agents"
        },
        {
            "key": "probe_host",
            "label": "probe host",
            "hint": "host:port to watch"
        },
        {
            "key": "font",
            "label": "font",
            "hint": "leave empty for the default"
        }
    ]

    function has(key) {
        return Object.prototype.hasOwnProperty.call(local, key);
    }

    function fieldValue(key) {
        return settings && settings[key] ? String(settings[key]) : "";
    }

    function sourceOn(key) {
        return has(key) ? local[key] : !!producers[key];
    }

    function soundOn() {
        return has("sound") ? local.sound : !!(settings && settings.sound);
    }

    function holdSeconds() {
        if (has("seconds"))
            return local.seconds;
        return settings && settings.seconds ? settings.seconds : 3;
    }

    function providerFlag(provider, kind) {
        var key = kind + ":" + provider.id;
        return has(key) ? local[key] : !!(kind === "usage" ? provider.enabled : provider.pinned);
    }

    function remember(key, value) {
        var next = ({});
        for (var k in local)
            next[k] = local[k];
        next[key] = value;
        local = next;
        settle.restart();
    }

    function refresh() {
        listing.running = false;
        listing.running = true;
    }

    function act(key) {
        if (key === "sound")
            remember(key, !soundOn());
        else if (key === "seconds") {
            var now = holdSeconds();
            remember(key, now >= 5 ? 2 : now + 0.5);
        } else if (key.indexOf("usage:") === 0 || key.indexOf("pin:") === 0) {
            var kind = key.split(":")[0];
            for (var i = 0; i < providers.length; i++)
                if (providers[i].id === key.split(":")[1])
                    remember(key, !providerFlag(providers[i], kind));
            relist.restart();
        } else if (key in producers)
            remember(key, !sourceOn(key));
        root.flip(key);
    }

    onActiveChanged: {
        if (active)
            refresh();
    }

    onSettingsChanged: {
        var next = ({});
        var changed = false;
        for (var k in local) {
            var live = k === "sound" ? !!(settings && settings.sound) : k === "seconds" ? holdSeconds() : k in producers ? !!producers[k] : null;
            if (live !== null && live === local[k])
                changed = true;
            else
                next[k] = local[k];
        }
        if (changed)
            local = next;
    }

    Component.onCompleted: refresh()

    Timer {
        id: settle

        interval: 3000
        repeat: false
        onTriggered: root.local = ({})
    }

    Timer {
        id: relist

        interval: 900
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: listing

        command: ["python3", root.pluginDir + "/usage.py", "--list"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.providers = JSON.parse(text).providers || [];
                    var next = ({});
                    for (var k in root.local)
                        if (k.indexOf("usage:") !== 0 && k.indexOf("pin:") !== 0)
                            next[k] = root.local[k];
                    root.local = next;
                } catch (e) {
                }
            }
        }
    }

    implicitWidth: 448
    implicitHeight: column.implicitHeight + 40

    component Cap: Text {
        textFormat: Text.PlainText
        font.family: root.fontFamily
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 1.6
        font.capitalization: Font.AllUppercase
        color: root.muted
    }

    component Switch: Rectangle {
        id: sw

        property bool on: false
        property bool dim: false

        width: 34
        height: 20
        radius: 10
        antialiasing: true
        opacity: dim ? 0.45 : 1
        color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.14)
        border.width: 1
        border.color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.95) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }

        Rectangle {
            y: 3
            x: sw.on ? sw.width - width - 3 : 3
            width: 14
            height: 14
            radius: 7
            antialiasing: true
            color: sw.on ? "#ffffff" : root.fgAlt

            Behavior on x {
                NumberAnimation {
                    duration: 170
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.4
                }
            }
        }
    }

    component Tile: Rectangle {
        id: tile

        property bool hot: false
        property bool lit: false

        radius: 12
        antialiasing: true
        color: lit ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.24) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, hot ? 0.09 : 0.045)
        border.width: 1
        border.color: lit ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, hot ? 0.16 : 0.08)

        Behavior on color {
            ColorAnimation {
                duration: 150
            }
        }

        Behavior on border.color {
            ColorAnimation {
                duration: 150
            }
        }
    }

    Column {
        id: column

        x: 20
        y: 18
        width: parent.width - 40
        spacing: 14

        Row {
            width: parent.width
            height: 26
            spacing: 10

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                font.family: root.fontFamily
                font.pixelSize: 17
                color: root.accent
            }

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "Settings"
                font.family: root.fontFamily
                font.pixelSize: 16
                font.weight: Font.Bold
                font.letterSpacing: 0.4
                color: root.fg
            }
        }

        Row {
            width: parent.width
            spacing: 8

            Tile {
                id: soundTile

                width: (parent.width - 8) / 2
                height: 44
                lit: root.soundOn()
                hot: soundHit.containsMouse

                Text {
                    textFormat: Text.PlainText
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Sound on critical"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    color: root.fg
                }

                Switch {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    on: root.soundOn()
                }

                MouseArea {
                    id: soundHit

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.act("sound")
                }
            }

            Tile {
                width: (parent.width - 8) / 2
                height: 44
                hot: holdHit.containsMouse

                Text {
                    textFormat: Text.PlainText
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Hold alerts"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    color: root.fg
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.holdSeconds().toFixed(1) + " s"
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: root.accent
                }

                MouseArea {
                    id: holdHit

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.act("seconds")
                }
            }
        }

        Column {
            width: parent.width
            spacing: 8

            Cap {
                x: 2
                text: "Sources"
            }

            Flow {
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.sources

                    Tile {
                        id: chip

                        required property var modelData
                        readonly property bool enabled: root.sourceOn(modelData.key)

                        width: chipLabel.implicitWidth + 40
                        height: 30
                        radius: 15
                        lit: enabled
                        hot: chipHit.containsMouse

                        Rectangle {
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: 3.5
                            antialiasing: true
                            color: chip.enabled ? root.accent : root.muted

                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                        }

                        Text {
                            id: chipLabel

                            textFormat: Text.PlainText
                            x: 26
                            anchors.verticalCenter: parent.verticalCenter
                            text: chip.modelData.label
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: chip.enabled ? root.fg : root.fgAlt
                        }

                        MouseArea {
                            id: chipHit

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.act(chip.modelData.key)
                        }
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: 8

            Item {
                width: parent.width
                height: 14

                Cap {
                    x: 2
                    text: "Limits"
                }

                Text {
                    textFormat: Text.PlainText
                    x: 62
                    text: "pin two to the bar"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    color: root.muted
                }
            }

            Grid {
                id: limits

                width: parent.width
                columns: 2
                spacing: 8

                Repeater {
                    model: root.providers

                    Tile {
                        id: prov

                        required property var modelData
                        readonly property bool enabled: root.providerFlag(modelData, "usage")
                        readonly property bool pinned: root.providerFlag(modelData, "pin")

                        width: (limits.width - 8) / 2
                        height: 40
                        lit: enabled
                        hot: provHit.containsMouse

                        Text {
                            textFormat: Text.PlainText
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 108
                            elide: Text.ElideRight
                            text: prov.modelData.name
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: prov.enabled ? root.fg : root.fgAlt
                            opacity: prov.modelData.detected ? 1 : 0.45
                        }

                        MouseArea {
                            id: provHit

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.act("usage:" + prov.modelData.id)
                        }

                        Rectangle {
                            id: pin

                            anchors.right: parent.right
                            anchors.rightMargin: 56
                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 20
                            radius: 10
                            antialiasing: true
                            visible: prov.enabled
                            color: prov.pinned ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.85) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, pinHit.containsMouse ? 0.18 : 0.09)

                            Behavior on color {
                                ColorAnimation {
                                    duration: 140
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: "pin"
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                color: prov.pinned ? "#ffffff" : root.fgAlt
                            }

                            MouseArea {
                                id: pinHit

                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.act("pin:" + prov.modelData.id)
                            }
                        }

                        Switch {
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            on: prov.enabled
                            dim: !prov.modelData.detected
                        }
                    }
                }
            }

            Text {
                visible: !root.providers.length
                textFormat: Text.PlainText
                x: 2
                text: "no providers found"
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.fgAlt
            }
        }

        Column {
            width: parent.width
            spacing: 8

            Cap {
                x: 2
                text: "Connections"
            }

            Repeater {
                model: root.fields

                Item {
                    id: field

                    required property var modelData

                    width: column.width
                    height: 34

                    Text {
                        textFormat: Text.PlainText
                        x: 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 92
                        text: field.modelData.label
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        color: root.fgAlt
                    }

                    Rectangle {
                        x: 100
                        width: parent.width - 100
                        height: 34
                        radius: 10
                        antialiasing: true
                        color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, input.activeFocus ? 0.1 : 0.05)
                        border.width: 1
                        border.color: input.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.8) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.09)

                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }
                        }

                        Behavior on border.color {
                            ColorAnimation {
                                duration: 140
                            }
                        }

                        TextInput {
                            id: input

                            x: 12
                            width: parent.width - 24
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.fieldValue(field.modelData.key)
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: root.fg
                            selectByMouse: true
                            selectionColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
                            clip: true
                            onAccepted: {
                                root.flip(field.modelData.key + "=" + text);
                                focus = false;
                            }
                            onActiveFocusChanged: {
                                if (!activeFocus && text !== root.fieldValue(field.modelData.key))
                                    root.flip(field.modelData.key + "=" + text);
                            }

                            Text {
                                textFormat: Text.PlainText
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: !input.text.length && !input.activeFocus
                                text: field.modelData.hint
                                font: input.font
                                color: root.muted
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: input.forceActiveFocus()
                        }
                    }
                }
            }
        }

        Text {
            visible: root.missing.length > 0
            width: parent.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: "missing tools: " + root.missing.join(", ")
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.warn
        }

        Row {
            id: foot

            width: parent.width
            spacing: 8

            Repeater {
                model: [
                    {
                        "key": "notifications",
                        "label": "Notification centre"
                    },
                    {
                        "key": "clear",
                        "label": "Clear tasks"
                    }
                ]

                Tile {
                    id: button

                    required property var modelData

                    width: (foot.width - 8) / 2
                    height: 36
                    hot: buttonHit.containsMouse

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: button.modelData.label
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        color: buttonHit.containsMouse ? root.fg : root.fgAlt
                    }

                    MouseArea {
                        id: buttonHit

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.act(button.modelData.key)
                    }
                }
            }
        }
    }
}
