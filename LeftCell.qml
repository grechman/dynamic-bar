import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
    id: cell

    property var palette: ({
    })

    readonly property color fg: palette.fg || "#c5c9c5"
    readonly property color fgAlt: palette.fg_alt || "#a6a69c"
    readonly property color muted: palette.muted || "#625e5a"
    readonly property color accent: palette.accent || "#658594"

    readonly property int rooms: 5
    readonly property int slot: 26

    implicitWidth: rooms * slot
    implicitHeight: 27

    Component.onCompleted: Hyprland.refreshWorkspaces()

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name.indexOf("window") < 0 && event.name.indexOf("workspace") < 0)
                return;
            Hyprland.refreshWorkspaces();
            settle.restart();
        }
    }

    Timer {
        id: settle

        interval: 160
        repeat: false
        onTriggered: clients.running = true
    }

    Process {
        id: clients

        command: ["hyprctl", "clients", "-j"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var list = JSON.parse(text);
                    var map = ({});
                    for (var i = 0; i < list.length; i++) {
                        var room = String(list[i].workspace ? list[i].workspace.name : "");
                        if (!map[room])
                            map[room] = [];
                        map[room].push(list[i]["class"] || "");
                    }
                    cell.occupancy = map;
                } catch (e) {}
            }
        }
    }

    property var occupancy: ({
    })

    function windowsOf(room) {
        var live = occupancy[String(room)];
        return live ? live : [];
    }

    readonly property int here: {
        var focused = Hyprland.focusedWorkspace;
        var name = focused ? parseInt(focused.name) : 1;
        return isNaN(name) ? 1 : name;
    }

    Repeater {
        model: cell.rooms

        Item {
            id: room

            required property int index

            readonly property int number: index + 1
            readonly property bool active: cell.here === number
            readonly property int load: cell.windowsOf(number).length

            x: index * cell.slot
            width: cell.slot
            height: 27
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                width: 11
                height: room.load === 0 ? 3 : 8 + Math.min(2, room.load - 1) * 4 + (room.active ? 6 : 0)
                radius: 2
                antialiasing: true
                color: room.active ? cell.fg : Qt.rgba(cell.fgAlt.r, cell.fgAlt.g, cell.fgAlt.b, room.load ? 0.42 : 0.26)

                Behavior on height {
                    NumberAnimation {
                        duration: 280
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }

                Behavior on color {
                    ColorAnimation {
                        duration: 220
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + room.number + "\" })")
            }
        }
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: clients.running = true
    }
}
