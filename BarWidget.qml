import QtQuick
import qs.Commons
import qs.Ui

// Fleet chip: online count, offline count, red when a screen dropped since the
// panel was last opened. Click opens the screens panel.
BarWidget {
  id: root
  moduleName: "screenrig.omarchy"

  readonly property var svc: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property bool alert: !!svc && svc.droppedIds.length > 0
  readonly property bool showCounts: setting("showCounts", true)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function label() {
    if (!svc || !svc.ready) return ""
    var text = svc.onlineCount + " ●"
    if (svc.offlineCount > 0) text += " " + svc.offlineCount + " ○"
    return text
  }

  function tooltip() {
    if (!svc) return "screenRIG"
    if (!svc.ready) return svc.lastError !== "" ? "screenRIG: " + svc.lastError : "screenRIG: connecting"
    var lines = ["screenRIG · " + (svc.project.name || "") ,
                 svc.onlineCount + " of " + svc.screens.length + " screens online"]
    var dropped = svc.droppedNames()
    for (var i = 0; i < dropped.length; i++) lines.push(dropped[i] + " went offline")
    if (svc.live && svc.live.live) lines.push("Live: " + (svc.live.label || "Desktop") + " on " + (svc.live.screens || []).length + " screen(s) · middle-click to stop")
    if (svc.credits && svc.credits.low) lines.push("Credits are low")
    if (!svc.connected && svc.lastError !== "") lines.push(svc.lastError)
    return lines.join("\n")
  }

  TextMetrics {
    id: labelMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.bar.iconFont
    text: button.labelText
  }

  readonly property bool casting: !!svc && !!svc.live && !!svc.live.live
  readonly property bool warn: alert || casting || (!!svc && !!svc.credits && !!svc.credits.low)

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The logomark in the bar's own foreground: white on a dark bar, black on a light one.
    iconComponent: Component {
      Item {
        Logomark {
          x: (parent.width - width) / 2
          y: (parent.height - height) / 2
          size: button.iconSize * 1.2
          color: button.foreground
          opacity: root.svc && root.svc.ready && !root.svc.connected ? 0.5 : 1
        }
      }
    }
    labelText: root.showCounts && !root.vertical ? root.label() : ""
    slotSize: labelText === "" || root.vertical ? Style.bar.iconSlot
      : Style.bar.iconSlot + labelMetrics.advanceWidth + Style.space(8)
    foreground: root.bar ? root.bar.barForeground : Color.foreground
    tooltipText: root.tooltip()

    // A screen dropped or credits are low: a red dot, the mark stays monochrome.
    Rectangle {
      visible: root.warn
      width: Style.space(6)
      height: width
      radius: width / 2
      color: Color.urgent
      x: parent.width / 2 + Style.space(5)
      y: parent.height / 2 - Style.space(9)
      SequentialAnimation on opacity {
        running: root.warn
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton && root.casting) {
        if (root.bar) root.bar.run("screenrig-omarchy live-stop --notify")
        return
      }
      if (buttonCode === Qt.RightButton) {
        if (root.bar) root.bar.run("screenrig-omarchy capture")
        return
      }
      if (root.bar && root.bar.shell) root.bar.shell.toggle(root.moduleName, "{}")
    }
  }
}
