import QtQuick

Item {
    id: view
    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var scene: ({
    })
    property var palette: scene.palette || ({
    })
    property string clockText: ""
    property bool pillHovered: false
    property bool bubbleHovered: false
    property alias pillItem: pill
    property alias satelliteItem: satellite
    property alias clipItem: clip
    readonly property int padLeft: shown.icon === "" ? 14 : shown.provider === "claude" ? 17 : 19
    readonly property int padRight: shown.showDot ? 12 : 14
    readonly property int nextPadLeft: pending.icon === "" ? 14 : pending.provider === "claude" ? 17 : 19
    readonly property int nextPadRight: pending.showDot ? 12 : 14
    readonly property color bg: palette.bg || "#181616"
    readonly property color bgAlt: palette.bg_alt || "#282727"
    readonly property color accent: palette.accent || "#658594"
    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color ok: palette.ok || "#87a987"
    readonly property color warn: palette.warn || "#c4b28a"
    readonly property color crit: palette.crit || "#c4746e"
    readonly property color claude: palette.claude || "#D97757"
    readonly property color telegram: palette.telegram || "#229ED9"

    onShelfOpenChanged: {
        if (shelfOpen) {
            shelfFold.stop();
            shelfOpenHeight = shelfHeight;
            shelfShape = true;
            shelfReveal2.restart();
        } else {
            shelfReveal2.stop();
            shelfContent = false;
            shelfFold.restart();
        }
        sceneChanged();
    }

    property var shown: descriptor()
    property var pending: descriptor()
    readonly property color toneColor: shown.tone === "good" ? mix(bgAlt, ok, 0.25) : shown.tone === "bad" ? mix(bgAlt, crit, 0.25) : shown.tone === "blocked" ? mix(bgAlt, crit, 0.22) : bgAlt
    property color baseColor: "#282727"
    property real sweepProgress: 0
    property bool swapMerge: false
    property string lastMainProvider: ""
    readonly property bool mergeActive: {
        if (swapMerge)
            return true;

        var ev = scene.event || null;
        if (!ev)
            return false;

        if (ev.kind !== "done" && ev.kind !== "question")
            return false;

        var current = scene.bubble || satellite.lastBubble || null;
        if (!ev.provider || !current || !current.provider)
            return true;

        if (ev.provider === current.provider)
            return true;

        return !!(current.second && current.second.provider === ev.provider);
    }
    readonly property string mainProvider: scene.main ? (scene.main.provider || "") : ""
    property string lastEventKey: ""

    readonly property int shelfCount: shelfGrid.items.length
    property bool shelfOpen: false
    property string panel: "shelf"
    property var settings: null
    property string pluginDir: ""

    property real glass: shelfShape ? 1 : 0
    readonly property color glassTint: mix(baseColor, bg, glass * 0.55)

    Behavior on glass {
        NumberAnimation {
            duration: 320
            easing.type: Easing.InOutCubic
        }
    }

    readonly property int shelfHeight: 44 + (panel === "settings" ? tune.implicitHeight : shelfGrid.implicitHeight) + 24
    readonly property bool shelfMoving: pill.height > 28
    property int shelfOpenHeight: 27

    onShelfHeightChanged: {
        if (shelfOpen)
            shelfOpenHeight = shelfHeight;
    }

    onShelfShapeChanged: {
        sceneChanged();
    }

    property bool shelfContent: false
    property bool shelfShape: false

    Timer {
        id: shelfReveal2
        interval: 300
        repeat: false
        onTriggered: view.shelfContent = true
    }

    Timer {
        id: shelfFold
        interval: 90
        repeat: false
        onTriggered: view.shelfShape = false
    }



    signal shelfToggled()
    signal tuneFlip(string key)
    signal shelfCopy(string name)
    signal shelfReveal(string name)
    signal shelfDrop(string name)
    signal bubbleActivated(int half)
    signal pillActivated()
    signal pillAlternate()

    function mix(base, tint, amount) {
        return Qt.rgba(base.r + (tint.r - base.r) * amount, base.g + (tint.g - base.g) * amount, base.b + (tint.b - base.b) * amount, 1);
    }

    function severityColor(severity) {
        if (severity === "good")
            return ok;

        if (severity === "bad" || severity === "crit")
            return crit;

        return fg;
    }

    function dotColor(name) {
        if (name === "crit")
            return crit;

        if (name === "warn")
            return warn;

        return ok;
    }

    function descriptor() {
        if (shelfShape && panel === "settings")
            return {
                "struct": "shelf",
                "key": "tune",
                "icon": "\uf013",
                "iconSize": 15,
                "iconColor": accent,
                "provider": "",
                "tone": "plain",
                "showDot": false,
                "text": "settings"
            };
        if (shelfShape)
            return {
                "struct": "shelf",
                "key": "shelf|" + shelfCount,
                "icon": "\uf0c6",
                "iconSize": 15,
                "iconColor": accent,
                "iconGap": 9,
                "text": shelfCount === 1 ? "1 thing on the shelf" : shelfCount + " things on the shelf",
                "textColor": fg,
                "note": "",
                "noteColor": muted,
                "showClock": false,
                "showDot": false,
                "dot": "ok",
                "tone": "plain",
                "pulse": false
            };
        var ev = scene.event || null;
        var main = scene.main || null;
        if (ev) {
            var telegramLayout = ev.layout === "telegram";
            var tone = "plain";
            if (ev.kind === "done")
                tone = "good";
            else if (ev.kind === "question" || ev.severity === "crit")
                tone = "bad";
            return {
                "struct": "ev|" + (ev.id || "") + "|" + (telegramLayout ? ev.sender : ev.text),
                "key": "ev|" + (ev.id || "") + "|" + (telegramLayout ? ev.sender + "|" + ev.count : ev.text),
                "icon": ev.icon || "",
                "iconSize": ev.provider === "claude" ? 20 : 17,
                "iconColor": telegramLayout ? telegram : ev.provider === "claude" ? (ev.kind === "done" ? ok : ev.kind === "question" ? crit : claude) : severityColor(ev.severity),
                "iconGap": ev.provider === "claude" ? 5 : 7,
                "provider": ev.provider || "",
                "text": telegramLayout ? (ev.sender || "") : (ev.text || ""),
                "textColor": severityColor(ev.severity),
                "note": telegramLayout ? String(ev.count || "") : "",
                "noteColor": fgAlt,
                "showClock": !!main,
                "showDot": !!main && ev.kind !== "done",
                "dot": ev.kind === "question" || ev.severity === "crit" ? "crit" : main ? main.dot : "ok",
                "tone": tone,
                "pulse": ev.severity === "crit"
            };
        }
        if (main)
            return {
                "struct": "main|" + main.kind + "|" + (main.provider || "") + "|" + main.text,
                "key": "main|" + main.kind + "|" + (main.provider || "") + "|" + main.text + "|" + main.note,
                "icon": main.icon || "",
                "iconSize": main.provider === "claude" ? 20 : 17,
                "iconColor": main.provider === "claude" ? (main.tone === "bad" ? crit : claude) : main.tone === "bad" ? crit : fg,
                "iconGap": main.provider === "claude" ? 5 : 7,
                "provider": main.provider || "",
                "text": main.text || "",
                "textColor": main.tone === "bad" ? crit : fg,
                "note": main.note || "",
                "noteColor": muted,
                "showClock": true,
                "showDot": true,
                "dot": main.dot || "ok",
                "tone": main.tone === "bad" ? "blocked" : "plain",
                "pulse": false
            };

        return {
            "struct": "idle",
            "key": "idle",
            "icon": "",
            "iconSize": 17,
            "iconColor": fg,
            "iconGap": 0,
            "provider": "",
            "text": "",
            "textColor": fg,
            "note": "",
            "noteColor": muted,
            "showClock": true,
            "showDot": false,
            "dot": "ok",
            "tone": "plain",
            "pulse": false
        };
    }

    implicitWidth: pill.width
    implicitHeight: pill.height
    onSceneChanged: {
        var next = descriptor();
        if (next.key === pending.key) {
            pending = next;
            if (!swap.running && !noteSwap.running)
                shown = next;

            return ;
        }
        var noteOnly = next.struct === pending.struct && !swap.running;
        pending = next;
        if (noteOnly)
            noteSwap.restart();
        else
            swap.restart();
    }
    Component.onCompleted: baseColor = toneColor
    onToneColorChanged: {
        if (Qt.colorEqual(baseColor, toneColor))
            return ;

        sweepPause.duration = Qt.colorEqual(toneColor, bgAlt) ? 0 : 110;
        sweep.color = toneColor;
        sweepAnim.restart();
    }

    SequentialAnimation {
        id: sweepAnim

        PauseAnimation {
            id: sweepPause

            duration: 0
        }

        NumberAnimation {
            target: view
            property: "sweepProgress"
            from: 0
            to: 1
            duration: 240
            easing.type: Easing.OutCubic
        }

        ScriptAction {
            script: {
                view.baseColor = view.toneColor;
                view.sweepProgress = 0;
            }
        }

    }

    Rectangle {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        height: view.shelfShape ? view.shelfOpenHeight : 27
        radius: view.shelfShape ? 26 : height / 2

        Behavior on height {
            NumberAnimation {
                duration: view.shelfShape ? 320 : 360
                easing.type: Easing.InOutCubic
            }
        }
        Behavior on radius {
            NumberAnimation {
                duration: 320
                easing.type: Easing.InOutCubic
            }
        }
        transformOrigin: Item.Center
        color: Qt.rgba(view.glassTint.r, view.glassTint.g, view.glassTint.b, 1 - 0.38 * view.glass)
        border.width: 1 + view.glass
        border.color: Qt.rgba(view.fg.r, view.fg.g, view.fg.b, 0.18 + 0.10 * view.glass)
        width: view.shelfShape ? (view.panel === "settings" ? tune.implicitWidth + 48 : shelfGrid.implicitWidth + 48) : measure.implicitWidth + view.nextPadLeft + view.nextPadRight

        Rectangle {
            id: sweep

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            width: parent.width * view.sweepProgress
            radius: height / 2
            visible: width > 0.5

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    position: 0
                    color: Qt.rgba(view.toneColor.r, view.toneColor.g, view.toneColor.b, 0)
                }

                GradientStop {
                    position: Math.min(0.9, 26 / Math.max(1, sweep.width))
                    color: view.toneColor
                }

                GradientStop {
                    position: 1
                    color: view.toneColor
                }
            }
        }

        Item {
            id: viewport

            anchors.fill: parent
            anchors.rightMargin: view.padRight
            clip: true

            Row {
                id: content

                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: view.shelfShape ? -(pill.height / 2 - 22) : 0
                anchors.left: parent.left
                anchors.leftMargin: view.shelfShape ? 26 : view.padLeft

                Behavior on anchors.leftMargin {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.InOutCubic
                    }
                }
                spacing: 0
                opacity: 1

                Text {
                    textFormat: Text.PlainText
                    id: glyph

                    anchors.verticalCenter: parent.verticalCenter
                    visible: shown.icon !== ""
                    text: shown.icon
                    font.family: shown.provider === "codex" ? view.fontFamily : "Actions Island"
                    font.pixelSize: shown.iconSize
                    font.weight: Font.ExtraBold
                    color: shown.iconColor
                    rightPadding: visible ? shown.iconGap : 0
                }

                Text {
                    textFormat: Text.PlainText
                    id: label

                    anchors.verticalCenter: parent.verticalCenter
                    visible: shown.text !== ""
                    text: shown.text
                    font.family: view.fontFamily
                    font.pixelSize: 17
                    font.weight: Font.ExtraBold
                    color: shown.textColor
                    rightPadding: visible && (shown.note !== "" || shown.showClock || shown.showDot) ? 19 : 0
                }

                Text {
                    textFormat: Text.PlainText
                    id: note

                    anchors.verticalCenter: parent.verticalCenter
                    visible: shown.note !== ""
                    text: shown.note
                    font.family: view.fontFamily
                    font.pixelSize: 17
                    font.weight: Font.ExtraBold
                    color: shown.noteColor
                    rightPadding: visible && (shown.showClock || shown.showDot) ? 17 : 0
                }

                Text {
                    textFormat: Text.PlainText
                    id: clock

                    anchors.verticalCenter: parent.verticalCenter
                    visible: shown.showClock
                    text: view.clockText
                    font.family: view.fontFamily
                    font.pixelSize: 17
                    font.weight: Font.ExtraBold
                    color: view.fg
                }

                Item {
                    width: shown.showDot ? 16 : 0
                    height: 27

                    Rectangle {
                        id: dot

                        anchors.verticalCenter: parent.verticalCenter
                        x: 9
                        width: 7
                        height: 7
                        radius: 3.5
                        opacity: shown.showDot ? 1 : 0
                        color: view.dotColor(shown.dot)

                        Timer {
                            property real phase: 0

                            running: shown.showDot
                            repeat: true
                            interval: 33
                            onTriggered: {
                                phase = (phase + interval / 3600) % 1;
                                dot.opacity = 0.28 + 0.72 * (0.5 + 0.5 * Math.cos(2 * Math.PI * phase));
                            }
                        }

                    }

                }

            }

        }

        Row {
            id: measure

            opacity: 0
            spacing: 0

            Text {
                textFormat: Text.PlainText
                visible: view.pending.icon !== ""
                text: view.pending.icon
                font.family: glyph.font.family
                font.pixelSize: view.pending.iconSize
                font.weight: Font.ExtraBold
                rightPadding: visible ? view.pending.iconGap : 0
            }

            Text {
                textFormat: Text.PlainText
                visible: view.pending.text !== ""
                text: view.pending.text
                font.family: label.font.family
                font.pixelSize: label.font.pixelSize
                font.weight: Font.ExtraBold
                rightPadding: visible && (view.pending.note !== "" || view.pending.showClock || view.pending.showDot) ? 19 : 0
            }

            Text {
                textFormat: Text.PlainText
                visible: view.pending.note !== ""
                text: view.pending.note
                font.family: note.font.family
                font.pixelSize: note.font.pixelSize
                font.weight: Font.ExtraBold
                rightPadding: visible && (view.pending.showClock || view.pending.showDot) ? 17 : 0
            }

            Text {
                textFormat: Text.PlainText
                visible: view.pending.showClock
                text: view.clockText
                font.family: clock.font.family
                font.pixelSize: clock.font.pixelSize
                font.weight: Font.ExtraBold
            }

            Item {
                width: view.pending.showDot ? 16 : 0
                height: 27
            }

        }

        Settings {
            id: tune

            x: 24
            y: 44
            width: implicitWidth
            height: implicitHeight
            visible: view.panel === "settings" && opacity > 0.01
            opacity: view.shelfContent && view.panel === "settings" ? 1 : 0
            palette: view.palette
            settings: view.settings
            pluginDir: view.pluginDir
            missing: view.scene.missing || []
            onFlip: key => view.tuneFlip(key)

            Behavior on opacity {
                NumberAnimation {
                    duration: view.shelfContent ? 200 : 90
                    easing.type: Easing.OutCubic
                }
            }
        }

        Shelf {
            id: shelfGrid

            x: 24
            y: 44
            width: implicitWidth
            height: implicitHeight
            opacity: view.shelfContent && view.panel === "shelf" ? 1 : 0
            visible: view.panel === "shelf" && opacity > 0.01
            shelf: view.scene.shelf || null
            palette: view.palette
            onCopyItem: name => view.shelfCopy(name)
            onOpenItem: name => view.shelfReveal(name)
            onDropItem: name => view.shelfDrop(name)

            Behavior on opacity {
                NumberAnimation {
                    duration: view.shelfContent ? 200 : 90
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !view.shelfOpen
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: view.pillHovered = true
            onExited: view.pillHovered = false
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton)
                    view.pillAlternate();
                else
                    view.pillActivated();
            }
        }

        Behavior on width {
            SequentialAnimation {
                PauseAnimation {
                    duration: 90
                }

                NumberAnimation {
                    duration: 240
                    easing.type: Easing.InOutCubic
                }
            }
        }

        SequentialAnimation on color {
            running: shown.pulse
            loops: Animation.Infinite

            ColorAnimation {
                to: view.mix(view.bgAlt, view.crit, 0.35)
                duration: 550
            }

            ColorAnimation {
                to: view.mix(view.bgAlt, view.crit, 0.18)
                duration: 550
            }

        }

    }

    SequentialAnimation {
        id: pulseAnim

        NumberAnimation {
            target: pill
            property: "scale"
            to: 1.04
            duration: 140
            easing.type: Easing.OutCubic
        }

        NumberAnimation {
            target: pill
            property: "scale"
            to: 1
            duration: 320
            easing.type: Easing.OutBack
            easing.overshoot: 1.2
        }

    }

    SequentialAnimation {
        id: noteSwap

        NumberAnimation {
            target: note
            property: "opacity"
            to: 0
            duration: 80
            easing.type: Easing.OutCubic
        }

        ScriptAction {
            script: view.shown = view.pending
        }

        NumberAnimation {
            target: note
            property: "opacity"
            to: 1
            duration: 150
            easing.type: Easing.InCubic
        }

    }

    SequentialAnimation {
        id: swap

        NumberAnimation {
            target: content
            property: "opacity"
            to: 0
            duration: 90
            easing.type: Easing.OutCubic
        }

        ScriptAction {
            script: view.shown = view.pending
        }

        NumberAnimation {
            target: content
            property: "opacity"
            to: 1
            duration: 170
            easing.type: Easing.InCubic
        }

    }

    Timer {
        id: swapMergeTimer

        interval: 300
        repeat: false
        onTriggered: view.swapMerge = false
    }

    Rectangle {
        id: clip

        readonly property bool lit: shelfPress.containsMouse || view.shelfOpen

        x: pill.x - width - 6
        anchors.verticalCenter: parent.verticalCenter
        width: 27
        height: 27
        radius: 13.5
        antialiasing: true
        readonly property bool offered: (view.shelfCount > 0 || view.pillHovered || shelfPress.containsMouse) && !view.shelfShape && !view.shelfMoving

        opacity: offered ? 1 : 0
        scale: offered ? 1 : 0.7
        visible: opacity > 0.01
        color: lit ? view.mix(view.bgAlt, view.accent, 0.3) : view.bgAlt
        border.width: 1
        border.color: lit ? Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.6) : Qt.rgba(view.fg.r, view.fg.g, view.fg.b, 0.16)

        Behavior on opacity {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: 260
                easing.type: Easing.OutBack
                easing.overshoot: 1.5
            }
        }
        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }
        Behavior on border.color {
            ColorAnimation {
                duration: 160
            }
        }

        Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -1
            text: "\uf0c6"
            font.family: view.fontFamily
            font.pixelSize: 13
            renderType: Text.QtRendering
            color: clip.lit ? view.fg : view.fgAlt
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.rightMargin: -1
            anchors.topMargin: -1
            width: 13
            height: 13
            radius: 6.5
            antialiasing: true
            visible: view.shelfCount > 0
            color: view.accent

            Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: view.shelfCount > 9 ? "9+" : view.shelfCount
                font.family: view.fontFamily
                font.pixelSize: 8
                font.weight: Font.ExtraBold
                color: view.bg
            }
        }

        MouseArea {
            id: shelfPress
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.shelfToggled()
        }
    }

    Satellite {
        id: satellite

        anchors.verticalCenter: parent.verticalCenter
        bubble: view.shelfShape || view.shelfMoving ? null : (scene.bubble || null)
        palette: view.palette
        restX: pill.x + pill.width + 6
        mergeX: pill.x + pill.width - 26
        merging: view.mergeActive
        onActivated: half => view.bubbleActivated(half)
        onHoveredChanged: view.bubbleHovered = hovered
    }

    Connections {
        function onSceneChanged() {
            var ev = view.scene.event || null;
            var key = ev ? (ev.id || "") + "|" + (ev.kind || "") : "";
            if (key === view.lastEventKey)
                return ;

            view.lastEventKey = key;
            if (!ev)
                return ;

            if (ev.kind === "glance")
                pulseAnim.restart();
        }

        function onMainProviderChanged() {
            var provider = view.mainProvider;
            var previous = view.lastMainProvider;
            view.lastMainProvider = provider;
            if (!previous || !provider || previous === provider)
                return ;

            if (!view.scene.bubble)
                return ;

            view.swapMerge = true;
            swapMergeTimer.restart();
        }

        target: view
    }

}
