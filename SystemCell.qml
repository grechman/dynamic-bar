import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: cell
    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var palette: ({
    })
    property bool open: false

    signal toggled

    property alias pillItem: pill

    readonly property color bg: palette.bg || "#181616"
    readonly property color bgAlt: palette.bg_alt || "#282727"
    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color accent: palette.accent || "#658594"
    readonly property color ok: palette.ok || "#87a987"
    readonly property color warn: palette.warn || "#c4b28a"
    readonly property color crit: palette.crit || "#c4746e"

    readonly property int panelWidth: 424
    readonly property int panelHeight: 46 + panel.implicitHeight + 20
    readonly property int collapsedWidth: 265
    readonly property bool moving: pill.height > 30
    property int openHeight: 29



    onPanelHeightChanged: {
        if (open)
            openHeight = panelHeight;
    }
    property bool shape: false
    property bool content: false

    implicitWidth: shape ? panelWidth : collapsedWidth
    implicitHeight: shape ? openHeight : 29

    function mix(base, tint, amount) {
        return Qt.rgba(base.r + (tint.r - base.r) * amount, base.g + (tint.g - base.g) * amount, base.b + (tint.b - base.b) * amount, 1);
    }

    property real glass: shape ? 1 : 0
    readonly property color glassTint: mix(bgAlt, bg, glass * 0.55)

    Behavior on glass {
        NumberAnimation {
            duration: cell.shape ? 320 : 360
            easing.type: Easing.InOutCubic
        }
    }

    onOpenChanged: {
        if (open) {
            fold.stop();
            openHeight = panelHeight;
            shape = true;
            reveal.restart();
        } else {
            reveal.stop();
            content = false;
            fold.restart();
        }
    }

    Timer {
        id: reveal

        interval: 300
        repeat: false
        onTriggered: cell.content = true
    }

    Timer {
        id: fold

        interval: 90
        repeat: false
        onTriggered: cell.shape = false
    }

    property var sys: null
    property string pluginDir: ""
    property int catFrame: 0

    readonly property string cpuLine: sys && sys.cpu_tip ? sys.cpu_tip.split("\n")[0] : ""
    readonly property string ramLine: sys && sys.ram_tip ? sys.ram_tip.split("\n")[0] : ""
    readonly property int catMs: sys && sys.cat_ms ? sys.cat_ms : 0
    readonly property real ramLevel: sys && sys.ram !== undefined ? sys.ram / 100 : 0
    readonly property color ramTint: ramLevel < 0.7 ? ok : ramLevel <= 0.9 ? warn : crit
    readonly property string catSource: {
        if (!sys || !sys.cat_dir)
            return "";
        return "file://" + sys.cat_dir + (catMs > 0 ? "/cat-" + catFrame + ".svg" : "/cat-idle.svg");
    }

    Timer {
        interval: Math.max(40, cell.catMs)
        running: cell.catMs > 0
        repeat: true
        onTriggered: cell.catFrame = (cell.catFrame + 1) % 5
    }

    property string layout: ""

    Process {
        id: layoutProbe

        command: ["hyprctl", "devices", "-j"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var boards = JSON.parse(text).keyboards || [];
                    for (var i = 0; i < boards.length; i++)
                        if (boards[i].main)
                            cell.layout = cell.shortLayout(boards[i].active_keymap);
                } catch (e) {}
            }
        }
    }

    function shortLayout(name) {
        var raw = name || "";
        if (raw.indexOf("Russian") >= 0)
            return "RU";
        if (raw.indexOf("English") >= 0)
            return "EN";
        return raw.substring(0, 2).toUpperCase();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name !== "activelayout")
                return;
            var parts = event.data.split(",");
            cell.layout = cell.shortLayout(parts.length > 1 ? parts.slice(1).join(",") : "");
        }
    }

    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    readonly property var sinkAudio: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Pipewire.defaultAudioSink.audio : null
    readonly property real volume: sinkAudio ? sinkAudio.volume : 0
    readonly property bool volumeMuted: sinkAudio ? sinkAudio.muted : false

    readonly property var wifiDevice: {
        var devs = Networking.devices ? Networking.devices.values : [];
        for (var i = 0; i < devs.length; i++)
            if (devs[i].type === DeviceType.Wifi)
                return devs[i];
        return null;
    }

    readonly property var liveNetwork: {
        if (!wifiDevice || !wifiDevice.networks)
            return null;
        var nets = wifiDevice.networks.values;
        for (var i = 0; i < nets.length; i++)
            if (nets[i].connected)
                return nets[i];
        return null;
    }

    Binding {
        target: cell.wifiDevice
        property: "scannerEnabled"
        value: cell.open
        when: !!cell.wifiDevice
        restoreMode: Binding.RestoreBindingOrValue
    }

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btLinked: {
        if (!adapter || !adapter.devices)
            return false;
        var devs = adapter.devices.values;
        for (var i = 0; i < devs.length; i++)
            if (devs[i].connected)
                return true;
        return false;
    }

    readonly property var batteryDevice: UPower.displayDevice
    readonly property real batteryLevel: batteryDevice && batteryDevice.isPresent ? batteryDevice.percentage : 0
    readonly property bool charging: batteryDevice ? (batteryDevice.state === UPowerDeviceState.Charging || (!UPower.onBattery && batteryDevice.state === UPowerDeviceState.FullyCharged)) : false
    readonly property color batteryTint: charging ? ok : batteryLevel <= 0.15 ? crit : batteryLevel <= 0.3 ? warn : ok

    Rectangle {
        id: pill

        anchors.right: parent.right
        y: 0
        height: cell.shape ? cell.openHeight : 29
        width: cell.shape ? cell.panelWidth : cell.collapsedWidth
        radius: cell.shape ? 26 : height / 2
        antialiasing: true
        color: Qt.rgba(cell.glassTint.r, cell.glassTint.g, cell.glassTint.b, 1 - 0.38 * cell.glass)
        border.width: 1 + cell.glass
        border.color: Qt.rgba(cell.fg.r, cell.fg.g, cell.fg.b, 0.20 + 0.10 * cell.glass)

        Behavior on height {
            NumberAnimation {
                duration: cell.shape ? 320 : 360
                easing.type: Easing.InOutCubic
            }
        }

        Behavior on width {
            NumberAnimation {
                duration: cell.shape ? 320 : 360
                easing.type: Easing.InOutCubic
            }
        }

        Behavior on radius {
            NumberAnimation {
                duration: 320
                easing.type: Easing.InOutCubic
            }
        }

        Item {
            id: glyphs

            readonly property int slots: 7
            readonly property int cellSize: 26
            readonly property var packed: [0, 36, 68, 99, 134, 170, 208]
            readonly property int packedWidth: 229

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            y: cell.shape ? 23 - height / 2 : (29 - height) / 2
            height: 26

            function slotX(index) {
                var near = packedWidth - packed[index] - cellSize;
                var far = width * (1 - (index + 0.5) / slots) - cellSize / 2;
                return width - cellSize - (near + (far - near) * cell.glass);
            }

            Behavior on y {
                NumberAnimation {
                    duration: cell.shape ? 320 : 360
                    easing.type: Easing.InOutCubic
                }
            }

            Image {
                x: glyphs.slotX(0)
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                sourceSize.width: 52
                sourceSize.height: 52
                smooth: true
                source: cell.catSource
            }

            Item {
                x: glyphs.slotX(1)
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26

                Text {
                    textFormat: Text.PlainText
                    id: ramGlyph

                    anchors.centerIn: parent
                    text: "\udb81\udfc6"
                    font.family: cell.fontFamily
                    font.pixelSize: 23
                    color: cell.muted
                }

                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    height: Math.round(18 * cell.ramLevel)
                    clip: true

                    Text {
                        textFormat: Text.PlainText
                        x: ramGlyph.x
                        y: ramGlyph.y - (parent.parent.height - parent.height - 4)
                        text: ramGlyph.text
                        font: ramGlyph.font
                        color: cell.ramTint
                    }

                    Behavior on height {
                        NumberAnimation {
                            duration: 400
                            easing.type: Easing.InOutCubic
                        }
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                x: glyphs.slotX(2)
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                horizontalAlignment: Text.AlignHCenter
                text: cell.volumeMuted ? "󰖁" : cell.volume < 0.01 ? "󰕿" : cell.volume < 0.5 ? "󰖀" : "󰕾"
                font.family: cell.fontFamily
                font.pixelSize: 19
                color: cell.volumeMuted ? cell.muted : cell.fgAlt
            }

            Text {
                textFormat: Text.PlainText
                x: glyphs.slotX(3)
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                horizontalAlignment: Text.AlignHCenter
                text: {
                    if (!Networking.wifiEnabled)
                        return "󰤭";
                    if (!cell.liveNetwork)
                        return "󰤯";
                    var level = cell.liveNetwork.signalStrength;
                    if (level >= 0.75)
                        return "󰤨";
                    if (level >= 0.55)
                        return "󰤥";
                    if (level >= 0.35)
                        return "󰤢";
                    return "󰤟";
                }
                font.family: cell.fontFamily
                font.pixelSize: 19
                color: cell.liveNetwork ? cell.fgAlt : cell.muted
            }

            Text {
                textFormat: Text.PlainText
                x: glyphs.slotX(4)
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                horizontalAlignment: Text.AlignHCenter
                text: !cell.adapter || !cell.adapter.enabled ? "󰂲" : cell.btLinked ? "󰂱" : "󰂯"
                font.family: cell.fontFamily
                font.pixelSize: 19
                color: cell.btLinked ? cell.accent : !cell.adapter || !cell.adapter.enabled ? cell.muted : cell.fgAlt
            }

            Item {
                x: glyphs.slotX(5)
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -0.5
                width: 26
                height: 26

                BatteryIcon {
                    anchors.centerIn: parent
                    unit: 1
                    level: cell.batteryLevel
                    charging: cell.charging
                    shell: cell.fgAlt
                    hollow: cell.bgAlt
                    tint: cell.batteryTint
                }
            }

            Text {
                textFormat: Text.PlainText
                x: glyphs.slotX(6)
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 0.5
                width: 26
                horizontalAlignment: Text.AlignHCenter
                text: cell.layout
                font.family: cell.fontFamily
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: cell.fgAlt
            }
        }

        SysPanel {
            id: panel

            anchors.right: parent.right
            anchors.rightMargin: 24
            y: 46
            width: cell.panelWidth - 48
            opacity: cell.content ? 1 : 0
            visible: opacity > 0.01
            palette: cell.palette
            active: cell.open || cell.shape || cell.moving
            cpuLine: cell.cpuLine
            ramLine: cell.ramLine

            Behavior on opacity {
                NumberAnimation {
                    duration: cell.content ? 200 : 90
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            anchors.right: parent.right
            anchors.top: parent.top
            width: cell.shape ? cell.panelWidth : cell.collapsedWidth
            height: cell.shape ? 46 : 29
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onWheel: wheel => {
                if (!cell.sinkAudio)
                    return;
                cell.sinkAudio.muted = false;
                cell.sinkAudio.volume = Math.max(0, Math.min(1, cell.sinkAudio.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)));
            }
            onClicked: cell.toggled()
        }
    }
}
