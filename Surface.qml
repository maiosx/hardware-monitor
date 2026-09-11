import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

// A fullscreen layer-shell overlay: a blurred copy of the current wallpaper
// (same technique as the Wallpaper Blur plugin's Surface.qml, borrowed
// wholesale) plus a dark scrim, with live CPU / GPU / memory / GPU VRAM
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
      "[ -e \"$p\" ] && readlink -f \"$p\" && exit 0; done " +
      " " +
      "for proc in /proc/[0-9]*; do " +
      "[ -r \"$proc/cmdline\" ] || continue; " +
      "mapfile -d '' -t args < \"$proc/cmdline\" 2>/dev/null || continue; " +
      "for ((i = 1; i < ${#args[@]}; i++)); do " +
      "case \"${args[i]}\" in " +
      "-i|--image) " +
      "[ -f \"${args[i + 1]}\" ] && readlink -f \"${args[i + 1]}\" && exit 0 ;; " +
      "--image=*) p=\"${args[i]#--image=}\"; " +
      "[ -f \"$p\" ] && readlink -f \"$p\" && exit 0 ;; " +
      "esac; done; done"]
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
  readonly property real vramFraction: hw.hasGpu && hw.gpuVramPercent >= 0 ? hw.gpuVramPercent / 100 : -1

  readonly property real cpuSeverity: Model.severity(hw.cpuPercent, root.warnPercent, root.criticalPercent)
  readonly property real ramSeverity: Model.severity(hw.memPercent, root.warnPercent, root.criticalPercent)
  readonly property real gpuSeverity: Model.severity(hw.gpuPercent, root.warnPercent, root.criticalPercent)
  readonly property real vramSeverity: Model.severity(hw.gpuVramPercent, root.warnPercent, root.criticalPercent)

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
              visible: hw.hasGpu
              title: "VRAM"
              fraction: root.vramFraction
              valueText: Model.formatPercent(hw.gpuVramPercent)
              subText: hw.gpuVramTotalBytes > 0
                ? Model.formatGib(Model.gibFromBytes(hw.gpuVramUsedBytes)) + " / " +
                  Model.formatGib(Model.gibFromBytes(hw.gpuVramTotalBytes)) + " GiB" : ""
              severity: root.vramSeverity
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
