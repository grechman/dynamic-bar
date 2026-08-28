import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")
    readonly property string stateDir: Quickshell.env("ISLAND_DIR") || (home + "/.cache/island")
    property string position: Quickshell.env("ISLAND_PREVIEW") === "1" ? "bottom" : "top"
    readonly property bool bottom: position === "bottom"
    property bool hidden: false
    property string fontFamily: ""
    property var rawScene: ({})
    property bool stale: false
    readonly property var scene: stale ? {
        "palette": rawScene.palette || ({}),
        "main": null,
        "event": null,
        "bubble": null
    } : rawScene
    readonly property var palette: {
        var base = scene.palette || ({});
        if (!fontFamily)
            return base;
        var out = ({});
        for (var key in base)
            out[key] = base[key];
        out.font = fontFamily;
        return out;
    }

    IpcHandler {
        target: "island"

        function open(name: string): void {
            root.openPanel(name);
        }

        function close(): void {
            root.openPanel("");
        }
    }

    function openPanel(name) {
        shelfOpen = false;
        usageOpen = false;
        systemOpen = false;
        musicOpen = false;
        if (name === "usage")
            usageOpen = true;
        else if (name === "system")
            systemOpen = true;
        else if (name === "music")
            musicOpen = true;
        else if (name === "settings" || name === "shelf") {
            islandPanel = name;
            shelfOpen = true;
        }
    }

    FontLoader {
        source: "file://" + root.pluginDir + "/assets/fonts/ActionsIsland-Regular.ttf"
    }

    FontLoader {
        source: "file://" + root.pluginDir + "/assets/fonts/T3Island-Regular.ttf"
    }

    readonly property string calendarMarkup: {
        var raw = root.scene.tooltip || "";
        if (!raw)
            return "";
        var day = Qt.formatDateTime(sysClock.date, "d");
        var lines = raw.split("\n");
        var out = [];
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].replace(/&/g, "&amp;").replace(/</g, "&lt;");
            if (i > 1)
                line = line.replace(new RegExp("(^|\\s)" + day + "(?=\\s|$)"), "$1<b>" + day + "</b>");
            out.push(line);
        }
        return "<pre style='line-height:1.25; font-family:" + (root.palette.font || "JetBrainsMono Nerd Font") + "'>" + out.join("\n") + "</pre>";
    }

    FileView {
        id: sceneFile
        path: root.stateDir + "/scene.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.rawScene = JSON.parse(sceneFile.text());
                root.stale = false;
            } catch (e) {}
        }
    }

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: {
            var ts = root.rawScene.ts || 0;
            root.stale = ts > 0 && (Date.now() / 1000 - ts) > 30;
        }
    }

    Process {
        id: bubbleClick
    }

    function clickBubble(half) {
        bubbleClick.command = ["env", "ISLAND_DIR=" + root.stateDir, "python3", root.pluginDir + "/island.py", "bubble", String(half)];
        bubbleClick.running = true;
    }

    Process {
        id: tuneClick
    }

    function flipSetting(key) {
        tuneClick.command = ["env", "ISLAND_DIR=" + root.stateDir, "python3", root.pluginDir + "/island.py", "set", key];
        tuneClick.running = true;
    }

    Process {
        id: musicClick
    }

    Process {
        id: shelfClick
    }

    Process {
        id: shelfBlob
        stdinEnabled: true
    }

    function encode64(buffer) {
        var bytes = new Uint8Array(buffer);
        var table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        var out = [];
        var i = 0;
        for (; i + 2 < bytes.length; i += 3) {
            var trio = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
            out.push(table[(trio >> 18) & 63], table[(trio >> 12) & 63], table[(trio >> 6) & 63], table[trio & 63]);
        }
        var rest = bytes.length - i;
        if (rest === 1) {
            var one = bytes[i] << 16;
            out.push(table[(one >> 18) & 63], table[(one >> 12) & 63], "=", "=");
        } else if (rest === 2) {
            var two = (bytes[i] << 16) | (bytes[i + 1] << 8);
            out.push(table[(two >> 18) & 63], table[(two >> 12) & 63], table[(two >> 6) & 63], "=");
        }
        return out.join("");
    }

    function stashImage(drop) {
        var wanted = ["image/png", "image/jpeg", "image/webp", "image/bmp"];
        for (var i = 0; i < wanted.length; i++) {
            if (drop.formats.indexOf(wanted[i]) < 0)
                continue;
            var buffer = drop.getDataAsArrayBuffer(wanted[i]);
            if (!buffer || !buffer.byteLength)
                continue;
            shelfBlob.command = ["env", "ISLAND_DIR=" + root.stateDir, "python3", root.pluginDir + "/island.py", "shelf", "blob", wanted[i].split("/")[1]];
            shelfBlob.stdinEnabled = true;
            shelfBlob.running = true;
            shelfBlob.write(root.encode64(buffer));
            shelfBlob.stdinEnabled = false;
            return true;
        }
        return false;
    }

    property bool shelfOpen: false
    property string islandPanel: "shelf"

    property bool systemOpen: false
    property bool usageOpen: false
    property bool musicOpen: false
    property bool systemWide: false
    readonly property bool held: !!root.scene.hold

    onShelfOpenChanged: {
        if (shelfOpen) {
            musicOpen = false;
            systemOpen = false;
            usageOpen = false;
        }
    }

    onSystemOpenChanged: {
        if (systemOpen) {
            musicOpen = false;
            shelfOpen = false;
            usageOpen = false;
            musicHold.stop();
            systemWide = true;
        } else {
            musicHold.restart();
        }
    }

    Timer {
        id: musicHold

        interval: 90
        repeat: false
        onTriggered: root.systemWide = false
    }

    onUsageOpenChanged: {
        if (usageOpen) {
            musicOpen = false;
            shelfOpen = false;
            systemOpen = false;
        }
    }

    onMusicOpenChanged: {
        if (musicOpen) {
            shelfOpen = false;
            systemOpen = false;
            usageOpen = false;
        }
    }

    function shelfAction(action, argument) {
        var call = ["env", "ISLAND_DIR=" + root.stateDir, "python3", root.pluginDir + "/island.py", "shelf", action];
        if (argument !== undefined && argument !== "")
            call.push(argument);
        shelfClick.command = call;
        shelfClick.running = true;
    }

    function clickMusic(action) {
        musicClick.command = ["env", "ISLAND_DIR=" + root.stateDir, "python3", root.pluginDir + "/island.py", "music", action];
        musicClick.running = true;
    }

    Process {
        id: dateClick
        command: ["env", "ISLAND_DIR=" + root.stateDir, "python3", root.pluginDir + "/island.py", "date"]
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: unit
            required property var modelData

            PanelWindow {
                id: backdrop
                screen: unit.modelData

                anchors {
                    top: !root.bottom
                    bottom: root.bottom
                    left: true
                    right: true
                }
                implicitHeight: 35
                color: "transparent"
                WlrLayershell.namespace: "quickshell-bar"
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                readonly property color fg: (root.scene.palette && root.scene.palette.fg) || "#c5c9c5"
                readonly property color accent: (root.scene.palette && root.scene.palette.accent) || "#658594"

                readonly property color bg: (root.scene.palette && root.scene.palette.bg) || "#181616"

                function frost(amount) {
                    return Qt.rgba(backdrop.bg.r, backdrop.bg.g, backdrop.bg.b, amount);
                }

                function sheen(amount) {
                    return Qt.rgba(backdrop.fg.r, backdrop.fg.g, backdrop.fg.b, amount);
                }

                Rectangle {
                    anchors.fill: parent
                    color: backdrop.sheen(0.10)
                }

                Rectangle {
                    anchors.fill: parent

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: backdrop.frost(0.58)
                        }

                        GradientStop {
                            position: 0.22
                            color: backdrop.frost(0.40)
                        }

                        GradientStop {
                            position: 0.5
                            color: backdrop.frost(0.30)
                        }

                        GradientStop {
                            position: 0.78
                            color: backdrop.frost(0.46)
                        }

                        GradientStop {
                            position: 1
                            color: backdrop.frost(0.64)
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 9

                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: backdrop.sheen(0.09)
                        }

                        GradientStop {
                            position: 0.35
                            color: backdrop.sheen(0.04)
                        }

                        GradientStop {
                            position: 1
                            color: backdrop.sheen(0)
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1.5
                    color: Qt.rgba(backdrop.accent.r, backdrop.accent.g, backdrop.accent.b, 0.22)
                }

                LeftCell {
                    id: leftCell
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    y: 3
                    palette: root.palette
                }
            }

            PanelWindow {
                id: usageWindow
                screen: unit.modelData
                visible: !root.hidden && !root.scene.fullscreen

                anchors {
                    top: !root.bottom
                    bottom: root.bottom
                    left: true
                }
                margins.left: 158
                implicitWidth: usage.panelWidth
                implicitHeight: 720
                mask: Region {
                    x: usage.x + usage.pillItem.x
                    y: usage.y + usage.pillItem.y
                    width: usage.pillItem.width
                    height: usage.pillItem.height
                }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: root.usageOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                Shortcut {
                    sequence: "Escape"
                    context: Qt.WindowShortcut
                    enabled: root.usageOpen
                    onActivated: root.usageOpen = false
                }

                HyprlandFocusGrab {
                    id: usageGrab
                    windows: [usageWindow]
                    active: root.usageOpen
                    onCleared: {
                        if (!root.held)
                            root.usageOpen = false;
                    }
                }

                UsageCell {
                    id: usage
                    anchors.left: parent.left
                    y: 3
                    pluginDir: root.pluginDir
                    palette: root.palette
                    open: root.usageOpen
                    onToggled: root.usageOpen = !root.usageOpen
                }
            }

            PanelWindow {
                id: panel
                screen: unit.modelData
                visible: !root.hidden && !root.scene.fullscreen

                anchors {
                    top: !root.bottom
                    bottom: root.bottom
                }
                implicitWidth: 760
                implicitHeight: 720
                mask: Region {
                    Region {
                        x: island.x + island.pillItem.x
                        y: island.y + island.pillItem.y
                        width: island.pillItem.width
                        height: island.pillItem.height
                    }

                    Region {
                        x: island.x + island.satelliteItem.x
                        y: island.y + island.satelliteItem.y
                        width: island.satelliteItem.width
                        height: island.satelliteItem.height
                    }

                    Region {
                        x: island.x + island.clipItem.x
                        y: island.y + island.clipItem.y
                        width: island.clipItem.width
                        height: island.clipItem.height
                    }
                }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: root.shelfOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                property bool dragHold: false

                DropArea {
                    anchors.fill: parent

                    onEntered: drag => {
                        drag.accept(Qt.CopyAction);
                        if (!root.shelfOpen) {
                            panel.dragHold = true;
                            root.shelfOpen = true;
                        }
                    }
                    onPositionChanged: drag => drag.accept(Qt.CopyAction)
                    onExited: {
                        if (panel.dragHold) {
                            panel.dragHold = false;
                            root.shelfOpen = false;
                        }
                    }
                    onDropped: drop => {
                        panel.dragHold = false;
                        if (drop.hasUrls)
                            root.shelfAction("drop", drop.urls.join("\n"));
                        else if (!root.stashImage(drop) && drop.hasText)
                            root.shelfAction("note", drop.text);
                        drop.acceptProposedAction();
                    }
                }

                HyprlandFocusGrab {
                    id: shelfGrab
                    windows: [panel]
                    active: root.shelfOpen && !panel.dragHold
                    onCleared: {
                        if (!root.held)
                            root.shelfOpen = false;
                    }
                }

                Item {
                    anchors.fill: parent
                    focus: root.shelfOpen

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.shelfOpen = false;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                            root.shelfAction("paste", "");
                            event.accepted = true;
                        }
                    }
                }

                IslandView {
                    id: island
                    pluginDir: root.pluginDir
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 4
                    width: 700
                    scene: root.scene
                    clockText: Qt.formatDateTime(sysClock.date, "HH:mm")
                    onBubbleActivated: half => root.clickBubble(half)
                    panel: root.islandPanel
                    settings: root.scene.settings || null
                    onTuneFlip: key => root.flipSetting(key)
                    onPillActivated: {
                        root.islandPanel = "settings";
                        root.shelfOpen = !root.shelfOpen;
                    }
                    onPillAlternate: dateClick.running = true
                    shelfOpen: root.shelfOpen
                    onShelfToggled: {
                        root.islandPanel = "shelf";
                        root.shelfOpen = !root.shelfOpen;
                    }
                    onShelfCopy: name => root.shelfAction("copy", name)
                    onShelfReveal: name => root.shelfAction("open", name)
                    onShelfDrop: name => root.shelfAction("remove", name)
                }
            }

            PanelWindow {
                id: systemPanel
                screen: unit.modelData
                visible: !root.hidden && !root.scene.fullscreen

                anchors {
                    top: !root.bottom
                    bottom: root.bottom
                    right: true
                }
                margins.right: 8
                implicitWidth: system.panelWidth
                implicitHeight: 720
                mask: Region {
                    x: system.x + system.pillItem.x
                    y: system.y + system.pillItem.y
                    width: system.pillItem.width
                    height: system.pillItem.height
                }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: root.systemOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                HyprlandFocusGrab {
                    id: systemGrab
                    windows: [systemPanel]
                    active: root.systemOpen
                    onCleared: {
                        if (!root.held)
                            root.systemOpen = false;
                    }
                }

                Shortcut {
                    sequence: "Escape"
                    context: Qt.WindowShortcut
                    enabled: root.systemOpen
                    onActivated: root.systemOpen = false
                }

                SystemCell {
                    id: system
                    anchors.right: parent.right
                    y: 3
                    sys: root.scene.sys || null
                    pluginDir: root.pluginDir
                    palette: root.palette
                    open: root.systemOpen
                    onToggled: root.systemOpen = !root.systemOpen
                }
            }

            PanelWindow {
                id: musicPanel
                screen: unit.modelData
                visible: !root.hidden && music.width > 2 && !root.scene.fullscreen

                anchors {
                    top: !root.bottom
                    bottom: root.bottom
                    right: true
                }
                margins.right: 30 + system.collapsedWidth
                implicitWidth: Math.max(249, music.panelWidth) + system.panelWidth - system.collapsedWidth
                implicitHeight: 720
                mask: Region {
                    x: music.x + music.pillItem.x
                    y: music.y + music.pillItem.y
                    width: music.pillItem.width
                    height: music.pillItem.height
                }
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: root.musicOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                Shortcut {
                    sequence: "Escape"
                    context: Qt.WindowShortcut
                    enabled: root.musicOpen
                    onActivated: root.musicOpen = false
                }

                HyprlandFocusGrab {
                    windows: [musicPanel]
                    active: root.musicOpen
                    onCleared: {
                        if (!root.held)
                            root.musicOpen = false;
                    }
                }

                readonly property real shift: root.systemWide ? system.panelWidth - system.collapsedWidth : 0
                readonly property bool crowded: unit.modelData.width / 2 + island.pillItem.width / 2 + 14 > unit.modelData.width - margins.right - music.width

                Music {
                    id: music
                    anchors.right: parent.right
                    anchors.rightMargin: musicPanel.shift
                    y: 4
                    opacity: musicPanel.crowded ? 0 : 1
                    scale: musicPanel.crowded ? 0.9 : 1
                    transformOrigin: Item.Right

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 220
                            easing.type: Easing.OutCubic
                        }
                    }

                    Behavior on scale {
                        NumberAnimation {
                            duration: 260
                            easing.type: Easing.OutCubic
                        }
                    }


                    Behavior on anchors.rightMargin {
                        NumberAnimation {
                            duration: root.systemOpen ? 320 : 360
                            easing.type: Easing.InOutCubic
                        }
                    }

                    state: root.scene.music || null
                    palette: root.palette
                    onPrevious: root.clickMusic("prev")
                    onToggle: root.clickMusic("toggle")
                    onNext: root.clickMusic("next")
                    onArt: root.clickMusic("focus")
                    onMute: root.clickMusic("mute")
                    onLike: root.clickMusic("like")
                    onExpand: root.musicOpen = !root.musicOpen
                    open: root.musicOpen
                    onSeek: seconds => root.clickMusic("seek:" + seconds.toFixed(1))
                }
            }

            PanelWindow {
                id: tipPanel
                screen: unit.modelData
                visible: !root.hidden && !root.scene.fullscreen && (calendarTip.active || bubbleTip.active)

                anchors {
                    top: !root.bottom
                    bottom: root.bottom
                    left: true
                }
                margins.top: root.bottom ? 0 : 35
                margins.bottom: root.bottom ? 35 : 0
                margins.left: Math.max(4, Math.round(tipCenter - implicitWidth / 2))
                implicitWidth: Math.max(calendarTip.width, bubbleTip.width) + 12
                implicitHeight: Math.max(calendarTip.height, bubbleTip.height) + 16
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Top
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                readonly property real tipCenter: {
                    var base = (unit.modelData.width - panel.implicitWidth) / 2 + island.x;
                    if (bubbleTip.active)
                        return base + island.satelliteItem.x + island.satelliteItem.width / 2;
                    return base + island.pillItem.x + island.pillItem.width / 2;
                }

                Tooltip {
                    id: calendarTip
                    palette: root.palette
                    anchorX: parent.width / 2
                    anchorY: 0
                    active: island.pillHovered && hoverDelay.fired && !island.bubbleHovered
                    text: root.calendarMarkup
                }

                Tooltip {
                    id: bubbleTip
                    palette: root.palette
                    anchorX: parent.width / 2
                    anchorY: 0
                    active: island.bubbleHovered && !!root.scene.bubble
                    text: root.scene.bubble ? (root.scene.bubble.tooltip || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/\n/g, "<br>") : ""
                }
            }

            Timer {
                id: hoverDelay
                property bool fired: false
                interval: 350
                repeat: false
                running: island.pillHovered
                onTriggered: fired = true
            }

            Connections {
                target: island

                function onPillHoveredChanged() {
                    if (!island.pillHovered)
                        hoverDelay.fired = false;
                }
            }
        }
    }
}
