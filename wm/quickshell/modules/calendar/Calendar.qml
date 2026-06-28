import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../.." as Root

Scope {
    id: calendarPanel

    property bool panelVisible: false
    property bool _showing: false
    property bool _panelOpen: false

    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()

    onPanelVisibleChanged: {
        if (panelVisible) {
            _showing = true
            var now = new Date()
            viewYear = now.getFullYear()
            viewMonth = now.getMonth()
        } else {
            _panelOpen = false
        }
    }

    function prevMonth() {
        if (viewMonth === 0) { viewMonth = 11; viewYear-- }
        else viewMonth--
    }

    function nextMonth() {
        if (viewMonth === 11) { viewMonth = 0; viewYear++ }
        else viewMonth++
    }

    function daysInMonth(year, month) {
        return new Date(year, month + 1, 0).getDate()
    }

    function firstDayOfWeek(year, month) {
        var d = new Date(year, month, 1).getDay()
        return d === 0 ? 6 : d - 1
    }

    function buildGrid() {
        var cells = []
        var total = daysInMonth(viewYear, viewMonth)
        var offset = firstDayOfWeek(viewYear, viewMonth)
        var prevTotal = daysInMonth(viewYear, viewMonth === 0 ? 11 : viewMonth - 1)

        for (var i = 0; i < offset; i++)
            cells.push({ day: prevTotal - offset + 1 + i, current: false })
        for (var d = 1; d <= total; d++)
            cells.push({ day: d, current: true })
        while (cells.length < 42)
            cells.push({ day: cells.length - offset - total + 1, current: false })
        return cells
    }

    property var gridCells: buildGrid()
    onViewYearChanged: gridCells = buildGrid()
    onViewMonthChanged: gridCells = buildGrid()

    IpcHandler {
        target: "calendar"
        function toggle(): void { calendarPanel.panelVisible = !calendarPanel.panelVisible }
        function show(): void { calendarPanel.panelVisible = true }
        function hide(): void { calendarPanel.panelVisible = false }
    }

    Loader {
        active: calendarPanel._showing

        sourceComponent: PanelWindow {
            id: panelWindow
            visible: true

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore

            WlrLayershell.namespace: "quickshell:calendar"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Component.onCompleted: openDelayTimer.start()

            Timer {
                id: openDelayTimer
                interval: 16
                repeat: false
                onTriggered: if (calendarPanel.panelVisible) calendarPanel._panelOpen = true
            }

            Shortcut {
                sequence: "Escape"
                onActivated: calendarPanel.panelVisible = false
            }

            MouseArea {
                anchors.fill: parent
                onClicked: calendarPanel.panelVisible = false
            }

            Item {
                id: panelClip
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Root.Theme.shelfHeight
                clip: true

                Rectangle {
                    id: panel

                    width: 340
                    height: contentCol.implicitHeight + 40

                    anchors.right: parent.right
                    anchors.rightMargin: Root.Theme.spacingSmall

                    states: [
                        State {
                            name: "visible"
                            when: calendarPanel._panelOpen
                            PropertyChanges {
                                target: panel
                                y: panelClip.height - panel.height - Root.Theme.spacingSmall
                                opacity: 1
                            }
                        },
                        State {
                            name: "hidden"
                            when: !calendarPanel._panelOpen
                            PropertyChanges {
                                target: panel
                                y: panelClip.height
                                opacity: 0
                            }
                        }
                    ]

                    transitions: [
                        Transition {
                            from: "hidden"; to: "visible"
                            ParallelAnimation {
                                NumberAnimation { property: "y"; duration: Root.Theme.animDuration; easing.type: Easing.OutCubic }
                                NumberAnimation { property: "opacity"; duration: Root.Theme.animDuration; easing.type: Easing.OutCubic }
                            }
                        },
                        Transition {
                            from: "visible"; to: "hidden"
                            SequentialAnimation {
                                ParallelAnimation {
                                    NumberAnimation { property: "y"; duration: Root.Theme.animDuration; easing.type: Easing.InCubic }
                                    NumberAnimation { property: "opacity"; duration: Root.Theme.animDuration; easing.type: Easing.InCubic }
                                }
                                ScriptAction { script: calendarPanel._showing = false }
                            }
                        }
                    ]

                    radius: Root.Theme.panelRadius
                    color: Qt.rgba(Root.Theme.panelBg.r, Root.Theme.panelBg.g, Root.Theme.panelBg.b, 0.95)
                    border.width: 1
                    border.color: Qt.rgba(Root.Theme.panelBorder.r, Root.Theme.panelBorder.g, Root.Theme.panelBorder.b, 0.5)

                    MouseArea { anchors.fill: parent }

                    ColumnLayout {
                        id: contentCol
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: prevMouse.containsMouse ? Root.Theme.surfaceContainerHigh : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰁍"
                                    font.family: Root.Theme.fontFamily
                                    font.pixelSize: 14
                                    color: Root.Theme.textPrimary
                                }
                                MouseArea {
                                    id: prevMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: calendarPanel.prevMonth()
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: {
                                    var months = ["January","February","March","April","May","June",
                                                  "July","August","September","October","November","December"]
                                    return months[calendarPanel.viewMonth] + " " + calendarPanel.viewYear
                                }
                                font.family: Root.Theme.fontFamily
                                font.pixelSize: 16
                                font.bold: true
                                color: Root.Theme.textPrimary
                            }

                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: nextMouse.containsMouse ? Root.Theme.surfaceContainerHigh : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰁔"
                                    font.family: Root.Theme.fontFamily
                                    font.pixelSize: 14
                                    color: Root.Theme.textPrimary
                                }
                                MouseArea {
                                    id: nextMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: calendarPanel.nextMonth()
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true
                            columns: 7
                            rowSpacing: 4
                            columnSpacing: 0

                            Repeater {
                                model: ["Mo","Tu","We","Th","Fr","Sa","Su"]
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData
                                    font.family: Root.Theme.fontFamily
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Root.Theme.textSecondary
                                }
                            }

                            Repeater {
                                model: calendarPanel.gridCells

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36

                                    property bool isToday: {
                                        var now = new Date()
                                        return modelData.current &&
                                               modelData.day === now.getDate() &&
                                               calendarPanel.viewMonth === now.getMonth() &&
                                               calendarPanel.viewYear === now.getFullYear()
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 32; height: 32; radius: 16
                                        color: isToday ? Root.Theme.primary : "transparent"
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.day
                                        font.family: Root.Theme.fontFamily
                                        font.pixelSize: 13
                                        color: isToday ? Root.Theme.panelBg :
                                               (modelData.current ? Root.Theme.textPrimary :
                                                Qt.rgba(Root.Theme.textSecondary.r,
                                                        Root.Theme.textSecondary.g,
                                                        Root.Theme.textSecondary.b, 0.4))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
