import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
    id: root

    property string omarchyPath: ""
    property var shell: null
    property var manifest: null
    property var barConfig: null
    property var barWidgetRegistry: null
    property var pluginRegistry: null
    property bool barHidden: false

    readonly property string home: Quickshell.env("HOME")
    readonly property string position: Quickshell.env("ISLAND_PREVIEW") === "1" ? "bottom" : "top"
    readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "").replace(/\/$/, "")

    IslandBar {
        position: root.position
        hidden: root.barHidden
        fontFamily: Style.font.family
    }

    property int crashes: 0
    property double daemonStarted: Date.now()

    Process {
        id: daemon

        command: ["python3", root.pluginDir + "/island.py"]
        running: true
        onExited: {
            if (Date.now() - root.daemonStarted > 60000)
                root.crashes = 0;
            else
                root.crashes += 1;
            if (root.crashes >= 8)
                return;
            relaunch.interval = Math.min(3000 * Math.pow(2, root.crashes), 300000);
            relaunch.restart();
        }
    }

    Timer {
        id: relaunch

        interval: 3000
        repeat: false
        onTriggered: {
            root.daemonStarted = Date.now();
            daemon.running = true;
        }
    }

    Process {
        id: hiddenProbe

        command: ["test", "-f", root.home + "/.local/state/omarchy/toggles/bar-off"]
        onExited: function (code) {
            root.barHidden = code === 0;
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: hiddenProbe.running = true
    }

    Component.onDestruction: daemon.running = false
}
