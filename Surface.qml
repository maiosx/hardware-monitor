import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

// A fullscreen layer-shell overlay: a blurred copy of the current wallpaper
// (same technique as the Wallpaper Blur plugin's Surface.qml, borrowed
// wholesale) plus a dark scrim, with live CPU / GPU / memory / temperature
// drawn as centered dials on top.
//
// Unlike Wallpaper Blur this sits on the Overlay layer and takes keyboard
// and pointer focus while open — it is a toggled HUD, not a permanent
// desktop backdrop. Click anywhere, or press Escape, to dismiss it.
//
// Toggle from the bar HW widget or via IPC: hwmonitor.overlay toggle.
Item {
  id: root

  // Injected by the Omarchy shell when the plugin loads.
  property var shell: null
  property var manifest: null

  // ---- tuning knobs -------------------------------------------------
  // How strong the background blur looks. Same two knobs as Wallpaper Blur.
  property real blurAmount: 0.78
  property int blurRadiusPx: 110
  // Darkens the blurred wallpaper so the dials read clearly at a glance.
  property real scrimOpacity: 0.46

  property int warnPercent: 70
  property int criticalPercent: 90
  property int warnTempC: 75
  property int criticalTempC: 90

  // ---- state ----------------------------------------------------------

  // Runtime on/off. The bar widget and IPC flip this.
  property bool overlayVisible: false

  // Same dual-path resolution Wallpaper Blur uses — Omarchy has moved this
  // symlink before.
  property string wallpaperPath: ""

  Process {
    id: resolver
    command: ["bash", "-c",
      "for p in \"$HOME/.local/state/omarchy/current/background\" " +
      "\"$HOME/.config/omarchy/current/background\"; do " +
      "[ -e \"$p\" ] && readlink -f \"$p\" && exit 0; done"]
    stdout: SplitParser {
      onRead: data => {
        const p = data.trim()
        if (p.length > 0 && p !== root.wallpaperPath) root.wallpaperPath = p
      }
    }
  }

  // Only need the current wallpaper while the overlay can be seen, so the
  // poll only runs while open rather than ticking in the background forever.
  Timer {
    interval: 2000
    running: root.overlayVisible
    repeat: true
    triggeredOnStart: true
    onTriggered: resolver.running = true
  }

  // One shared sensor service for every screen — sampling is cheap kernel
  // file reads, so there is no reason to fork it per monitor.
  Service {
    id: hw
    active: root.overlayVisible
  }

  IpcHandler {
    target: "hwmonitor.overlay"

    function toggle(): void {
      root.overlayVisible = !root.overlayVisible
    }

    function enable(): void {
      root.overlayVisible = true
    }

    function disable(): void {
      root.overlayVisible = false
    }

    function getVisible(): bool {
      return root.overlayVisible
    }
  }

  // ---- derived readouts -------------------------------------------------

  readonly property real cpuFraction: hw.cpuPercent >= 0 ? hw.cpuPercent / 100 : -1
  readonly property real ramFraction: hw.memPercent >= 0 ? hw.memPercent / 100 : -1
  readonly property real gpuFraction: hw.hasGpu && hw.gpuPercent >= 0 ? hw.gpuPercent / 100 : -1
  // Temperature drawn on a 0..criticalTempC scale so the ring fills up as it
  // approaches the danger zone rather than a generic 0-100 scale.
  readonly property real tempFraction: hw.cpuTempC >= 0
    ? Math.max(0, Math.min(1, hw.cpuTempC / Math.max(1, root.criticalTempC))) : -1

  readonly property real cpuSeverity: Model.severity(hw.cpuPercent, root.warnPercent, root.criticalPercent)
  readonly property real ramSeverity: Model.severity(hw.memPercent, root.warnPercent, root.criticalPercent)
  readonly property real gpuSeverity: Model.severity(hw.gpuPercent, root.warnPercent, root.criticalPercent)
  readonly property real tempSeverity: Model.severity(hw.cpuTempC, root.warnTempC, root.criticalTempC)

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: surface
        required property var modelData

        screen: modelData
        visible: root.overlayVisible && root.wallpaperPath.length > 0
        color: "transparent"

        anchors { top: true; bottom: true; left: true; right: true }

        WlrLayershell.namespace: "hwmonitor-overlay"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.overlayVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0

        // Click anywhere, or the whole surface, to dismiss.
        Item {
          id: content
          anchors.fill: parent
          focus: true
          opacity: surface.visible ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

          Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
              root.overlayVisible = false
              event.accepted = true
            }
          }

          Image {
            id: source
            anchors.fill: parent
            source: root.wallpaperPath ? "file://" + root.wallpaperPath : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: surface.width
            sourceSize.height: surface.height
            visible: false
          }

          MultiEffect {
            anchors.fill: source
            source: source
            blurEnabled: true
            blur: root.blurAmount
            blurMax: root.blurRadiusPx
            autoPaddingEnabled: false
          }

          Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: root.scrimOpacity
          }

          MouseArea {
            anchors.fill: parent
            onClicked: root.overlayVisible = false
          }

          // ---- centered sensor dials -----------------------------------

          Row {
            anchors.centerIn: parent
            spacing: 56

            Dial {
              title: "CPU"
              fraction: root.cpuFraction
              valueText: Model.formatPercent(hw.cpuPercent)
              subText: hw.cpuMhz > 0 ? Model.formatGhz(hw.cpuMhz) : ""
              severity: root.cpuSeverity
            }

            Dial {
              visible: hw.hasGpu
              title: "GPU"
              fraction: root.gpuFraction
              valueText: Model.formatPercent(hw.gpuPercent)
              subText: hw.gpuTempC >= 0 ? Model.formatTemp(hw.gpuTempC, false) : ""
              severity: root.gpuSeverity
            }

            Dial {
              title: "MEM"
              fraction: root.ramFraction
              valueText: Model.formatPercent(hw.memPercent)
              subText: hw.memory ? Model.formatGib(Model.gibFromKib(hw.memory.usedKib)) + " / " +
                                    Model.formatGib(Model.gibFromKib(hw.memory.totalKib)) + " GiB" : ""
              severity: root.ramSeverity
            }

            Dial {
              title: "TEMP"
              fraction: root.tempFraction
              valueText: hw.cpuTempC >= 0 ? Model.formatTemp(hw.cpuTempC, false) : ""
              subText: "CPU"
              severity: root.tempSeverity
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 48
            text: "click or esc to close"
            font.family: "monospace"
            font.pixelSize: 12
            color: Qt.rgba(1, 1, 1, 0.4)
          }
        }
      }
    }
  }
}
