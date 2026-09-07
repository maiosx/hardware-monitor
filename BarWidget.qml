import QtQuick
import Quickshell
import Quickshell.Io

// Compact bar control for the Hardware Monitor Overlay.
// Shows "HW". Left-click opens/closes the fullscreen overlay.
// Dimmed when closed so the bar state is obvious at a glance — same
// convention as Wallpaper Blur's single-letter "B" widget.
Item {
  id: root

  // Injected by the Omarchy bar / plugin loader.
  property var bar: null
  property var shell: null
  property var manifest: null
  property var settings: null
  property string moduleName: "hwmonitor.overlay"

  property bool overlayOpen: false

  implicitWidth: 34
  implicitHeight: bar ? (bar.barSize || 26) : 26

  // Keep local state in sync with the panel's IpcHandler.
  Process {
    id: query
    command: ["omarchy-shell", "-q", "hwmonitor.overlay", "getVisible"]
    stdout: StdioCollector {
      onStreamFinished: {
        const t = text.trim().toLowerCase()
        if (t === "true" || t === "1") root.overlayOpen = true
        else if (t === "false" || t === "0") root.overlayOpen = false
      }
    }
  }

  Process {
    id: toggler
    command: ["omarchy-shell", "-q", "hwmonitor.overlay", "toggle"]
    onExited: Qt.callLater(() => { query.running = true })
  }

  Timer {
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: query.running = true
  }

  Rectangle {
    anchors.fill: parent
    radius: 6
    color: root.overlayOpen ? (bar && bar.accent ? bar.accent : "transparent") : "transparent"
    opacity: root.overlayOpen ? 0.22 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  Text {
    anchors.centerIn: parent
    text: "HW"
    color: bar && bar.foreground ? bar.foreground : "#e8e8e8"
    opacity: root.overlayOpen ? 1.0 : 0.45
    font.family: bar && bar.fontFamily ? bar.fontFamily : "sans-serif"
    font.pixelSize: 11
    font.bold: true
    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: toggler.running = true
  }
}
