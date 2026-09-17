import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray

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

        // windows grouped by app, in order of first appearance
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
            return groups;
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
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Repeater {
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

                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 16
                            source: {
                                // DesktopEntries scans .desktop files asynchronously and
                                // heuristicLookup() is a method (no binding dependency), so
                                // read the list here to re-evaluate once the scan finishes.
                                DesktopEntries.applications.values;
                                const appId = task.modelData.appId;
                                const entry = DesktopEntries.heuristicLookup(appId);
                                if (entry && entry.icon)
                                    return Quickshell.iconPath(entry.icon);
                                return Quickshell.iconPath(appId, "application-x-executable");
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
                            onClicked: mouse => {
                                const wins = task.windows;
                                const target = task.focused ?? wins[0];
                                if (mouse.button === Qt.RightButton) {
                                    target.close();
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
    }
}
