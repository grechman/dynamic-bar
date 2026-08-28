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

    signal flip(string key)

    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color accent: palette.accent || "#658594"
    readonly property color warn: palette.warn || "#c4b28a"

    readonly property var producers: settings && settings.producers ? settings.producers : ({})
    readonly property real seconds: settings && settings.seconds ? settings.seconds : 3
    readonly property bool sound: !!(settings && settings.sound)
    property var providers: []

    readonly property var rows: [
        {
            "key": "t3",
            "label": "T3 Code"
        },
        {
            "key": "wifi",
            "label": "wi-fi"
        },
        {
            "key": "claude",
            "label": "Claude Code"
        },
        {
            "key": "tailnet",
            "label": "probe host"
        },
        {
            "key": "telegram",
            "label": "Telegram"
        },
        {
            "key": "bluetooth",
            "label": "bluetooth"
        },
        {
            "key": "github",
            "label": "GitHub"
        },
        {
            "key": "charging",
            "label": "charging"
        },
        {
            "key": "music",
            "label": "music"
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
            "key": "ram",
            "label": "memory"
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

    function fieldValue(key) {
        return settings && settings[key] ? String(settings[key]) : "";
    }

    function refresh() {
        listing.running = false;
        listing.running = true;
    }

    function act(key) {
        root.flip(key);
        if (key.indexOf("usage:") === 0 || key.indexOf("pin:") === 0)
            relist.restart();
    }

    Component.onCompleted: refresh()

    Timer {
        id: relist

        interval: 400
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
                } catch (e) {
                }
            }
        }
    }

    implicitWidth: 384
    implicitHeight: column.implicitHeight

    component Label: Text {
        font.family: root.fontFamily
        font.pixelSize: 12
        font.letterSpacing: 1.1
        color: root.fgAlt
    }

    Column {
        id: column

        width: parent.width
        spacing: 0

        Item {
            id: head

            width: parent.width
            height: 36

            Toggle {
                width: parent.width / 2
                palette: root.palette
                label: "sound on critical"
                on: root.sound
                onFlipped: root.act("sound")
            }

            Item {
                x: parent.width / 2
                width: parent.width / 2
                height: 32
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: 6
                    radius: 9
                    antialiasing: true
                    color: spanHit.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 130
                        }
                    }
                }

                Text {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "hold alerts"
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    color: root.fg
                }

                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.seconds.toFixed(1) + " s"
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: root.accent
                }

                MouseArea {
                    id: spanHit

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.act("seconds")
                }
            }
        }

        Grid {
            id: grid

            width: parent.width
            columns: 2
            rowSpacing: 0
            columnSpacing: 0

            Repeater {
                model: root.rows

                Toggle {
                    required property var modelData

                    width: grid.width / 2
                    palette: root.palette
                    label: modelData.label
                    on: !!root.producers[modelData.key]
                    onFlipped: root.act(modelData.key)
                }
            }
        }

        Item {
            width: parent.width
            height: 30

            Label {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "limits"
            }

            Text {
                x: 70
                anchors.verticalCenter: parent.verticalCenter
                text: "pin two to the bar, dim ones have no login"
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.fgAlt
            }
        }

        Grid {
            id: limits

            width: parent.width
            columns: 2
            rowSpacing: 0
            columnSpacing: 0

            Repeater {
                model: root.providers

                Item {
                    id: prov

                    required property var modelData

                    width: limits.width / 2
                    height: 30

                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin: 6
                        radius: 9
                        antialiasing: true
                        color: provHit.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06) : "transparent"
                    }

                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 96
                        elide: Text.ElideRight
                        text: prov.modelData.name
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        color: prov.modelData.enabled ? root.fg : root.fgAlt
                        opacity: prov.modelData.detected ? 1 : 0.45
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 50
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 18
                        radius: 6
                        antialiasing: true
                        visible: prov.modelData.enabled
                        color: prov.modelData.pinned ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, pinHit.containsMouse ? 0.16 : 0.08)

                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "pin"
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            color: prov.modelData.pinned ? root.fg : root.fgAlt
                        }

                        MouseArea {
                            id: pinHit

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.act("pin:" + prov.modelData.id)
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
                        color: prov.modelData.enabled ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.55) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

                        Behavior on color {
                            ColorAnimation {
                                duration: 180
                            }
                        }

                        Rectangle {
                            y: 3
                            x: prov.modelData.enabled ? track.width - width - 3 : 3
                            width: 10
                            height: 10
                            radius: 5
                            antialiasing: true
                            color: prov.modelData.enabled ? root.fg : root.muted

                            Behavior on x {
                                NumberAnimation {
                                    duration: 180
                                    easing.type: Easing.OutCubic
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: provHit

                        anchors.fill: parent
                        anchors.rightMargin: 84
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.act("usage:" + prov.modelData.id)
                    }

                    MouseArea {
                        anchors.fill: track
                        anchors.margins: -5
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.act("usage:" + prov.modelData.id)
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: root.providers.length ? 0 : 26
            visible: height > 0

            Text {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "no providers found"
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.fgAlt
            }
        }

        Repeater {
            model: root.fields

            Item {
                id: field

                required property var modelData

                width: column.width
                height: 31

                Text {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 104
                    text: field.modelData.label
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    color: root.fg
                }

                Rectangle {
                    x: 118
                    width: parent.width - 118 - 10
                    height: 26
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 8
                    antialiasing: true
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, input.activeFocus ? 0.12 : 0.07)
                    border.width: 1
                    border.color: input.activeFocus ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.7) : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 140
                        }
                    }

                    TextInput {
                        id: input

                        x: 9
                        width: parent.width - 18
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
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            visible: !input.text.length && !input.activeFocus
                            text: field.modelData.hint
                            font: input.font
                            color: root.fgAlt
                            opacity: 0.7
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

        Item {
            width: parent.width
            height: root.missing.length ? 22 : 0
            visible: height > 0

            Text {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 20
                elide: Text.ElideRight
                text: "missing tools: " + root.missing.join(", ")
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.warn
            }
        }

        Item {
            width: parent.width
            height: 10
        }

        Row {
            id: foot

            width: parent.width
            height: 30
            spacing: 10

            Repeater {
                model: [
                    {
                        "key": "notifications",
                        "label": "notification centre"
                    },
                    {
                        "key": "clear",
                        "label": "clear tasks"
                    }
                ]

                Rectangle {
                    required property var modelData

                    width: (foot.width - 10) / 2 - 3
                    height: 30
                    radius: 10
                    antialiasing: true
                    color: press.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.05)

                    Behavior on color {
                        ColorAnimation {
                            duration: 130
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData.label
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        color: root.fgAlt
                    }

                    MouseArea {
                        id: press

                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.act(parent.modelData.key)
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 6
        }
    }
}
