import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire

ShellRoot {
    PanelWindow {
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        color: "transparent"

        Image {
            anchors.fill: parent
            source: "assets/wallpaper.png"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
    }

    PanelWindow {
        id: bar

        // request an alpha-capable surface so the translucent color
        // below actually composites instead of falling back opaque
        surfaceFormat.opaque: false

        anchors {
            top: true
            left: true
            right: true
        }

        implicitHeight: 32
        color: "#e6000000"
        exclusiveZone: implicitHeight

        // appIds in the order the user dragged them into; apps not
        // listed here follow in order of first appearance
        property var taskOrder: []

        // windows grouped by app, sorted by taskOrder
        readonly property var taskGroups: {
            const groups = [];
            const byApp = {};
            for (const w of ToplevelManager.toplevels.values) {
                let g = byApp[w.appId];
                if (!g) {
                    g = { appId: w.appId, windows: [] };
                    byApp[w.appId] = g;
                    groups.push(g);
                }
                g.windows.push(w);
            }
            // explicit sort key so we don't rely on sort() being stable
            const order = bar.taskOrder;
            groups.forEach((g, i) => {
                const k = order.indexOf(g.appId);
                g.key = k < 0 ? order.length + i : k;
            });
            return groups.sort((a, b) => a.key - b.key);
        }

        function iconFor(appId) {
            const entry = DesktopEntries.heuristicLookup(appId);
            if (entry && entry.icon)
                return Quickshell.iconPath(entry.icon);
            return Quickshell.iconPath(appId, "application-x-executable");
        }

        // drag-to-reorder state: the model is a plain JS array, so any
        // reorder recreates every delegate (and would kill the pressed
        // MouseArea mid-drag). The order is therefore only applied on
        // release; while dragging we just draw a ghost + drop marker.
        property string dragAppId: ""
        property int dropSlot: -1
        property real dragX: 0

        function dropTask() {
            const appId = bar.dragAppId;
            const slot = bar.dropSlot;
            bar.dragAppId = "";
            bar.dropSlot = -1;
            if (appId === "" || slot < 0)
                return;
            const ids = bar.taskGroups.map(g => g.appId);
            const from = ids.indexOf(appId);
            if (from < 0)
                return;
            ids.splice(from, 1);
            ids.splice(slot > from ? slot - 1 : slot, 0, appId);
            bar.taskOrder = ids;
        }

        // faint glass edge along the bottom of the bar
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 1
            color: "#26ffffff"
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            Text {
                text: "labwc"
                leftPadding: 12
                rightPadding: 12
                color: "#ffffff"
                font.family: "CommitMono Nerd Font Mono"
                font.pixelSize: 14
                font.bold: true
            }

            Rectangle {
                width: 1
                Layout.fillHeight: true
                color: "#26ffffff"
            }

            RowLayout {
                id: taskRow
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // insertion index (0..count) for a pointer at x, in
                // taskRow coordinates: past the midpoint of a box means
                // "after it"
                function slotAt(x) {
                    let slot = 0;
                    for (let i = 0; i < taskRepeater.count; i++) {
                        const it = taskRepeater.itemAt(i);
                        if (x > it.x + it.width / 2)
                            slot = i + 1;
                    }
                    return slot;
                }

                // x of a drop slot, in taskRow coordinates
                function slotX(slot) {
                    const n = taskRepeater.count;
                    if (n === 0 || slot < 0)
                        return 0;
                    if (slot < n)
                        return taskRepeater.itemAt(slot).x;
                    const last = taskRepeater.itemAt(n - 1);
                    return last.x + last.width;
                }

                Repeater {
                    id: taskRepeater
                    model: bar.taskGroups

                    // one button per app: solid white, edge-to-edge
                    // full-height highlight when any of its windows is
                    // focused, with a window count in the corner
                    delegate: Rectangle {
                        id: task
                        required property var modelData

                        readonly property var windows: modelData.windows
                        // read .activated on every window so the binding
                        // re-evaluates when focus moves between them
                        readonly property var focused: windows.find(w => w.activated) ?? null
                        readonly property bool active: focused !== null

                        Layout.fillHeight: true
                        implicitWidth: 36
                        color: active ? "#ffffff" : "transparent"
                        border.width: 1
                        border.color: active ? "#ffffff" : "#26ffffff"
                        opacity: bar.dragAppId === modelData.appId ? 0.3 : 1

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 16
                            source: {
                                // DesktopEntries scans .desktop files asynchronously and
                                // heuristicLookup() is a method (no binding dependency), so
                                // read the list here to re-evaluate once the scan finishes.
                                DesktopEntries.applications.values;
                                return bar.iconFor(task.modelData.appId);
                            }
                        }

                        Text {
                            anchors {
                                right: parent.right
                                bottom: parent.bottom
                                rightMargin: 3
                                bottomMargin: 1
                            }
                            visible: task.windows.length > 1
                            text: task.windows.length
                            color: task.active ? "#000000" : "#ffffff"
                            font.family: "CommitMono Nerd Font Mono"
                            font.pixelSize: 9
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton

                            property real pressX: 0
                            // left-button drag past the threshold; stays
                            // set until the next press so onClicked can
                            // tell a drop apart from a click
                            property bool dragging: false

                            onPressed: mouse => {
                                pressX = mouse.x;
                                dragging = false;
                            }
                            onPositionChanged: mouse => {
                                if (!(mouse.buttons & Qt.LeftButton))
                                    return;
                                if (!dragging) {
                                    if (Math.abs(mouse.x - pressX) < 8)
                                        return;
                                    dragging = true;
                                    bar.dragAppId = task.modelData.appId;
                                }
                                const x = mapToItem(taskRow, mouse.x, 0).x;
                                bar.dragX = x;
                                bar.dropSlot = taskRow.slotAt(x);
                            }
                            onReleased: if (dragging) bar.dropTask()
                            onCanceled: if (dragging) bar.dropTask()

                            onClicked: mouse => {
                                if (dragging)
                                    return;
                                const wins = task.windows;
                                const target = task.focused ?? wins[0];
                                if (mouse.button === Qt.RightButton) {
                                    taskMenu.open(task);
                                } else if (task.focused) {
                                    // already focused: cycle to the next window
                                    wins[(wins.indexOf(task.focused) + 1) % wins.length].activate();
                                } else {
                                    target.activate();
                                }
                            }
                        }
                    }
                }

                // Spacer: the fixed-width task boxes cap this layout's
                // maximum width, which would block fillWidth. This lets
                // the section grow while the boxes stay packed left.
                Item { Layout.fillWidth: true }
            }

            // Separator + tray only exist while there are tray items;
            // otherwise the margins alone leave an empty bordered box
            // next to the clock.
            Rectangle {
                width: 1
                Layout.fillHeight: true
                color: "#26ffffff"
                visible: tray.visible
            }

            RowLayout {
                id: tray
                spacing: 10
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                visible: SystemTray.items.values.length > 0
                // A nested Layout defaults to fillWidth: true. With no
                // windows open the taskbar's implicit width is 0, so the
                // tray would win the spare space and the taskbar would
                // collapse to a small empty bordered box.
                Layout.fillWidth: false

                Repeater {
                    model: SystemTray.items

                    delegate: IconImage {
                        required property var modelData

                        implicitSize: 16
                        // SystemTrayItem.icon is already a full image URL
                        // (e.g. image://qspixmap/...); don't wrap it in iconPath()
                        source: modelData.icon

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    parent.modelData.secondaryActivate();
                                else
                                    parent.modelData.activate();
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: 1
                Layout.fillHeight: true
                color: "#26ffffff"
            }

            // Volume: icon + percent for the default sink. Scroll to
            // adjust, middle-click to mute, click to toggle pavucontrol
            // (themed by gtk-4.0/gtk.css).
            Item {
                id: volume
                Layout.fillHeight: true
                implicitWidth: volumeText.implicitWidth

                readonly property var sink: Pipewire.defaultAudioSink
                readonly property bool ready: sink !== null && sink.audio !== null
                readonly property real level: ready ? sink.audio.volume : 0
                readonly property bool muted: ready ? sink.audio.muted : true

                // sink properties only update while the node is tracked
                PwObjectTracker { objects: volume.sink ? [volume.sink] : [] }

                function setLevel(v) {
                    if (!ready)
                        return;
                    sink.audio.volume = Math.max(0, Math.min(1, v));
                }

                function toggleMute() {
                    if (ready)
                        sink.audio.muted = !sink.audio.muted;
                }

                // Nerd Font (Material Design) volume glyphs
                readonly property string icon: {
                    if (!ready || muted || level === 0)
                        return "\u{f0581}";
                    if (level < 0.34)
                        return "\u{f057f}";
                    if (level < 0.67)
                        return "\u{f0580}";
                    return "\u{f057e}";
                }

                Text {
                    id: volumeText
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 12
                    rightPadding: 12
                    text: volume.icon + " " + (volume.ready ? Math.round(volume.level * 100) + "%" : "--")
                    color: volume.muted ? "#80ffffff" : "#ffffff"
                    font.family: "CommitMono Nerd Font Mono"
                    font.pixelSize: 14
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton)
                            volume.toggleMute();
                        else
                            Quickshell.execDetached(["sh", "-c", "pkill -x pavucontrol || exec pavucontrol"]);
                    }
                    onWheel: wheel => {
                        volume.setLevel(volume.level + (wheel.angleDelta.y > 0 ? 0.05 : -0.05));
                    }
                }
            }

            Rectangle {
                width: 1
                Layout.fillHeight: true
                color: "#26ffffff"
            }

            Text {
                text: clock.date.toLocaleString(Qt.locale(), "ddd d MMM  hh:mm:ss")
                leftPadding: 12
                rightPadding: 12
                color: "#ffffff"
                font.family: "CommitMono Nerd Font Mono"
                font.pixelSize: 14

                SystemClock {
                    id: clock
                    precision: SystemClock.Seconds
                }
            }
        }

        // Drag feedback: a drop marker at the target slot and a ghost
        // of the dragged task following the pointer. Both live outside
        // the RowLayout so they aren't laid out as tasks.
        Rectangle {
            visible: bar.dragAppId !== ""
            width: 2
            height: parent.height
            color: "#ffffff"
            x: {
                const slot = bar.dropSlot;
                bar.taskGroups; // re-evaluate after delegates are rebuilt
                return taskRow.mapToItem(null, taskRow.slotX(slot), 0).x - 1;
            }
        }

        Rectangle {
            visible: bar.dragAppId !== ""
            width: 36
            height: parent.height
            x: taskRow.mapToItem(null, bar.dragX, 0).x - width / 2
            color: "#40ffffff"
            border.width: 1
            border.color: "#ffffff"

            IconImage {
                anchors.centerIn: parent
                implicitSize: 16
                source: bar.dragAppId !== "" ? bar.iconFor(bar.dragAppId) : ""
            }
        }

        // Right-click menu for a task group: one shared popup that is
        // re-anchored under whichever task opened it.
        PopupWindow {
            id: taskMenu

            // the task delegate this menu was opened from
            property var task: null
            readonly property var windows: task ? task.windows : []
            // window the actions apply to: the focused one, else the first
            readonly property var target: task ? (task.focused ?? windows[0]) : null

            function open(t) {
                task = t;
                anchor.item = t;
                visible = true;
            }

            function act(fn) {
                visible = false;
                fn();
            }

            anchor.window: bar
            // hang off the task's bottom-left corner, extending down-right
            anchor.edges: Edges.Bottom | Edges.Left
            anchor.gravity: Edges.Bottom | Edges.Right
            surfaceFormat.opaque: false
            color: "transparent"
            // xdg popup grab: clicking anywhere outside dismisses the menu
            grabFocus: true
            visible: false
            onVisibleChanged: if (!visible) task = null

            implicitWidth: 220
            implicitHeight: menuColumn.implicitHeight + 2

            Rectangle {
                anchors.fill: parent
                color: "#e6000000"
                border.width: 1
                border.color: "#26ffffff"

                ColumnLayout {
                    id: menuColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 1
                    }
                    spacing: 0

                    // one row per window when the group has several;
                    // clicking a row focuses that window
                    Repeater {
                        model: taskMenu.windows.length > 1 ? taskMenu.windows : []

                        delegate: MenuRow {
                            required property var modelData
                            label: modelData.title
                            highlighted: modelData.activated
                            onTriggered: taskMenu.act(() => modelData.activate())
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: "#26ffffff"
                        visible: taskMenu.windows.length > 1
                    }

                    MenuRow {
                        label: taskMenu.target?.minimized ? "Restore" : "Minimize"
                        onTriggered: taskMenu.act(() => {
                            if (taskMenu.target.minimized)
                                taskMenu.target.activate();
                            else
                                taskMenu.target.minimized = true;
                        })
                    }

                    MenuRow {
                        label: taskMenu.target?.maximized ? "Unmaximize" : "Maximize"
                        onTriggered: taskMenu.act(() => {
                            taskMenu.target.maximized = !taskMenu.target.maximized;
                        })
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: "#26ffffff"
                    }

                    MenuRow {
                        label: "Close"
                        onTriggered: taskMenu.act(() => taskMenu.target.close())
                    }

                    MenuRow {
                        label: "Close all"
                        visible: taskMenu.windows.length > 1
                        onTriggered: taskMenu.act(() => {
                            for (const w of taskMenu.windows)
                                w.close();
                        })
                    }
                }
            }
        }
    }

    // A menu entry: white-on-black, inverts on hover like an active task.
    component MenuRow: Rectangle {
        id: row
        property string label
        property bool highlighted: false
        signal triggered()

        Layout.fillWidth: true
        implicitHeight: 28
        color: rowMouse.containsMouse ? "#ffffff" : "transparent"

        Text {
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 12
                rightMargin: 12
            }
            text: row.label
            elide: Text.ElideRight
            color: rowMouse.containsMouse ? "#000000" : "#ffffff"
            font.family: "CommitMono Nerd Font Mono"
            font.pixelSize: 12
            font.bold: row.highlighted
        }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: row.triggered()
        }
    }
}
