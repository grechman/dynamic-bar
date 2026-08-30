import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Item {
    id: root
    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var palette: ({
    })
    property bool active: false
    property string cpuLine: ""
    property string ramLine: ""

    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color accent: palette.accent || "#658594"
    readonly property color ok: palette.ok || "#87a987"
    readonly property color warn: palette.warn || "#c4b28a"
    readonly property color crit: palette.crit || "#c4746e"

    property string asking: ""
    property string askError: ""

    implicitWidth: 376
    implicitHeight: column.implicitHeight

    onActiveChanged: {
        if (!active) {
            asking = "";
            askError = "";
        }
    }

    readonly property var wifi: {
        var devs = Networking.devices ? Networking.devices.values : [];
        for (var i = 0; i < devs.length; i++)
            if (devs[i].type === DeviceType.Wifi)
                return devs[i];
        return null;
    }

    readonly property var adapter: Bluetooth.defaultAdapter

    readonly property var networks: {
        if (!wifi || !wifi.networks)
            return [];
        var raw = wifi.networks.values.slice();
        var seen = ({});
        var out = [];
        for (var i = 0; i < raw.length; i++) {
            var n = raw[i];
            if (!n.name || seen[n.name])
                continue;
            seen[n.name] = true;
            out.push(n);
        }
        out.sort(function (a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            if (a.known !== b.known)
                return a.known ? -1 : 1;
            return b.signalStrength - a.signalStrength;
        });
        return out;
    }

    readonly property bool btBusy: {
        for (var i = 0; i < btDevices.length; i++) {
            var d = btDevices[i];
            if (d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting)
                return true;
        }
        return false;
    }

    readonly property string btDetail: {
        if (!adapter)
            return "no adapter";
        if (adapter.state === BluetoothAdapterState.Enabling)
            return "turning on";
        if (adapter.state === BluetoothAdapterState.Disabling)
            return "turning off";
        if (adapter.state === BluetoothAdapterState.Blocked)
            return "blocked by rfkill";
        if (!adapter.enabled)
            return "off";
        for (var i = 0; i < btDevices.length; i++) {
            var d = btDevices[i];
            if (d.pairing)
                return "pairing " + (d.name || d.address);
            if (d.state === BluetoothDeviceState.Connecting)
                return "connecting " + (d.name || d.address);
            if (d.state === BluetoothDeviceState.Disconnecting)
                return "disconnecting";
        }
        for (var j = 0; j < btDevices.length; j++)
            if (btDevices[j].connected)
                return btDevices[j].name || btDevices[j].address;
        if (adapter.discovering)
            return "looking for devices";
        return "not connected";
    }

    function btStatus(device) {
        if (device.pairing)
            return "pairing";
        if (device.state === BluetoothDeviceState.Connecting)
            return "connecting";
        if (device.state === BluetoothDeviceState.Disconnecting)
            return "disconnecting";
        if (device.connected && device.batteryAvailable)
            return Math.round(device.battery * 100) + "%";
        if (device.connected)
            return "connected";
        var kind = btKind(device.icon, device.name);
        if (device.paired)
            return kind;
        return kind.length ? kind + " · new" : "new";
    }

    readonly property var btDevices: {
        if (!adapter || !adapter.devices)
            return [];
        var raw = adapter.devices.values.slice();
        raw.sort(function (a, b) {
            if (a.connected !== b.connected)
                return a.connected ? -1 : 1;
            if (a.paired !== b.paired)
                return a.paired ? -1 : 1;
            return (a.name || "").localeCompare(b.name || "");
        });
        return raw;
    }

    function open(security) {
        return security === WifiSecurityType.Open || security === WifiSecurityType.Owe;
    }

    function enterprise(security) {
        return security === WifiSecurityType.Wpa2Eap || security === WifiSecurityType.WpaEap || security === WifiSecurityType.DynamicWep || security === WifiSecurityType.Leap;
    }

    function signalGlyph(level) {
        if (level >= 0.75)
            return "󰤨";
        if (level >= 0.55)
            return "󰤥";
        if (level >= 0.35)
            return "󰤢";
        if (level > 0)
            return "󰤟";
        return "󰤯";
    }

    function tapNetwork(net) {
        askError = "";
        if (net.connected) {
            net.requestDisconnect();
            return;
        }
        if (net.known || open(net.security)) {
            asking = "";
            net.requestConnect();
            return;
        }
        if (enterprise(net.security)) {
            askError = "enterprise Wi-Fi needs nmcli";
            return;
        }
        asking = asking === net.name ? "" : net.name;
    }

    Column {
        id: column

        width: parent.width
        spacing: 0

        Item {
            width: parent.width
            height: 42

            BatteryIcon {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                unit: 1.3
                level: root.batteryLevel
                charging: root.charging
                shell: root.fgAlt
                hollow: root.palette.bg_alt || "#282727"
                tint: root.batteryTint
            }

            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: 44
                anchors.verticalCenter: parent.verticalCenter
                text: root.batteryText
                font.family: root.fontFamily
                font.pixelSize: 14
                color: root.fgAlt
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                visible: PowerProfiles.hasPerformanceProfile

                Repeater {
                    model: [
                        {
                            "id": PowerProfile.PowerSaver,
                            "icon": "󰌪"
                        },
                        {
                            "id": PowerProfile.Balanced,
                            "icon": "󰓅"
                        },
                        {
                            "id": PowerProfile.Performance,
                            "icon": "󱓞"
                        }
                    ]

                    Rectangle {
                        required property var modelData

                        readonly property bool on: PowerProfiles.profile === modelData.id
                        width: 32
                        height: 24
                        radius: 8
                        antialiasing: true
                        color: on ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, chipHit.containsMouse ? 0.12 : 0.05)

                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: parent.modelData.icon
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            color: parent.on ? root.fg : root.muted
                        }

                        MouseArea {
                            id: chipHit

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: PowerProfiles.profile = parent.modelData.id
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 26

            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                elide: Text.ElideRight
                text: root.loadLine
                font.family: root.fontFamily
                font.pixelSize: 13
                color: root.fgAlt
            }
        }

        Item {
            width: parent.width
            height: 46

            PwObjectTracker {
                objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
            }

            readonly property var sink: Pipewire.defaultAudioSink
            readonly property var audio: sink && sink.audio ? sink.audio : null
            readonly property real level: audio ? audio.volume : 0
            readonly property bool muted: audio ? audio.muted : false

            Text {
                textFormat: Text.PlainText
                id: volIcon

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: parent.muted ? "󰖁" : parent.level < 0.01 ? "󰕿" : parent.level < 0.5 ? "󰖀" : "󰕾"
                font.family: root.fontFamily
                font.pixelSize: 18
                color: parent.muted ? root.muted : root.fgAlt

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -5
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (volIcon.parent.audio)
                            volIcon.parent.audio.muted = !volIcon.parent.audio.muted;
                    }
                }
            }

            Item {
                id: volTrack

                x: 36
                width: parent.width - 36 - 52
                height: parent.height
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    antialiasing: true
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.16)

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, volTrack.parent.level))
                        height: parent.height
                        radius: parent.radius
                        antialiasing: true
                        color: volTrack.parent.muted ? root.muted : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, volSlide.containsMouse || volSlide.pressed ? 0.78 : 0.5)

                        Behavior on color {
                            ColorAnimation {
                                duration: 150
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: volTrack.width * Math.max(0, Math.min(1, volTrack.parent.level)) - width / 2
                    width: volSlide.containsMouse || volSlide.pressed ? 12 : 9
                    height: width
                    radius: width / 2
                    antialiasing: true
                    color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, volSlide.containsMouse || volSlide.pressed ? 1 : 0.8)

                    Behavior on width {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                MouseArea {
                    id: volSlide

                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => volTrack.apply(mouse.x)
                    onPositionChanged: mouse => {
                        if (pressed)
                            volTrack.apply(mouse.x);
                    }
                    onWheel: wheel => {
                        var a = volTrack.parent.audio;
                        if (!a)
                            return;
                        a.volume = Math.max(0, Math.min(1, a.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)));
                    }
                }

                function apply(px) {
                    var a = parent.audio;
                    if (!a)
                        return;
                    a.muted = false;
                    a.volume = Math.max(0, Math.min(1, (px - 4) / volTrack.width));
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(parent.level * 100) + "%"
                font.family: root.fontFamily
                font.pixelSize: 13
                color: root.fgAlt
            }
        }

        SysSection {
            width: parent.width
            palette: root.palette
            label: "wi-fi"
            detail: {
                if (!Networking.wifiEnabled)
                    return "off";
                for (var i = 0; i < root.networks.length; i++)
                    if (root.networks[i].connected)
                        return root.networks[i].name;
                return "not connected";
            }
            busy: root.wifi ? root.wifi.scannerEnabled && root.networks.length === 0 : false
            toggled: Networking.wifiEnabled
            onFlipped: Networking.wifiEnabled = !Networking.wifiEnabled
        }

        Flickable {
            id: wifiBox

            readonly property bool expanded: Networking.wifiEnabled

            width: parent.width
            height: expanded ? 216 : 0
            contentHeight: wifiList.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: height > 0

            Behavior on height {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.InOutCubic
                }
            }

            Column {
                id: wifiList

                width: parent.width
                opacity: wifiBox.expanded ? 1 : 0

                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation {
                            duration: wifiBox.expanded ? 120 : 0
                        }

                        NumberAnimation {
                            duration: wifiBox.expanded ? 170 : 110
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Repeater {
                    model: root.networks

                    Item {
                        id: netRow

                        required property var modelData

                        readonly property bool asking: root.asking === modelData.name
                        width: wifiList.width
                        height: asking ? 76 : 36

                        Behavior on height {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 36
                            radius: 10
                            antialiasing: true
                            color: netHit.containsMouse || netRow.asking ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07) : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            x: 10
                            y: 9
                            text: root.signalGlyph(netRow.modelData.signalStrength)
                            font.family: root.fontFamily
                            font.pixelSize: 16
                            color: netRow.modelData.connected ? root.ok : root.fgAlt
                        }

                        Text {
                            textFormat: Text.PlainText
                            x: 38
                            y: 10
                            width: parent.width - 38 - 84
                            elide: Text.ElideRight
                            text: netRow.modelData.name
                            font.family: root.fontFamily
                            font.pixelSize: 14
                            color: netRow.modelData.connected ? root.fg : netRow.modelData.known ? root.fgAlt : Qt.rgba(root.fgAlt.r, root.fgAlt.g, root.fgAlt.b, 0.8)
                        }

                        Text {
                            textFormat: Text.PlainText
                            x: parent.width - 80
                            y: 12
                            text: netRow.modelData.stateChanging ? "…" : root.open(netRow.modelData.security) ? "" : "󰌾"
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: root.muted
                        }

                        Text {
                            textFormat: Text.PlainText
                            x: parent.width - 56
                            y: 12
                            width: 46
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(netRow.modelData.signalStrength * 100) + "%"
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: root.fgAlt
                        }

                        MouseArea {
                            id: netHit

                            width: parent.width
                            height: 36
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    if (netRow.modelData.known)
                                        netRow.modelData.requestForget();
                                    return;
                                }
                                root.tapNetwork(netRow.modelData);
                            }
                        }

                        Rectangle {
                            y: 39
                            x: 10
                            width: parent.width - 20
                            height: 32
                            radius: 10
                            antialiasing: true
                            visible: netRow.height > 46
                            opacity: netRow.asking ? 1 : 0
                            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.09)

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 160
                                }
                            }

                            Text {
                                textFormat: Text.PlainText
                                x: 9
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰌾"
                                font.family: root.fontFamily
                                font.pixelSize: 12
                                color: root.muted
                            }

                            TextInput {
                                id: psk

                                x: 32
                                width: parent.width - 44
                                anchors.verticalCenter: parent.verticalCenter
                                echoMode: TextInput.Password
                                passwordCharacter: "•"
                                font.family: root.fontFamily
                                font.pixelSize: 13
                                color: root.fg
                                selectByMouse: true
                                selectionColor: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
                                focus: netRow.asking
                                onVisibleChanged: {
                                    if (!visible)
                                        text = "";
                                }
                                Keys.onEscapePressed: event => {
                                    root.asking = "";
                                    text = "";
                                    event.accepted = true;
                                }
                                onAccepted: {
                                    if (!text.length)
                                        return;
                                    netRow.modelData.requestConnectWithPsk(text);
                                    text = "";
                                    root.asking = "";
                                }

                                Text {
                                    textFormat: Text.PlainText
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    visible: !psk.text.length
                                    text: "password, enter to join"
                                    font: psk.font
                                    color: root.muted
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: root.askError.length ? 24 : 0
            clip: true

            Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: root.askError
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.crit
            }
        }

        SysSection {
            width: parent.width
            palette: root.palette
            label: "bluetooth"
            detail: root.btDetail
            busy: root.adapter ? (root.adapter.discovering || root.btBusy) : false
            toggled: root.adapter ? root.adapter.enabled : false
            onFlipped: {
                if (root.adapter)
                    root.adapter.enabled = !root.adapter.enabled;
            }
        }

        Flickable {
            id: btBox

            readonly property bool expanded: !!root.adapter && root.adapter.enabled

            width: parent.width
            height: expanded ? Math.min(root.adapter.discovering ? 216 : 108, Math.max(36, root.btDevices.length * 36)) : 0
            contentHeight: btList.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            visible: height > 0

            Behavior on height {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.InOutCubic
                }
            }

            Column {
                id: btList

                width: parent.width
                opacity: btBox.expanded ? 1 : 0

                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation {
                            duration: btBox.expanded ? 120 : 0
                        }

                        NumberAnimation {
                            duration: btBox.expanded ? 170 : 110
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Repeater {
                    model: root.btDevices

                    Item {
                        id: btRow

                        required property var modelData

                        width: btList.width
                        height: 36

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            antialiasing: true
                            color: btHit.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.07) : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            x: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.btGlyph(btRow.modelData.icon, btRow.modelData.name)
                            font.family: root.fontFamily
                            font.pixelSize: 16
                            color: btRow.modelData.connected ? root.ok : root.fgAlt
                        }

                        Text {
                            textFormat: Text.PlainText
                            x: 38
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 38 - 112
                            elide: Text.ElideRight
                            text: btRow.modelData.name || btRow.modelData.address
                            font.family: root.fontFamily
                            font.pixelSize: 14
                            color: btRow.modelData.connected ? root.fg : btRow.modelData.paired ? root.fgAlt : Qt.rgba(root.fgAlt.r, root.fgAlt.g, root.fgAlt.b, 0.75)
                        }

                        Text {
                            textFormat: Text.PlainText
                            x: parent.width - 108
                            width: 98
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            text: root.btStatus(btRow.modelData)
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: btRow.modelData.batteryAvailable && btRow.modelData.battery < 0.2 ? root.crit : root.fgAlt
                        }

                        MouseArea {
                            id: btHit

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: btRow.modelData.connected = !btRow.modelData.connected
                        }
                    }
                }
            }
        }

        Item {
            id: scanBox

            readonly property bool expanded: !!root.adapter && root.adapter.enabled

            width: parent.width
            height: expanded ? 38 : 0
            clip: true

            Behavior on height {
                NumberAnimation {
                    duration: 220
                    easing.type: Easing.InOutCubic
                }
            }

            Rectangle {
                x: 10
                opacity: scanBox.expanded ? 1 : 0
                anchors.verticalCenter: parent.verticalCenter

                Behavior on opacity {
                    SequentialAnimation {
                        PauseAnimation {
                            duration: scanBox.expanded ? 120 : 0
                        }

                        NumberAnimation {
                            duration: scanBox.expanded ? 170 : 110
                            easing.type: Easing.OutCubic
                        }
                    }
                }
                width: parent.width - 20
                height: 28
                radius: 10
                antialiasing: true
                color: root.adapter && root.adapter.discovering ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.26) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, scanHit.containsMouse ? 0.12 : 0.06)

                Behavior on color {
                    ColorAnimation {
                        duration: 140
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: root.adapter && root.adapter.discovering ? "stop scanning" : "scan for devices"
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    color: root.adapter && root.adapter.discovering ? root.fg : root.fgAlt
                }

                MouseArea {
                    id: scanHit

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.adapter)
                            root.adapter.discovering = !root.adapter.discovering;
                    }
                }
            }
        }

    }

    readonly property var btKinds: [
        {
            "kind": "earbuds",
            "glyph": "󱡏",
            "icons": [],
            "words": ["airpods", "buds", "earbud", "freebuds", "pods"]
        },
        {
            "kind": "headset",
            "glyph": "󰋎",
            "icons": ["audio-headset"],
            "words": ["headset"]
        },
        {
            "kind": "headphones",
            "glyph": "󰋋",
            "icons": ["audio-headphones"],
            "words": ["headphone", "wh-", "wf-", "momentum", "beats"]
        },
        {
            "kind": "speaker",
            "glyph": "󰓃",
            "icons": ["audio-card", "audio-speakers"],
            "words": ["speaker", "boombox", "jbl", "marshall", "soundcore"]
        },
        {
            "kind": "tv",
            "glyph": "󰔂",
            "icons": ["video-display"],
            "words": ["chromecast", "smart tv"]
        },
        {
            "kind": "gamepad",
            "glyph": "󰊴",
            "icons": ["input-gaming"],
            "words": ["controller", "gamepad", "dualsense", "dualshock", "xbox", "joy-con"]
        },
        {
            "kind": "mouse",
            "glyph": "󰍽",
            "icons": ["input-mouse"],
            "words": ["mouse", "mx master", "mx anywhere"]
        },
        {
            "kind": "keyboard",
            "glyph": "󰌌",
            "icons": ["input-keyboard"],
            "words": ["keyboard", "keychron"]
        },
        {
            "kind": "stylus",
            "glyph": "󰏫",
            "icons": ["input-tablet"],
            "words": ["pencil", "stylus", "wacom"]
        },
        {
            "kind": "watch",
            "glyph": "󰥔",
            "icons": [],
            "words": ["watch", "mi band", "amazfit", "garmin"]
        },
        {
            "kind": "phone",
            "glyph": "󰄜",
            "icons": ["phone"],
            "words": ["iphone", "pixel", "galaxy", "redmi", "xiaomi", "poco", "honor"]
        },
        {
            "kind": "laptop",
            "glyph": "󰌢",
            "icons": ["computer"],
            "words": ["macbook", "laptop", "thinkpad", "zenbook"]
        },
        {
            "kind": "printer",
            "glyph": "󰐪",
            "icons": ["printer", "scanner"],
            "words": ["printer", "deskjet", "laserjet", "epson"]
        },
        {
            "kind": "camera",
            "glyph": "󰄀",
            "icons": ["camera-photo", "camera-video"],
            "words": ["camera", "gopro"]
        },
        {
            "kind": "car",
            "glyph": "󰄋",
            "icons": [],
            "words": ["carplay", "car audio", "hyundai", "toyota", "kia", "my car"]
        },
        {
            "kind": "tracker",
            "glyph": "󰝥",
            "icons": [],
            "words": ["airtag", "smarttag", "tile "]
        },
        {
            "kind": "router",
            "glyph": "󰑩",
            "icons": ["modem", "network-wireless"],
            "words": ["router", "modem"]
        },
        {
            "kind": "player",
            "glyph": "󰲠",
            "icons": ["multimedia-player"],
            "words": []
        }
    ]

    function btMatch(icon, name) {
        var tag = (icon || "").toLowerCase();
        var label = (name || "").toLowerCase();
        var i;
        var j;
        for (i = 0; i < btKinds.length; i++) {
            var byName = btKinds[i].words;
            for (j = 0; j < byName.length; j++)
                if (label.indexOf(byName[j]) >= 0)
                    return btKinds[i];
        }
        for (i = 0; i < btKinds.length; i++) {
            var byIcon = btKinds[i].icons;
            for (j = 0; j < byIcon.length; j++)
                if (tag === byIcon[j])
                    return btKinds[i];
        }
        if (tag.indexOf("audio") >= 0)
            return btKinds[2];
        if (tag.indexOf("input") >= 0)
            return btKinds[6];
        return null;
    }

    function btGlyph(icon, name) {
        var hit = btMatch(icon, name);
        return hit ? hit.glyph : "󰂯";
    }

    function btKind(icon, name) {
        var hit = btMatch(icon, name);
        return hit ? hit.kind : "";
    }

    readonly property var batteryDevice: UPower.displayDevice
    readonly property real batteryLevel: batteryDevice && batteryDevice.isPresent ? batteryDevice.percentage : 0
    readonly property bool charging: batteryDevice ? (batteryDevice.state === UPowerDeviceState.Charging || (!UPower.onBattery && batteryDevice.state === UPowerDeviceState.FullyCharged)) : false

    readonly property color batteryTint: charging ? ok : batteryLevel <= 0.15 ? crit : batteryLevel <= 0.3 ? warn : ok

    function span(seconds) {
        if (!seconds || seconds <= 0)
            return "";
        var h = Math.floor(seconds / 3600);
        var m = Math.round((seconds % 3600) / 60);
        return h > 0 ? h + "h " + m + "m" : m + "m";
    }

    readonly property string batteryText: {
        if (!batteryDevice || !batteryDevice.isPresent)
            return "no battery";
        var pct = Math.round(batteryLevel * 100) + "%";
        if (batteryDevice.state === UPowerDeviceState.FullyCharged)
            return pct + "  full";
        var left = charging ? span(batteryDevice.timeToFull) : span(batteryDevice.timeToEmpty);
        return left.length ? pct + "  " + left + (charging ? " to full" : " left") : pct;
    }

    readonly property string loadLine: {
        var parts = [];
        if (cpuLine.length)
            parts.push(cpuLine);
        if (ramLine.length)
            parts.push(ramLine);
        return parts.join("   ");
    }
}
