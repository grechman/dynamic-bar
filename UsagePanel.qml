import QtQuick

Item {
    id: root
    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var palette: ({
    })
    property var providers: []
    property var block: null
    property var errors: []
    property var daily: []
    property double stamp: 0
    property int span: 1

    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color accent: palette.accent || "#658594"
    readonly property color ok: palette.ok || "#87a987"
    readonly property color warn: palette.warn || "#c4b28a"
    readonly property color crit: palette.crit || "#c4746e"

    implicitWidth: 376
    implicitHeight: column.implicitHeight

    function tintFor(name) {
        return name === "crit" ? crit : name === "warn" ? warn : ok;
    }

    function tintOf(slice) {
        var tone = tintFor(slice.state);
        return slice.stale ? Qt.rgba(tone.r, tone.g, tone.b, 0.55) : tone;
    }

    function providerDetail(provider) {
        if (provider.error)
            return provider.error;
        var parts = [];
        if (provider.plan)
            parts.push(provider.plan);
        if (provider.stale && provider.windows.length)
            parts.push("stale");
        if (provider.source === "omarchy")
            parts.push("via omarchy");
        return parts.join("  ·  ");
    }

    function untilText(stamp) {
        if (!stamp)
            return "";
        var left = stamp * 1000 - clock.now;
        if (left <= 0)
            return "due";
        var mins = Math.round(left / 60000);
        if (mins < 60)
            return mins + "m";
        var hours = Math.floor(mins / 60);
        if (hours < 24)
            return hours + "h " + (mins % 60) + "m";
        return Math.floor(hours / 24) + "d " + (hours % 24) + "h";
    }

    function spanText(minutes) {
        if (!minutes || minutes <= 0)
            return "0m";
        var hours = Math.floor(minutes / 60);
        return hours > 0 ? hours + "h " + Math.round(minutes % 60) + "m" : Math.round(minutes) + "m";
    }

    function compact(count) {
        if (!count)
            return "0";
        if (count >= 1000000)
            return (count / 1000000).toFixed(1) + "M";
        if (count >= 1000)
            return Math.round(count / 1000) + "k";
        return String(count);
    }

    function windowStart(days) {
        var from = new Date();
        from.setDate(from.getDate() - (days - 1));
        return Qt.formatDateTime(from, "yyyy-MM-dd");
    }

    function periodSum(days, field) {
        var cut = windowStart(days);
        var total = 0;
        for (var i = 0; i < daily.length; i++) {
            var row = daily[i];
            var when = row.date || "";
            if (when >= cut)
                total += row[field] || 0;
        }
        return total;
    }

    function periodCost(days) {
        return periodSum(days, "cost");
    }

    function periodTokens(days) {
        return periodSum(days, "tokens");
    }

    function clockAt(seconds) {
        if (!seconds)
            return "";
        return Qt.formatDateTime(new Date(seconds * 1000), "HH:mm");
    }

    readonly property string freshness: {
        if (!stamp)
            return "no data yet";
        var mins = Math.floor((clock.now - stamp) / 60000);
        if (mins < 1)
            return "updated just now";
        if (mins < 60)
            return "updated " + mins + "m ago";
        return "updated " + Math.floor(mins / 60) + "h ago";
    }

    function money(value) {
        if (value === undefined || value === null)
            return "";
        return "$" + (value >= 100 ? Math.round(value) : value.toFixed(2));
    }

    QtObject {
        id: clock

        property double now: 0
    }

    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clock.now = Date.now()
    }

    readonly property real elapsedShare: {
        if (!block)
            return 0;
        var from = block.start * 1000;
        var to = block.end * 1000;
        if (!(to > from))
            return 0;
        return Math.max(0, Math.min(1, (clock.now - from) / (to - from)));
    }

    Column {
        id: column

        width: parent.width
        spacing: 0

        Repeater {
            model: root.providers

            Column {
                id: section

                required property var modelData

                width: column.width
                spacing: 0

                SysSection {
                    width: parent.width
                    palette: root.palette
                    label: section.modelData.name.toLowerCase()
                    detail: root.providerDetail(section.modelData)
                    toggled: !section.modelData.error
                    switchable: false
                }

                Repeater {
                    model: section.modelData.windows

                    Item {
                        id: row

                        required property var modelData

                        width: column.width
                        height: 34

                        Text {
                            textFormat: Text.PlainText
                            x: 10
                            y: 4
                            width: 108
                            elide: Text.ElideRight
                            text: row.modelData.name
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            color: row.modelData.stale ? root.fgAlt : root.fg
                        }

                        Text {
                            textFormat: Text.PlainText
                            x: 124
                            y: 4
                            width: 44
                            horizontalAlignment: Text.AlignRight
                            text: row.modelData.pct === null ? "--" : row.modelData.pct + "%"
                            font.family: root.fontFamily
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: row.modelData.pct === null ? root.fgAlt : root.tintOf(row.modelData)
                        }

                        Meter {
                            x: 178
                            y: 9
                            width: column.width - 178 - 68
                            level: (row.modelData.pct || 0) / 100
                            rail: root.muted
                            tint: root.tintOf(row.modelData)
                        }

                        Text {
                            textFormat: Text.PlainText
                            x: column.width - 62
                            y: 4
                            width: 52
                            horizontalAlignment: Text.AlignRight
                            text: root.untilText(row.modelData.reset)
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: root.fgAlt
                        }

                        Text {
                            textFormat: Text.PlainText
                            x: 10
                            y: 19
                            text: row.modelData.resets_available ? row.modelData.resets_available + " reset banked" : ""
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            color: root.accent
                        }
                    }
                }
            }
        }

        SysSection {
            width: parent.width
            palette: root.palette
            label: "no providers"
            detail: root.errors.length ? root.errors[0] : "sign in to claude, codex, gemini, kimi, glm, grok or copilot"
            switchable: false
            visible: root.providers.length === 0
            height: visible ? 36 : 0
        }

        SysSection {
            width: parent.width
            palette: root.palette
            label: "claude spend"
            detail: root.money(root.periodCost(root.span)) + "  ·  " + root.compact(root.periodTokens(root.span))
            switchable: false
        }

        Item {
            width: parent.width
            height: 34

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: [
                        {
                            "tag": "today",
                            "days": 1
                        },
                        {
                            "tag": "week",
                            "days": 7
                        },
                        {
                            "tag": "month",
                            "days": 30
                        }
                    ]

                    Rectangle {
                        required property var modelData

                        readonly property bool picked: root.span === modelData.days
                        width: 68
                        height: 24
                        radius: 8
                        antialiasing: true
                        color: picked ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, spanHit.containsMouse ? 0.12 : 0.05)

                        Behavior on color {
                            ColorAnimation {
                                duration: 140
                            }
                        }

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: parent.modelData.tag
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: parent.picked ? root.fg : root.muted
                        }

                        MouseArea {
                            id: spanHit

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.span = parent.modelData.days
                        }
                    }
                }
            }
        }

        SysSection {
            width: parent.width
            palette: root.palette
            label: "burn"
            detail: root.block ? root.clockAt(root.block.start) + " to " + root.clockAt(root.block.end) : "idle"
            switchable: false
        }

        Item {
            width: parent.width
            height: root.block ? 26 : 0
            clip: true

            Meter {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 20
                thickness: 6
                level: root.elapsedShare
                rail: root.muted
                tint: root.accent
            }
        }

        Repeater {
            model: root.block ? [
                {
                    "key": "spent so far",
                    "value": root.money(root.block.cost) + "  ·  " + root.compact(root.block.tokens)
                },
                {
                    "key": "rate",
                    "value": root.money(root.block.rate) + "/h"
                },
                {
                    "key": "at this rate",
                    "value": root.money(root.block.projected) + " by " + root.clockAt(root.block.end)
                }
            ] : []

            Item {
                required property var modelData

                width: column.width
                height: 26

                Text {
                    textFormat: Text.PlainText
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.key
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    color: root.muted
                }

                Text {
                    textFormat: Text.PlainText
                    x: parent.width - width - 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.modelData.value
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    color: root.fgAlt
                }
            }
        }

        Item {
            width: parent.width
            height: 26

            Text {
                textFormat: Text.PlainText
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                text: root.freshness
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.muted
            }
        }
    }
}
