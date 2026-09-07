import QtQuick
import QtQuick.Shapes

// A minimal 270-degree arc dial. Deliberately self-contained (no qs.Commons
// singleton) so this plugin has no dependency on the main hw-monitor plugin
// or the shell's theme system — it carries its own small, neutral palette.
Item {
  id: root

  property string title: ""
  // 0..1. Negative means "no data" and draws an empty track with a dash.
  property real fraction: -1
  property string valueText: ""
  property string subText: ""
  // 0 = normal, 1 = warning, 2 = critical. Blends the value color toward
  // hotColor so a busy machine warms up gradually instead of snapping.
  property real severity: 0

  property color baseColor: "#e8e8e8"
  property color accentColor: "#7dd3fc"
  property color hotColor: "#fb7176"
  property color valueColor: {
    var t = Math.max(0, Math.min(1, severity))
    return Qt.rgba(
      accentColor.r + (hotColor.r - accentColor.r) * t,
      accentColor.g + (hotColor.g - accentColor.g) * t,
      accentColor.b + (hotColor.b - accentColor.b) * t,
      1.0)
  }
  property color trackColor: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.14)
  property color subTextColor: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.55)
  property string fontFamily: "monospace"

  property real diameter: 168
  property real arcWidth: 6

  readonly property bool hasData: fraction >= 0
  readonly property real clampedFraction: hasData ? Math.max(0, Math.min(1, fraction)) : 0
  readonly property bool arcVisible: hasData && clampedFraction > 0.004

  readonly property real dialStart: 135
  readonly property real dialSweep: 270
  readonly property real arcRadius: Math.max(1, (diameter / 2) - arcWidth)

  width: diameter
  height: diameter
  implicitWidth: diameter
  implicitHeight: diameter

  Behavior on fraction { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: root.arcWidth
      strokeColor: root.trackColor
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.arcRadius
        radiusY: root.arcRadius
        startAngle: root.dialStart
        sweepAngle: root.dialSweep
      }
    }

    // Soft under-glow beneath the live value arc.
    ShapePath {
      strokeWidth: root.arcWidth * 2.4
      strokeColor: root.arcVisible ? Qt.rgba(root.valueColor.r, root.valueColor.g, root.valueColor.b, 0.16) : "transparent"
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.arcRadius
        radiusY: root.arcRadius
        startAngle: root.dialStart
        sweepAngle: root.dialSweep * root.clampedFraction
      }
    }

    ShapePath {
      strokeWidth: root.arcWidth
      strokeColor: root.arcVisible ? root.valueColor : "transparent"
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.arcRadius
        radiusY: root.arcRadius
        startAngle: root.dialStart
        sweepAngle: root.dialSweep * root.clampedFraction
      }
    }
  }

  Column {
    anchors.centerIn: parent
    spacing: 4

    Text {
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.title.toUpperCase()
      font.family: root.fontFamily
      font.pixelSize: 12
      font.bold: true
      font.letterSpacing: 2
      color: root.subTextColor
    }

    Text {
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.hasData ? root.valueText : "–"
      font.family: root.fontFamily
      font.pixelSize: 30
      font.bold: true
      color: root.hasData ? root.valueColor : root.subTextColor
      Behavior on color { ColorAnimation { duration: 240 } }
    }

    Text {
      visible: root.subText !== ""
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.subText
      font.family: root.fontFamily
      font.pixelSize: 12
      color: root.subTextColor
    }
  }
}
