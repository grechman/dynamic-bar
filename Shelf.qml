import QtQuick
import Quickshell.Io

Item {
    id: root
    readonly property string fontFamily: palette.font || "JetBrainsMono Nerd Font"

    property var shelf: null
    property var palette: ({})
    property bool open: false
    property string naming: shelf && shelf.ask ? shelf.ask : ""

    signal copyItem(string name)
    signal openItem(string name)
    signal dropItem(string name)
    signal rename(string name, string title)
    signal keepName(string name)
    signal dismiss

    property var dropped: ({})

    FileView {
        id: noteBody

        blockLoading: true
    }

    function noteText(item) {
        if (noteBody.path !== item.path)
            noteBody.path = item.path;
        var body = noteBody.text();
        return body.length ? body : item.text;
    }

    readonly property var items: {
        var raw = shelf && shelf.items ? shelf.items : [];
        var out = [];
        for (var i = 0; i < raw.length; i++)
            if (!dropped[raw[i].name])
                out.push(raw[i]);
        return out;
    }

    onShelfChanged: {
        var raw = shelf && shelf.items ? shelf.items : [];
        var live = {};
        for (var i = 0; i < raw.length; i++)
            live[raw[i].name] = true;
        var kept = {};
        var names = Object.keys(dropped);
        for (var k = 0; k < names.length; k++)
            if (live[names[k]])
                kept[names[k]] = true;
        dropped = kept;
    }

    function discard(name) {
        dropItem(name);
        forget(name);
    }

    function forget(name) {
        var next = {};
        var names = Object.keys(dropped);
        for (var i = 0; i < names.length; i++)
            next[names[i]] = true;
        next[name] = true;
        dropped = next;
    }
    readonly property color bg: palette.bg || "#181616"
    readonly property color bgAlt: palette.bg_alt || "#282727"
    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color accent: palette.accent || "#658594"
    readonly property color hover: palette.hover || "#a292a3"
    readonly property color crit: palette.crit || "#c4746e"

    readonly property int columns: 6
    readonly property int tile: 92
    readonly property int gap: 10
    readonly property int pad: 16
    readonly property int rows: Math.max(1, Math.min(3, Math.ceil(items.length / columns)))

    readonly property int span: Math.max(3, Math.min(columns, items.length))

    implicitWidth: columns * tile + (columns - 1) * gap
    implicitHeight: rows * tile + (rows - 1) * gap

    Flickable {
        anchors.fill: parent
        contentHeight: grid.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Grid {
            id: grid
            columns: root.columns
            spacing: root.gap

            Repeater {
                model: root.items

                Rectangle {
                    id: card

                    readonly property bool image: modelData.kind === "image"
                    readonly property bool note: modelData.kind === "text"

                    width: root.tile
                    height: root.tile
                    radius: 14
                    antialiasing: true
                    color: touch.containsMouse ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                    border.width: 1
                    border.color: touch.containsMouse ? Qt.rgba(root.hover.r, root.hover.g, root.hover.b, 0.55) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.08)

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

                    Image {
                        anchors.fill: parent
                        anchors.margins: 1
                        visible: card.image && status === Image.Ready
                        source: modelData.thumb ? "file://" + modelData.thumb : ""
                        sourceSize.width: 128
                        sourceSize.height: 128
                        smooth: true
                        mipmap: true
                        opacity: 0.92
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.fill: parent
                        anchors.margins: 9
                        visible: card.note
                        text: modelData.preview
                        color: root.fgAlt
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: 6
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: card.image && !modelData.thumb
                        text: "\uf03e"
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: 26
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: !card.image && !card.note
                        text: "\uf15b"
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: 26
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 1
                        height: 20
                        radius: 13
                        visible: !card.note
                        color: Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.72)

                        Text {
                            textFormat: Text.PlainText
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            verticalAlignment: Text.AlignVCenter
                            text: modelData.name
                            color: root.fgAlt
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideMiddle
                        }
                    }

                    Rectangle {
                        z: 2
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 4
                        width: 17
                        height: 17
                        radius: 8.5
                        antialiasing: true
                        visible: touch.containsMouse || kill.containsMouse
                        color: kill.containsMouse ? root.crit : Qt.rgba(root.bg.r, root.bg.g, root.bg.b, 0.85)

                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "\uf00d"
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            color: kill.containsMouse ? root.bg : root.fgAlt
                        }

                        MouseArea {
                            id: kill
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.discard(modelData.name)
                        }
                    }

                    Drag.active: touch.hauling
                    Drag.dragType: Drag.Automatic
                    Drag.supportedActions: Qt.CopyAction
                    Drag.mimeData: card.note && modelData.text ? ({
                            "text/plain": root.noteText(modelData)
                        }) : ({
                            "text/uri-list": "file://" + modelData.path
                        })

                    MouseArea {
                        id: touch

                        property bool hauling: false
                        property real originX: 0
                        property real originY: 0

                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: hauling ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                        onPressed: mouse => {
                            originX = mouse.x;
                            originY = mouse.y;
                            if (card.note)
                                noteBody.path = modelData.path;
                        }
                        onPositionChanged: mouse => {
                            if (!hauling && pressed && mouse.buttons & Qt.LeftButton && Math.hypot(mouse.x - originX, mouse.y - originY) > 8)
                                hauling = true;
                        }
                        onReleased: hauling = false
                        onCanceled: hauling = false
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                root.openItem(modelData.name);
                            else
                                root.copyItem(modelData.name);
                        }
                    }
                }
            }
        }
    }

    Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        visible: root.items.length === 0
        text: "drop a screenshot or some text here"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 12
    }
}
