import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: cell

    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"
    property var palette: ({
    })
    property string pluginDir: ""
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
    readonly property color claudeMark: palette.claude || "#D97757"

    readonly property int panelWidth: 440
    readonly property int panelHeight: 46 + panel.implicitHeight + 20
    readonly property int markSlot: 25
    readonly property int windowSlot: 47
    readonly property int groupGap: 20
    property int openHeight: 29

    property var providers: []
    property var pinned: []
    property var errors: []
    property var block: null
    property var daily: []
    property double stamp: 0

    readonly property var shown: {
        var out = [];
        for (var i = 0; i < pinned.length && out.length < 2; i++)
            for (var j = 0; j < providers.length; j++)
                if (providers[j].id === pinned[i] && providers[j].windows.length)
                    out.push(providers[j]);
        return out;
    }

    function groupWidth(provider) {
        return markSlot + provider.windows.length * windowSlot - 7;
    }

    readonly property int groupsWidth: {
        var total = 0;
        for (var i = 0; i < shown.length; i++)
            total += groupWidth(shown[i]);
        return total;
    }

    readonly property int collapsedWidth: shown.length ? 32 + groupsWidth + groupGap * (shown.length - 1) : 120

    function packedX(index) {
        var x = 0;
        for (var i = 0; i < index; i++)
            x += groupWidth(shown[i]) + groupGap;
        return x;
    }

    function tintOf(slice) {
        if (!slice || slice.pct === null || slice.pct === undefined)
            return fgAlt;
        var tone = slice.state === "crit" ? crit : slice.state === "warn" ? warn : ok;
        return slice.stale ? Qt.rgba(tone.r, tone.g, tone.b, 0.55) : tone;
    }

    readonly property string blockCost: {
        if (!block)
            return "--";
        return "$" + (block.cost >= 100 ? Math.round(block.cost) : block.cost.toFixed(1));
    }

    implicitWidth: shape ? panelWidth : collapsedWidth
    implicitHeight: shape ? openHeight : 29

    function mix(base, tint, amount) {
        return Qt.rgba(base.r + (tint.r - base.r) * amount, base.g + (tint.g - base.g) * amount, base.b + (tint.b - base.b) * amount, 1);
    }

    property real glass: shape ? 1 : 0
    readonly property color glassTint: mix(bgAlt, bg, glass * 0.55)
    property bool shape: false
    property bool content: false

    Behavior on glass {
        NumberAnimation {
            duration: cell.shape ? 320 : 360
            easing.type: Easing.InOutCubic
        }
    }

    onPanelHeightChanged: {
        if (open)
            openHeight = panelHeight;
    }

    onOpenChanged: {
        if (open) {
            fold.stop();
            openHeight = panelHeight;
            shape = true;
            reveal.restart();
            probe.running = true;
            spend.running = true;
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

    Process {
        id: probe

        command: ["python3", cell.pluginDir + "/usage.py"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var payload = JSON.parse(text);
                    cell.providers = payload.providers || [];
                    cell.pinned = payload.pinned || [];
                    cell.errors = payload.errors || [];
                    cell.stamp = Date.now();
                } catch (e) {
                }
            }
        }
    }

    Process {
        id: spend

        command: ["python3", cell.pluginDir + "/spend.py"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var payload = JSON.parse(text);
                    cell.daily = payload.daily || [];
                    cell.block = payload.block || null;
                } catch (e) {
                }
            }
        }
    }

    Timer {
        interval: 120000
        running: true
        repeat: true
        onTriggered: {
            probe.running = true;
            spend.running = true;
        }
    }

    component Mark: Item {
        id: mark

        property var provider: null
        readonly property string pid: provider ? provider.id : ""

        width: 18
        height: 22

        Text {
            anchors.centerIn: parent
            visible: mark.pid === "claude"
            text: "\ue001"
            font.family: "Actions Island"
            font.pixelSize: 19
            font.weight: Font.ExtraBold
            renderType: Text.QtRendering
            color: cell.claudeMark
        }

        Image {
            anchors.centerIn: parent
            visible: mark.pid === "codex"
            width: 14
            height: 14
            opacity: 0.78
            sourceSize.width: 32
            sourceSize.height: 32
            smooth: true
            source: mark.pid === "codex" ? "file://" + cell.pluginDir + "/assets/openai-mark.svg" : ""
        }

        Rectangle {
            anchors.centerIn: parent
            visible: mark.pid !== "claude" && mark.pid !== "codex"
            width: 17
            height: 17
            radius: 5
            antialiasing: true
            color: Qt.rgba(cell.fg.r, cell.fg.g, cell.fg.b, 0.14)

            Text {
                anchors.centerIn: parent
                text: mark.provider ? (mark.provider.name || mark.pid).substring(0, 1).toUpperCase() : ""
                font.family: cell.fontFamily
                font.pixelSize: 11
                font.weight: Font.Bold
                color: cell.fg
            }
        }
    }

    Rectangle {
        id: pill

        anchors.left: parent.left
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

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            y: cell.shape ? 23 - height / 2 : (29 - height) / 2
            height: 22

            function slotX(index) {
                var near = cell.packedX(index);
                var count = Math.max(1, cell.shown.length);
                var far = width * (index + 0.5) / count - cell.groupWidth(cell.shown[index]) / 2;
                return near + (far - near) * cell.glass;
            }

            Behavior on y {
                NumberAnimation {
                    duration: cell.shape ? 320 : 360
                    easing.type: Easing.InOutCubic
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: cell.shown.length === 0
                text: cell.errors.length ? "usage unavailable" : "no usage"
                font.family: cell.fontFamily
                font.pixelSize: 12
                color: cell.fgAlt
            }

            Repeater {
                model: cell.shown

                Row {
                    id: group

                    required property var modelData
                    required property int index

                    x: glyphs.slotX(index)
                    anchors.verticalCenter: parent.verticalCenter
                    height: 22
                    spacing: 7

                    Mark {
                        anchors.verticalCenter: parent.verticalCenter
                        provider: group.modelData
                    }

                    Repeater {
                        model: group.modelData.windows

                        Row {
                            required property var modelData

                            anchors.verticalCenter: parent.verticalCenter
                            height: 22
                            spacing: 3

                            Text {
                                id: tagText

                                anchors.baseline: number.baseline
                                width: 15
                                text: parent.modelData.tag
                                font.family: cell.fontFamily
                                font.pixelSize: 11
                                color: cell.fgAlt
                            }

                            Text {
                                id: number

                                anchors.verticalCenter: parent.verticalCenter
                                width: 22
                                horizontalAlignment: Text.AlignHCenter
                                text: parent.modelData.pct === null || parent.modelData.pct === undefined ? "--" : parent.modelData.pct
                                font.family: cell.fontFamily
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                                color: cell.tintOf(parent.modelData)
                            }
                        }
                    }
                }
            }
        }

        UsagePanel {
            id: panel

            anchors.left: parent.left
            anchors.leftMargin: 24
            y: 46
            width: cell.panelWidth - 48
            opacity: cell.content ? 1 : 0
            visible: opacity > 0.01
            palette: cell.palette
            providers: cell.providers
            errors: cell.errors
            block: cell.block
            daily: cell.daily
            stamp: cell.stamp

            Behavior on opacity {
                NumberAnimation {
                    duration: cell.content ? 200 : 90
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            anchors.left: parent.left
            anchors.top: parent.top
            width: cell.shape ? cell.panelWidth : cell.collapsedWidth
            height: cell.shape ? 46 : 29
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cell.toggled()
        }
    }
}
