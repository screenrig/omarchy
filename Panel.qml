import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The screenRIG panel: screens grid, send to screens, Player on this machine,
// ask your agent and theme matching.
//
// Look: an opaque graphite sheet with a soft ambient shadow, rounded tiles
// with masked screenshots, segmented controls with sliding indicators and a
// floating action bar on the hovered tile. Type: titleSize, bodySize,
// metaSize, plus one hero numeral in the theme preview. Motion goes through
// d() so Omarchy's reduced-motion setting turns it off.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false

  property string mode: "screens"
  // The last tab survives closing the panel and restarting the shell.
  onModeChanged: {
    if (tabs.some(function(t) { return t.id === mode }) && lastTab.mode !== mode) {
      lastTab.mode = mode
      lastTabFile.setText(JSON.stringify({ mode: mode }) + "\n")
    }
    if (mode === "cast" && !casting && !openingSend) resetCast()
    Qt.callLater(focusCast)
  }
  property bool openingSend: false
  QtObject { id: lastTab; property string mode: "screens" }
  FileView {
    id: lastTabFile
    path: Quickshell.env("HOME") + "/.local/state/screenrig-omarchy/panel.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var saved = JSON.parse(String(text() || "{}")).mode
        if (saved === "send") saved = "cast"
        if (root.tabs.some(function(t) { return t.id === saved })) lastTab.mode = saved
      } catch (e) {}
    }
  }
  property string focusId: ""
  property string screenFilter: "all"
  property string search: ""
  property string sendKind: ""
  property string sendSource: ""
  property string sendPath: ""
  property string sendUrl: ""
  property var sendSelected: ({})
  property int sendMinutes: 10
  property bool sending: false
  property var picker: null
  property int pickMinutes: 30
  property int shotBump: 0
  property double nowMs: Date.now()
  property var playerInfo: ({ running: false, native: false, monitors: [] })
  property string playerMonitor: ""
  property bool themeSyncOn: false
  property bool playerBusy: false
  // Live cast: the chosen monitor or window ("screen:NAME" or "window:ADDRESS") and how long.
  property string liveSource: ""
  property string liveLabel: ""
  property int liveMinutes: 0
  property var liveSourceList: []
  // What was cast last and to which screens (written by the helper).
  property var lastCast: ({})
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/screenrig-omarchy/last-cast.json"
    watchChanges: true
    printErrors: false
    onLoaded: { try { root.lastCast = JSON.parse(String(text() || "{}")) || {} } catch (e) {} }
    onFileChanged: reload()
  }

  // Preselect the screens of the last cast that are available now.
  function preselectScreens() {
    if (selectedIds().length) return
    var want = lastCast.screens || []
    var list = castTargets()
    var next = {}
    for (var i = 0; i < list.length; i++) if (list[i].online && want.indexOf(list[i].id) >= 0) next[list[i].id] = true
    sendSelected = next
  }
  Connections {
    target: root.svc
    function onLiveTargetsChanged() { root.preselectScreens() }
  }

  // Cast starts live, until stopped, with the source and screens cast last (the desktop if that source is gone).
  function resetCast() {
    sendSource = "live"
    sendKind = ""
    sendSelected = ({})
    liveMinutes = 0
    liveSource = ""
    refreshLiveSources()
    preselectScreens()
  }

  function focusCast() {
    if (mode === "cast" && sendSource === "live" && !casting) sourceGrid.forceActiveFocus()
  }
  property string liveSourceKey: ""
  property bool projectMenu: false

  // Opening and closing animate `presence`; the window stays mapped until it reaches 0.
  readonly property bool revealed: opened && overlay.contentRevealed
  property real presence: revealed ? 1 : 0
  Behavior on presence {
    NumberAnimation { duration: root.d(root.revealed ? 380 : 170); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.easeOut }
  }

  readonly property var svc: service
  readonly property color fg: Commons.Color.popups.text
  readonly property color base: Qt.rgba(Commons.Color.popups.background.r, Commons.Color.popups.background.g, Commons.Color.popups.background.b, 1)
  readonly property color surface: Qt.darker(base, 1.08)
  readonly property color surfaceTop: Qt.tint(surface, Util.alpha(fg, 0.035))
  readonly property color raised: Qt.tint(surface, Util.alpha(fg, 0.045))
  readonly property color well: Qt.darker(surface, 1.45)
  readonly property color line: Util.alpha(fg, 0.10)
  readonly property color lineStrong: Util.alpha(fg, 0.18)
  readonly property color dim: Util.alpha(fg, 0.56)
  readonly property color accent: Commons.Color.accent
  readonly property color onAccent: Qt.darker(base, 1.4)
  readonly property color onlineColor: "#4cc38a"
  readonly property color offlineColor: "#ef5f5f"
  readonly property string fontFamily: Style.font.family
  readonly property int titleSize: Style.font.title
  readonly property int bodySize: Style.font.body
  readonly property int metaSize: Style.font.bodySmall
  readonly property real gap: Style.space(14)
  readonly property real pad: Style.space(22)
  readonly property real rCard: Style.space(14)
  readonly property real rTile: Style.space(10)
  readonly property real rControl: Style.space(8)
  readonly property real controlHeight: Style.space(34)
  // Every view but the chat sizes the panel to its content.
  readonly property bool compact: mode !== "agent"

  function d(ms) { return Style.duration(ms) }

  readonly property var tabs: [
    { id: "screens", label: "Screens", icon: "󰍹" },
    { id: "cast", label: "Cast", icon: "󰄘" },
    { id: "agent", label: "Agent", icon: "󰚩" }
    // Player and Theme are hidden for now; their views below stay.
  ]

  readonly property var visibleScreens: {
    var list = svc ? svc.screens : []
    var q = search.trim().toLowerCase()
    var out = []
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      if (screenFilter === "online" && !s.online) continue
      if (screenFilter === "offline" && s.online) continue
      if (q !== "" && (s.label + " " + (s.playing_name || "")).toLowerCase().indexOf(q) < 0) continue
      out.push(s)
    }
    return out
  }

  // ------------------------------------------------------------------ host API

  function open(payloadJson) {
    var p = {}
    try { p = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    var want = p.mode === "send" ? "cast" : p.mode
    openingSend = !!(p.kind || p.path || p.url)
    mode = tabs.some(function(t) { return t.id === want }) ? want : lastTab.mode
    openingSend = false
    focusId = p.focus || ""
    picker = null
    if (focusId !== "") { screenFilter = "all"; search = "" }
    if (mode === "cast" && !(p.kind || p.path || p.url)) resetCast()
    if (mode === "cast" && (p.kind || p.path || p.url)) {
      sendKind = p.kind || ""
      sendSource = p.source || (p.kind === "url" ? "clipboard" : "file")
      sendPath = p.path || ""
      sendUrl = p.url || ""
      sendSelected = ({})
      sending = false
      Qt.callLater(preselectScreens)
    }
    nowMs = Date.now()
    if (svc) svc.acknowledge()
    refreshPlayer()
    refreshTheme()
    projectMenu = false
    if (svc) { svc.loadProjects(); svc.loadChat(); svc.refreshLive(); svc.loadLiveTargets() }
    refreshOnboarding()
    refreshLiveSetup()
    refreshLiveSources()
    opened = true
    Qt.callLater(function() {
      if (!root.opened) return
      if (root.mode === "agent") agentField.forceActiveFocus()
      else if (root.mode === "cast" && root.sendSource === "live" && !root.casting) sourceGrid.forceActiveFocus()
      else keyCatcher.forceActiveFocus()
      root.scrollToFocus()
    })
  }

  function close() {
    opened = false
    picker = null
    projectMenu = false
    if (svc) svc.acknowledge()
  }

  // IPC: `omarchy-shell shell call screenrig.omarchy stopCast ""` ends a live cast from a keybinding.
  function stopCast(unused) {
    if (!svc || stopping) return
    stopping = true
    svc.liveStop()
  }

  // IPC: `omarchy-shell shell call screenrig.omarchy ask "…"` opens the chat and sends.
  function ask(text) {
    mode = "agent"
    if (svc) svc.agentSend(text)
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "screenrig.omarchy")
    else close()
  }

  // ------------------------------------------------------------------ helpers

  function scrollToFocus() {
    for (var i = 0; i < visibleScreens.length; i++) {
      if (visibleScreens[i].id === focusId) { grid.positionViewAtIndex(i, GridView.Contain); return }
    }
  }

  function runDetached(args) { Quickshell.execDetached([svc.helper].concat(args)) }

  function refreshPlayer() {
    if (!svc) return
    svc.run(["player", "status"], function(ok, message, answer) {
      root.playerInfo = answer || {}
      var mons = root.playerInfo.monitors || []
      if (root.playerMonitor === "" && mons.length) root.playerMonitor = mons[mons.length - 1].name
    })
  }

  function refreshTheme() {
    if (!svc) return
    svc.run(["theme-sync", "enabled"], function(ok) { root.themeSyncOn = ok })
  }

  function ago(iso) {
    if (!iso) return "never"
    var s = Math.max(0, Math.round((nowMs - Date.parse(iso)) / 1000))
    if (s < 60) return s + "s ago"
    if (s < 3600) return Math.round(s / 60) + "m ago"
    if (s < 86400) return Math.round(s / 3600) + "h ago"
    return Math.round(s / 86400) + "d ago"
  }

  function minutesLeft(iso) {
    if (!iso) return ""
    var m = Math.round((Date.parse(iso) - nowMs) / 60000)
    return m > 0 ? " · " + m + " min" : ""
  }

  function has(list, value) { return (list || []).indexOf(value) >= 0 }

  function countWhere(online) {
    var n = 0
    var list = svc ? svc.screens : []
    for (var i = 0; i < list.length; i++) if (online === null || list[i].online === online) n++
    return n
  }

  function selectedIds() {
    var ids = []
    for (var k in sendSelected) if (sendSelected[k]) ids.push(k)
    return ids
  }

  function allOnlineSelected() {
    var list = svc ? svc.screens : []
    var any = false
    for (var i = 0; i < list.length; i++) {
      if (!list[i].online) continue
      any = true
      if (!sendSelected[list[i].id]) return false
    }
    return any
  }

  function toggleSend(id) {
    var next = Object.assign({}, sendSelected)
    next[id] = !next[id]
    sendSelected = next
  }

  function selectAllOnline() {
    var clear = allOnlineSelected()
    var next = {}
    var list = svc ? svc.screens : []
    if (!clear) for (var i = 0; i < list.length; i++) if (list[i].online) next[list[i].id] = true
    sendSelected = next
  }

  function doSend() {
    var ids = selectedIds()
    if (!ids.length || sending || sendKind === "") return
    sending = true
    var args = ["send", "--screens", ids.join(","), "--minutes", String(sendMinutes)]
    if (sendKind === "url") args = args.concat(["--url", sendUrl])
    else args = args.concat(["--file", sendPath])
    svc.report(true, "Casting to " + ids.length + " screen" + (ids.length === 1 ? "" : "s"))
    svc.run(args, function(ok, message) {
      root.sending = false
      svc.report(ok, message)
      if (ok) { root.mode = "screens"; root.sendKind = ""; headerLogo.celebrate() }
    })
  }

  // A cast is live: the Cast tab shows its status instead of the pickers.
  readonly property bool casting: !!svc && !!svc.live && !!svc.live.live
  property bool stopping: false
  property double tickMs: Date.now()
  onCastingChanged: if (!casting) stopping = false

  Timer {
    interval: 1000
    repeat: true
    running: root.casting && root.opened
    triggeredOnStart: true
    onTriggered: root.tickMs = Date.now()
  }

  // The monitor or window a live cast captures, for its preview.
  function captureFor(source) {
    source = String(source || "")
    if (source.indexOf("screen:") === 0) {
      var name = source.slice(7)
      for (var i = 0; i < Quickshell.screens.length; i++) if (Quickshell.screens[i].name === name) return Quickshell.screens[i]
    } else if (source.indexOf("window:") === 0) {
      var address = source.slice(7).replace(/^0x/, "")
      var tops = Hyprland.toplevels.values
      for (var j = 0; j < tops.length; j++) if (String(tops[j].address).replace(/^0x/, "") === address) return tops[j].wayland
    }
    return null
  }

  function screenNames(ids) {
    var names = []
    for (var i = 0; i < ids.length; i++) {
      var s = svc ? svc.screenById(ids[i]) : null
      names.push(s ? s.label : ids[i])
    }
    if (names.length <= 1) return names.join("")
    return names.slice(0, -1).join(", ") + " and " + names[names.length - 1]
  }

  // 1:04:09 or 12:34.
  function clock(ms) {
    var t = Math.max(0, Math.floor(ms / 1000))
    var h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), sec = t % 60
    var pad = function(n) { return (n < 10 ? "0" : "") + n }
    return (h > 0 ? h + ":" + pad(m) : m) + ":" + pad(sec)
  }

  // Monitors first, then app windows; rebuilt only when the set changes, so thumbnails stay put.
  function refreshLiveSources() {
    var out = []
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var sc = Quickshell.screens[i]
      out.push({ id: "screen:" + sc.name, kind: "screen", title: "Desktop", detail: sc.name + "  " + sc.width + "×" + sc.height, capture: sc })
    }
    var tops = Hyprland.toplevels.values
    for (var j = 0; j < tops.length; j++) {
      var t = tops[j]
      if (!t || !t.wayland) continue
      out.push({ id: "window:" + t.address, kind: "window", title: t.title || t.wayland.appId || "Window",
                 detail: t.wayland.appId || "", capture: t.wayland })
    }
    var key = out.map(function(o) { return o.id }).join(",")
    if (key !== liveSourceKey) {
      liveSourceKey = key
      liveSourceList = out
    }
    // The source cast last while it still exists, else the desktop.
    var ids = out.map(function(o) { return o.id })
    if ((liveSource === "" || ids.indexOf(liveSource) < 0) && out.length) {
      var pick = ids.indexOf(lastCast.source || "") >= 0 ? out[ids.indexOf(lastCast.source)] : out[0]
      liveSource = pick.id
      liveLabel = pick.title
    }
  }

  function liveSources() { return liveSourceList }

  Timer {
    interval: 4000
    repeat: true
    running: root.opened && root.mode === "cast" && root.sendSource === "live"
    onTriggered: root.refreshLiveSources()
  }

  function castTargets() {
    if (sendSource === "live") return svc && svc.liveTargets.screens ? svc.liveTargets.screens : []
    return svc ? svc.screens : []
  }

  function allTargetsSelected() {
    var list = castTargets()
    var any = false
    for (var i = 0; i < list.length; i++) {
      if (!list[i].online) continue
      any = true
      if (!sendSelected[list[i].id]) return false
    }
    return any
  }

  function selectAllTargets() {
    var clear = allTargetsSelected()
    var next = {}
    var list = castTargets()
    if (!clear) for (var i = 0; i < list.length; i++) if (list[i].online) next[list[i].id] = true
    sendSelected = next
  }

  // Live casting changes this laptop only after the person allows it here.
  // First run: the screenRIG plugin for the default agent, then a sign-in.
  property var onboarding: ({})
  property bool installingPlugin: false
  readonly property bool needsPlugin: onboarding.ok === true && !(onboarding.plugin && onboarding.cli)
  readonly property bool needsSignIn: onboarding.ok === true && !onboarding.signed_in
  readonly property bool firstRun: needsPlugin || needsSignIn
  function refreshOnboarding() {
    if (svc) svc.run(["onboarding"], function(ok, message, answer) { if (ok) root.onboarding = answer })
  }
  function installPlugin() {
    if (installingPlugin) return
    installingPlugin = true
    svc.run(["install-plugin"], function(ok, message) {
      root.installingPlugin = false
      svc.report(ok, message)
      root.refreshOnboarding()
    })
  }
  function signIn() {
    svc.addProject()
  }
  Connections {
    target: root.svc
    function onPendingLoginChanged() { if (root.svc && !root.svc.pendingLogin) root.refreshOnboarding() }
  }

  property var liveSetup: ({})
  readonly property bool liveWindowPicked: liveSource.indexOf("window:") === 0
  readonly property bool needsFirewall: liveSetup.firewall === "needed" || liveSetup.firewall === "no-sudo"
  readonly property bool needsPicker: liveWindowPicked && liveSetup.picker === false
  readonly property bool needsConsent: sendSource === "live" && (needsFirewall || needsPicker)
  function refreshLiveSetup() {
    if (svc) svc.run(["live-setup-status"], function(ok, message, answer) { if (ok) root.liveSetup = answer })
  }
  function allowLive() {
    svc.run(["live-setup"], function(ok, message) {
      svc.report(ok, message)
      root.refreshLiveSetup()
    })
  }

  function goLive() {
    var allowed = {}
    var list = castTargets()
    for (var i = 0; i < list.length; i++) allowed[list[i].id] = true
    var ids = selectedIds().filter(function(id) { return allowed[id] })
    if (!ids.length || sending || liveSource === "" || needsConsent) return
    sending = true
    svc.report(true, "Going live on " + ids.length + " screen" + (ids.length === 1 ? "" : "s"))
    svc.liveStart(liveSource, liveLabel, ids, liveMinutes, function(ok, message) {
      root.sending = false
      svc.report(ok, message)
      if (ok) headerLogo.celebrate()
    })
  }

  function isImage(path) { return /\.(png|jpe?g|webp|gif)$/i.test(path || "") }

  function restartAction(s) {
    if (has(s.capabilities, "reboot")) return { action: "reboot", tip: "Reboot the device" }
    if (has(s.capabilities, "restart_app")) return { action: "restart-app", tip: "Restart the Player app" }
    return { action: "", tip: "This device cannot be restarted remotely" }
  }

  function hex(c) { return String(c).toUpperCase().slice(0, 7) }

  Timer {
    interval: 15000
    repeat: true
    running: root.opened
    onTriggered: root.nowMs = Date.now()
  }

  FontMetrics { id: bodyMetrics; font.family: root.fontFamily; font.pixelSize: root.bodySize }
  FontMetrics { id: metaMetrics; font.family: root.fontFamily; font.pixelSize: root.metaSize }

  // ---------------------------------------------------------------- components

  component Label: Text {
    property bool meta: false
    property bool title: false
    color: meta ? root.dim : root.fg
    font.family: root.fontFamily
    font.pixelSize: title ? root.titleSize : (meta ? root.metaSize : root.bodySize)
    font.bold: title
    elide: Text.ElideRight
    Behavior on color { ColorAnimation { duration: root.d(160) } }
  }

  component Hairline: Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    color: root.line
  }

  // A status dot; `pulse` adds a slow expanding halo.
  component PulseDot: Item {
    id: dot
    property color color: root.onlineColor
    property bool pulse: false
    implicitWidth: Style.space(8)
    implicitHeight: implicitWidth
    Rectangle {
      id: halo
      anchors.centerIn: parent
      width: parent.width; height: width; radius: width / 2
      color: dot.color
      opacity: 0
      SequentialAnimation {
        running: dot.pulse && root.revealed && Style.duration(1) > 0
        loops: Animation.Infinite
        ParallelAnimation {
          NumberAnimation { target: halo; property: "scale"; from: 1; to: 2.6; duration: 1700; easing.type: Easing.OutCubic }
          NumberAnimation { target: halo; property: "opacity"; from: 0.45; to: 0; duration: 1700; easing.type: Easing.OutCubic }
        }
        PauseAnimation { duration: 500 }
      }
    }
    Rectangle { anchors.fill: parent; radius: width / 2; color: dot.color }
  }

  // Segmented control with a sliding indicator. `underline` draws an accent
  // bar instead of a pill; `equal` gives every segment the same width.
  component Segmented: Item {
    id: seg
    property var items: []
    property string current: ""
    property bool underline: false
    property bool equal: false
    property real pillX: 0
    property real pillW: 0
    signal picked(string id)
    implicitHeight: root.controlHeight
    implicitWidth: segRow.implicitWidth + Style.space(8)

    Rectangle {
      anchors.fill: parent
      radius: root.rControl
      color: Util.alpha(root.fg, 0.03)
      border.color: root.line
    }
    Rectangle {
      visible: !seg.underline && seg.pillW > 0
      x: seg.pillX + Style.space(4)
      y: Style.space(3)
      width: seg.pillW
      height: seg.height - Style.space(6)
      radius: root.rControl - Style.space(3)
      color: Util.alpha(root.fg, 0.10)
      border.color: Util.alpha(root.fg, 0.08)
      Behavior on x { NumberAnimation { duration: root.d(340); easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
      Behavior on width { NumberAnimation { duration: root.d(340); easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
    }
    Rectangle {
      visible: seg.underline && seg.pillW > 0
      x: seg.pillX + Style.space(4) + Style.space(12)
      y: seg.height - Style.space(4)
      width: Math.max(0, seg.pillW - Style.space(24))
      height: Style.space(2)
      radius: 1
      color: root.accent
      Behavior on x { NumberAnimation { duration: root.d(340); easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
      Behavior on width { NumberAnimation { duration: root.d(340); easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
    }
    Row {
      id: segRow
      x: Style.space(4)
      height: parent.height
      Repeater {
        model: seg.items
        Item {
          id: cell
          required property var modelData
          required property int index
          readonly property bool on: seg.current === modelData.id
          width: seg.equal ? (seg.width - Style.space(8)) / Math.max(1, seg.items.length) : cellRow.implicitWidth + Style.space(28)
          height: segRow.height
          function sync() { if (on) { seg.pillX = x; seg.pillW = width } }
          onOnChanged: sync()
          onXChanged: sync()
          onWidthChanged: sync()
          Component.onCompleted: sync()
          Row {
            id: cellRow
            anchors.centerIn: parent
            spacing: Style.space(8)
            PulseDot {
              visible: !!cell.modelData.dot
              anchors.verticalCenter: parent.verticalCenter
              color: cell.modelData.dot === "online" ? root.onlineColor : root.offlineColor
            }
            Label {
              visible: !!cell.modelData.icon
              anchors.verticalCenter: parent.verticalCenter
              text: cell.modelData.icon || ""
              color: cell.on ? root.fg : root.dim
            }
            Label {
              anchors.verticalCenter: parent.verticalCenter
              text: cell.modelData.label
              color: cell.on || cellMouse.containsMouse ? root.fg : root.dim
              font.bold: cell.on
            }
            Label {
              visible: cell.modelData.count !== undefined
              anchors.verticalCenter: parent.verticalCenter
              text: cell.modelData.count !== undefined ? String(cell.modelData.count) : ""
              meta: true
            }
          }
          MouseArea {
            id: cellMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: seg.picked(cell.modelData.id)
          }
        }
      }
    }
  }

  // Text input with a rounded surface and an accent focus ring.
  component Field: TextField {
    id: field
    property string glyph: ""
    implicitHeight: root.controlHeight
    leftPadding: glyph !== "" ? Style.space(34) : Style.space(12)
    rightPadding: Style.space(12)
    verticalAlignment: TextInput.AlignVCenter
    background: Rectangle {
      radius: root.rControl
      color: field.activeFocus ? Util.alpha(root.fg, 0.06) : Util.alpha(root.fg, 0.03)
      border.color: field.activeFocus ? Util.alpha(root.accent, 0.7) : (field.hovered ? root.lineStrong : root.line)
      Behavior on border.color { ColorAnimation { duration: root.d(160) } }
      Behavior on color { ColorAnimation { duration: root.d(160) } }
      Text {
        visible: field.glyph !== ""
        x: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        text: field.glyph
        color: field.activeFocus ? root.accent : root.dim
        font.family: root.fontFamily
        font.pixelSize: root.bodySize
      }
    }
  }

  // The one filled accent action on a view, with a soft glow.
  component PrimaryButton: Item {
    id: primary
    property string text: ""
    property string iconText: ""
    property bool busy: false
    signal clicked()
    implicitHeight: root.controlHeight
    implicitWidth: primaryRow.implicitWidth + Style.space(32)
    opacity: enabled ? 1 : 0.42
    Behavior on opacity { NumberAnimation { duration: root.d(160) } }

    Rectangle {
      id: primaryFill
      anchors.fill: parent
      radius: root.rControl
      color: primaryMouse.pressed ? Qt.darker(root.accent, 1.12) : (primaryMouse.containsMouse ? Qt.lighter(root.accent, 1.08) : root.accent)
      Behavior on color { ColorAnimation { duration: root.d(140) } }
      layer.enabled: primary.enabled
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: root.accent
        shadowBlur: 0.9
        shadowOpacity: primaryMouse.containsMouse ? 0.55 : 0.28
        shadowVerticalOffset: 2
        shadowHorizontalOffset: 0
        Behavior on shadowOpacity { NumberAnimation { duration: root.d(200) } }
      }
    }
    Row {
      id: primaryRow
      anchors.centerIn: parent
      spacing: Style.space(8)
      Text {
        text: primary.busy ? "󰔟" : primary.iconText
        visible: text !== ""
        color: root.onAccent
        font.family: root.fontFamily
        font.pixelSize: root.bodySize
        anchors.verticalCenter: parent.verticalCenter
        RotationAnimation on rotation { running: primary.busy; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
      }
      Text {
        text: primary.text
        color: root.onAccent
        font.family: root.fontFamily
        font.pixelSize: root.bodySize
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    scale: primaryMouse.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: root.d(120); easing.type: Easing.OutCubic } }
    MouseArea {
      id: primaryMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: primary.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (primary.enabled) primary.clicked()
    }
  }

  // A quiet bordered secondary action.
  component QuietButton: Button {
    radius: root.rControl
    bordered: true
    implicitHeight: root.controlHeight
  }

  // A view under the header: fades and rises in when it becomes current.
  component View: ColumnLayout {
    id: view
    property string name: ""
    property real enter: 1
    Layout.fillWidth: true
    visible: root.mode === name
    spacing: root.gap
    opacity: enter
    transform: Translate { y: (1 - view.enter) * Style.space(10) }
    onVisibleChanged: if (visible) { enter = 0; enterAnim.restart() }
    NumberAnimation {
      id: enterAnim
      target: view
      property: "enter"
      to: 1
      duration: root.d(360)
      easing.type: Easing.BezierSpline
      easing.bezierCurve: Style.easeOut
    }
  }

  // Rounded image well: content clipped to the radius.
  component Well: Item {
    id: well
    property real radius: root.rControl
    default property alias content: wellContent.data
    Rectangle { id: wellMask; anchors.fill: parent; radius: well.radius; visible: false; layer.enabled: true; layer.smooth: true }
    Item {
      id: wellContent
      anchors.fill: parent
      layer.enabled: true
      layer.effect: MultiEffect { maskEnabled: true; maskSource: wellMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }
    }
    Rectangle { anchors.fill: parent; radius: well.radius; color: "transparent"; border.color: Util.alpha("white", 0.06) }
  }

  // ------------------------------------------------------------------ window

  OverlayWindow {
    id: overlay
    shown: root.opened || root.presence > 0.001
    WlrLayershell.namespace: "screenrig-omarchy"

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.7 * root.presence)
      MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: {
        if (root.projectMenu) root.projectMenu = false
        else if (root.picker) root.picker = null
        else root.dismiss()
      }

      Item {
        id: stage
        readonly property real fullHeight: Math.min(Style.space(860), parent.height - Style.space(56))
        anchors.centerIn: parent
        anchors.verticalCenterOffset: (1 - root.presence) * Style.space(18)
        // Each view gets the width its content needs.
        readonly property real modeWidth: Style.space(root.mode === "screens" ? 1320 : (root.mode === "cast" ? 1120 : 880))
        width: Math.min(modeWidth, parent.width - Style.space(56))
        Behavior on width {
          enabled: root.revealed
          NumberAnimation { duration: root.d(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.easeOut }
        }
        height: root.compact ? Math.min(fullHeight, body.implicitHeight + root.pad * 2) : fullHeight
        Behavior on height {
          enabled: root.revealed
          NumberAnimation { duration: root.d(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.easeOut }
        }
        opacity: root.presence
        scale: 0.965 + 0.035 * root.presence

        // Ambient shadow.
        Rectangle {
          anchors.fill: parent
          radius: root.rCard
          color: root.surface
          layer.enabled: true
          layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "black"
            shadowBlur: 1.0
            shadowOpacity: 0.7
            shadowVerticalOffset: Style.space(18)
            blurMax: 64
          }
        }

        Rectangle {
          id: card
          anchors.fill: parent
          radius: root.rCard
          gradient: Gradient {
            GradientStop { position: 0; color: root.surfaceTop }
            GradientStop { position: 0.35; color: root.surface }
          }
          border.color: root.line
          clip: true

          // Top inner highlight.
          Rectangle {
            x: root.rCard; width: parent.width - root.rCard * 2; height: 1; y: 1
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: "transparent" }
              GradientStop { position: 0.5; color: Util.alpha("white", 0.09) }
              GradientStop { position: 1; color: "transparent" }
            }
          }

          MouseArea { anchors.fill: parent; onClicked: {} }
          HoverHandler { id: cardHover }

          ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: root.pad
            spacing: root.gap

            // Header: mark, brand, project, fleet health, tabs, close.
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(12)
              LogoCharacter {
                id: headerLogo
                size: Style.space(30)
                Layout.alignment: Qt.AlignVCenter
                alive: root.revealed
                target: cardHover.hovered ? card.mapToItem(headerLogo, cardHover.point.position.x, cardHover.point.position.y) : null
              }
              // Wordmark, in the brand's colours and face.
              Row {
                Layout.alignment: Qt.AlignVCenter
                Text { text: "screen"; color: "#F8B334"; font.family: "Agave Nerd Font"; font.pixelSize: root.titleSize * 1.25 }
                Text { text: "RIG"; color: "#EEE9DF"; font.family: "Agave Nerd Font"; font.pixelSize: root.titleSize * 1.25 }
              }
              Text { text: "/"; color: root.lineStrong; font.family: root.fontFamily; font.pixelSize: root.titleSize * 1.25 }
              // Project switcher.
              Item {
                id: projectButton
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: projectRow.implicitWidth + Style.space(20)
                implicitHeight: root.controlHeight
                Rectangle {
                  anchors.fill: parent
                  radius: root.rControl
                  color: root.projectMenu ? Util.alpha(root.fg, 0.10) : (projectMouse.containsMouse ? Util.alpha(root.fg, 0.06) : "transparent")
                  border.color: root.projectMenu || projectMouse.containsMouse ? root.line : "transparent"
                  Behavior on color { ColorAnimation { duration: root.d(140) } }
                }
                Row {
                  id: projectRow
                  anchors.centerIn: parent
                  spacing: Style.space(8)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.svc && root.svc.switching ? "Switching" : (root.svc ? (root.svc.project.name || "Project") : "Project")
                    color: "#EEE9DF"
                    font.family: root.fontFamily
                    font.pixelSize: root.titleSize * 1.25
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰅀"
                    color: root.projectMenu ? root.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.bodySize
                    rotation: root.projectMenu ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: root.d(240); easing.type: Easing.OutCubic } }
                  }
                }
                MouseArea {
                  id: projectMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.projectMenu = !root.projectMenu
                    if (root.projectMenu && root.svc) root.svc.loadProjects()
                  }
                }
              }
              Item { implicitWidth: Style.space(10); visible: root.mode === "screens" }
              Row {
                visible: !!root.svc && root.svc.ready && root.mode === "screens"
                spacing: Style.space(8)
                Layout.alignment: Qt.AlignVCenter
                PulseDot { anchors.verticalCenter: parent.verticalCenter; color: root.onlineColor; pulse: true }
                Label { anchors.verticalCenter: parent.verticalCenter; text: (root.svc ? root.svc.onlineCount : 0) + " online" }
                Item { width: Style.space(4); height: 1 }
                PulseDot { anchors.verticalCenter: parent.verticalCenter; color: root.offlineColor; visible: root.svc && root.svc.offlineCount > 0 }
                Label {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: root.svc && root.svc.offlineCount > 0
                  text: (root.svc ? root.svc.offlineCount : 0) + " offline"
                  meta: true
                }
              }
              // Health bar: share of screens online.
              Item {
                visible: !!root.svc && root.svc.ready && root.svc.screens.length > 0 && root.mode === "screens"
                implicitWidth: Style.space(120)
                implicitHeight: Style.space(4)
                Layout.alignment: Qt.AlignVCenter
                Rectangle { anchors.fill: parent; radius: height / 2; color: Util.alpha(root.offlineColor, 0.55) }
                Rectangle {
                  height: parent.height
                  radius: height / 2
                  color: root.onlineColor
                  width: root.svc && root.svc.screens.length ? parent.width * root.presence * root.svc.onlineCount / root.svc.screens.length : 0
                }
              }
              Label {
                visible: !!root.svc && !!root.svc.credits && !!root.svc.credits.low
                text: "· credits low"
                color: Commons.Color.urgent
              }
              Item { Layout.fillWidth: true }
              Segmented {
                items: root.tabs
                current: root.mode
                onPicked: function(id) {
                  root.mode = id
                  root.picker = null
                  if (id === "player") root.refreshPlayer()
                  if (id === "agent") agentField.forceActiveFocus()
                }
              }
              Item {
                implicitWidth: root.controlHeight
                implicitHeight: root.controlHeight
                Rectangle {
                  anchors.fill: parent
                  radius: width / 2
                  color: closeMouse.containsMouse ? Util.alpha(root.fg, 0.10) : "transparent"
                  Behavior on color { ColorAnimation { duration: root.d(140) } }
                }
                Label { anchors.centerIn: parent; text: "󰅖"; color: closeMouse.containsMouse ? root.fg : root.dim }
                MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.dismiss() }
              }
            }

            Hairline {}

            // Casting: Stop stays one click away on every tab.
            Rectangle {
              visible: root.casting && root.mode !== "cast"
              Layout.fillWidth: true
              implicitHeight: root.controlHeight + Style.space(12)
              radius: root.rTile
              color: Util.alpha(root.offlineColor, 0.10)
              border.color: Util.alpha(root.offlineColor, 0.4)
              readonly property var info: root.svc ? root.svc.live : ({})
              readonly property real untilMs: info.until ? Date.parse(info.until) : 0
              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.space(14)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(12)
                PulseDot { color: root.offlineColor; pulse: true }
                Text { text: "LIVE"; color: root.offlineColor; font.family: root.fontFamily; font.pixelSize: root.metaSize; font.bold: true; font.letterSpacing: 1.4 }
                Label {
                  Layout.fillWidth: true
                  text: (parent.parent.info.label || "Desktop") + " on " + root.screenNames(parent.parent.info.screens || [])
                    + "  ·  " + (parent.parent.untilMs ? root.clock(parent.parent.untilMs - root.tickMs) + " left"
                      : root.clock(root.tickMs - (parent.parent.info.started_at || 0) * 1000))
                }
                Label {
                  text: "Open"
                  color: openLive.containsMouse ? root.fg : root.dim
                  MouseArea { id: openLive; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.mode = "cast" }
                }
                Item {
                  implicitWidth: stopRow.implicitWidth + Style.space(28)
                  implicitHeight: root.controlHeight
                  Rectangle {
                    anchors.fill: parent
                    radius: root.rControl
                    color: stripStop.containsMouse ? Qt.lighter(root.offlineColor, 1.08) : root.offlineColor
                    Behavior on color { ColorAnimation { duration: root.d(140) } }
                  }
                  Row {
                    id: stopRow
                    anchors.centerIn: parent
                    spacing: Style.space(8)
                    Text { text: root.stopping ? "󰔟" : "󰓛"; color: "white"; font.family: root.fontFamily; font.pixelSize: root.bodySize; anchors.verticalCenter: parent.verticalCenter }
                    Text { text: root.stopping ? "Stopping" : "Stop"; color: "white"; font.family: root.fontFamily; font.pixelSize: root.bodySize; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                  }
                  MouseArea { id: stripStop; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.stopCast() }
                }
              }
            }

            // First run: install the screenRIG plugin for the agent, then sign in.
            Rectangle {
              visible: root.firstRun
              Layout.fillWidth: true
              implicitHeight: firstCol.implicitHeight + Style.space(32)
              radius: root.rTile
              color: Util.alpha(root.accent, 0.08)
              border.color: Util.alpha(root.accent, 0.35)
              ColumnLayout {
                id: firstCol
                anchors.fill: parent
                anchors.margins: Style.space(16)
                anchors.leftMargin: Style.space(20)
                spacing: Style.space(12)
                Label { text: "Set up screenRIG"; font.bold: true; font.pixelSize: root.titleSize }
                Label {
                  Layout.fillWidth: true
                  meta: true
                  wrapMode: Text.Wrap
                  text: "screenRIG is free digital signage driven by your AI agent. The panel uses the official screenRIG plugin (its skill and CLI) and your screenRIG sign-in."
                }
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(14)
                  Label { text: root.needsPlugin ? "1" : "󰄬"; color: root.needsPlugin ? root.dim : root.accent; font.bold: true; Layout.preferredWidth: Style.space(20) }
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)
                    Label { text: "Install the screenRIG plugin for " + (root.onboarding.agent_name || "your agent") }
                    Label {
                      Layout.fillWidth: true
                      meta: true
                      wrapMode: Text.Wrap
                      text: !root.needsPlugin ? "Installed"
                        : root.onboarding.installable
                          ? "Runs " + (root.onboarding.agent || "the agent") + "'s plugin install from github.com/screenrig/plugin."
                          : "Install it from github.com/screenrig/plugin, then open the panel again."
                    }
                  }
                  PrimaryButton {
                    visible: root.needsPlugin && !!root.onboarding.installable
                    busy: root.installingPlugin
                    iconText: "󰏗"
                    text: root.installingPlugin ? "Installing" : "Install"
                    enabled: !root.installingPlugin
                    onClicked: root.installPlugin()
                  }
                }
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(14)
                  Label { text: root.needsSignIn ? "2" : "󰄬"; color: root.needsSignIn ? root.dim : root.accent; font.bold: true; Layout.preferredWidth: Style.space(20) }
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)
                    Label { text: "Sign in to screenRIG" }
                    Label {
                      Layout.fillWidth: true
                      meta: true
                      wrapMode: Text.Wrap
                      text: !root.needsSignIn ? "Signed in"
                        : root.svc && root.svc.pendingLogin ? "Approve code " + root.svc.pendingLogin.code + " in the browser."
                        : "Opens screenrig.ai in your browser to approve this laptop."
                    }
                  }
                  PrimaryButton {
                    visible: root.needsSignIn
                    busy: !!root.svc && !!root.svc.pendingLogin
                    iconText: "󰍂"
                    text: root.svc && root.svc.pendingLogin ? "Open again" : "Sign in"
                    enabled: !root.needsPlugin
                    onClicked: root.signIn()
                  }
                }
              }
            }

            // -------------------------------------------------------- screens
            View {
              name: "screens"
              Layout.fillHeight: true

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)
                Segmented {
                  underline: true
                  items: [
                    { id: "all", label: "All", icon: "󰕰", count: root.countWhere(null) },
                    { id: "online", label: "Online", dot: "online", count: root.countWhere(true) },
                    { id: "offline", label: "Offline", dot: "offline", count: root.countWhere(false) }
                  ]
                  current: root.screenFilter
                  onPicked: function(id) { root.screenFilter = id }
                }
                Field {
                  Layout.fillWidth: true
                  glyph: "󰍉"
                  placeholderText: "Search screens and playlists"
                  text: root.search
                  onTextEdited: root.search = text
                }
              }

              // As tall as the grid's rows (one blank row at least); the panel caps it and the grid scrolls.
              Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                readonly property int rows: Math.max(1, Math.ceil(root.visibleScreens.length / grid.columns))
                Layout.preferredHeight: Math.max(rows * grid.cellHeight - grid.tileGutter * 2, root.picker ? Style.space(460) : 0)

                Label {
                  anchors.centerIn: parent
                  visible: !root.svc || !root.svc.ready || root.visibleScreens.length === 0
                  meta: true
                  text: !root.svc || !root.svc.ready
                    ? (root.svc && root.svc.lastError !== "" ? root.svc.lastError : "Loading screens")
                    : "No screens match"
                }

                GridView {
                  id: grid
                  anchors.fill: parent
                  anchors.margins: -tileGutter
                  visible: !!root.svc && root.svc.ready
                  clip: true
                  model: root.visibleScreens
                  boundsBehavior: Flickable.StopAtBounds
                  cacheBuffer: 2000

                  readonly property real tileGutter: root.gap / 2
                  readonly property real tilePad: Style.space(8)
                  readonly property int columns: Math.max(1, Math.floor(width / Style.space(300)))
                  readonly property real thumbHeight: (cellWidth - tileGutter * 2 - tilePad * 2) * 9 / 16
                  readonly property real infoHeight: Style.space(14) + Math.ceil(bodyMetrics.height) + Style.space(5) + Math.ceil(metaMetrics.height) + Style.space(14)
                  cellWidth: Math.floor(width / columns)
                  cellHeight: tileGutter * 2 + tilePad + thumbHeight + infoHeight

                  delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property var s: modelData
                    readonly property var restart: root.restartAction(s)
                    readonly property bool hot: tileHover.hovered
                    readonly property bool focused: root.focusId === s.id
                    width: grid.cellWidth
                    height: grid.cellHeight

                    // Staggered entrance each time the panel opens.
                    property real arrive: root.revealed ? 1 : 0
                    Behavior on arrive {
                      SequentialAnimation {
                        PauseAnimation { duration: root.revealed ? root.d(Math.min(tile.index, 12) * 32) : 0 }
                        NumberAnimation { duration: root.d(440); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.easeOut }
                      }
                    }
                    opacity: arrive

                    property real lift: hot ? 1 : 0
                    Behavior on lift { NumberAnimation { duration: root.d(220); easing.type: Easing.OutCubic } }

                    HoverHandler { id: tileHover }

                    Item {
                      id: tileBody
                      anchors.fill: parent
                      anchors.margins: grid.tileGutter
                      transform: Translate { y: (1 - tile.arrive) * Style.space(14) - tile.lift * Style.space(3) }

                      // Lift shadow.
                      Rectangle {
                        anchors.fill: parent
                        radius: root.rTile
                        color: root.raised
                        opacity: tile.lift
                        layer.enabled: true
                        layer.effect: MultiEffect {
                          shadowEnabled: true
                          shadowColor: "black"
                          shadowBlur: 0.8
                          shadowOpacity: 0.65
                          shadowVerticalOffset: Style.space(10)
                        }
                      }

                      Rectangle {
                        anchors.fill: parent
                        radius: root.rTile
                        gradient: Gradient {
                          GradientStop { position: 0; color: Qt.tint(root.raised, Util.alpha(root.fg, 0.02)) }
                          GradientStop { position: 1; color: root.raised }
                        }
                        border.width: tile.focused ? 2 : 1
                        border.color: tile.focused ? root.accent
                          : (tile.hot ? Util.alpha(root.accent, 0.55) : root.line)
                        Behavior on border.color { ColorAnimation { duration: root.d(200) } }
                      }

                      // Screenshot.
                      Well {
                        id: thumb
                        x: grid.tilePad
                        y: grid.tilePad
                        width: parent.width - grid.tilePad * 2
                        height: grid.thumbHeight
                        radius: root.rTile - Style.space(3)

                        Rectangle { anchors.fill: parent; color: root.well }
                        Logomark {
                          visible: !tile.s.shot || shotImage.status !== Image.Ready
                          anchors.centerIn: parent
                          anchors.verticalCenterOffset: -Style.space(8)
                          size: Style.space(34)
                          color: Util.alpha(root.fg, 0.10)
                        }
                        Label {
                          visible: !tile.s.shot
                          anchors.horizontalCenter: parent.horizontalCenter
                          anchors.top: parent.verticalCenter
                          anchors.topMargin: Style.space(18)
                          meta: true
                          color: Util.alpha(root.fg, 0.35)
                          text: "No screenshot yet"
                        }
                        Image {
                          id: shotImage
                          anchors.fill: parent
                          source: tile.s.shot ? "file://" + tile.s.shot + "?" + tile.s.shot_mtime + "-" + root.shotBump : ""
                          cache: false
                          asynchronous: true
                          fillMode: Image.PreserveAspectFit
                          opacity: status === Image.Ready ? (tile.s.online ? 1 : 0.32) : 0
                          Behavior on opacity { NumberAnimation { duration: root.d(420) } }
                          scale: tile.hot ? 1.045 : 1
                          Behavior on scale { NumberAnimation { duration: root.d(700); easing.type: Easing.OutCubic } }
                        }
                        // Bottom shade for the action bar.
                        Rectangle {
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.bottom: parent.bottom
                          height: parent.height * 0.5
                          opacity: tile.lift
                          gradient: Gradient {
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) }
                          }
                        }
                      }

                      // State pill, top left.
                      Rectangle {
                        x: thumb.x + Style.space(8)
                        y: thumb.y + Style.space(8)
                        height: Style.space(22)
                        width: pillRow.implicitWidth + Style.space(18)
                        radius: height / 2
                        color: Qt.rgba(0, 0, 0, 0.62)
                        border.color: Util.alpha("white", 0.08)
                        Row {
                          id: pillRow
                          anchors.centerIn: parent
                          spacing: Style.space(6)
                          PulseDot {
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: Style.space(6)
                            color: tile.s.online ? root.onlineColor : root.offlineColor
                            pulse: tile.s.online
                          }
                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tile.s.online ? "LIVE" : "OFFLINE"
                            color: tile.s.online ? "white" : root.offlineColor
                            font.family: root.fontFamily
                            font.pixelSize: root.metaSize
                            font.bold: true
                            font.letterSpacing: 1
                          }
                        }
                      }

                      // Override or display-off, top right.
                      Rectangle {
                        visible: tile.s.online && (tile.s.display_off || tile.s.has_takeover)
                        anchors.right: thumb.right
                        anchors.rightMargin: Style.space(8)
                        y: thumb.y + Style.space(8)
                        height: Style.space(22)
                        width: statePill.implicitWidth + Style.space(18)
                        radius: height / 2
                        color: Util.alpha(root.accent, 0.92)
                        Text {
                          id: statePill
                          anchors.centerIn: parent
                          text: tile.s.display_off ? "DISPLAY OFF" : "OVERRIDE" + root.minutesLeft(tile.s.takeover_until).toUpperCase()
                          color: root.onAccent
                          font.family: root.fontFamily
                          font.pixelSize: root.metaSize
                          font.bold: true
                          font.letterSpacing: 1
                        }
                      }

                      // Floating action bar on hover.
                      Rectangle {
                        id: actionBar
                        anchors.horizontalCenter: thumb.horizontalCenter
                        y: thumb.y + thumb.height - height - Style.space(10) + (1 - tile.lift) * Style.space(10)
                        width: actionRow.implicitWidth + Style.space(10)
                        height: actionRow.implicitHeight + Style.space(8)
                        radius: root.rTile
                        color: Qt.rgba(0.06, 0.06, 0.07, 0.82)
                        border.color: Util.alpha("white", 0.10)
                        opacity: tile.lift
                        visible: opacity > 0.01
                        Row {
                          id: actionRow
                          anchors.centerIn: parent
                          spacing: Style.space(2)
                          Repeater {
                            model: [
                              { icon: "󰑓", tip: "Reload", go: "reload", ok: true },
                              { icon: "󰲸", tip: "Switch playlist", go: "pick-switch", ok: true },
                              { icon: tile.s.display_off ? "󰍹" : "󰶐", tip: tile.s.display_off ? "Turn the display back on" : "Turn the display off", go: tile.s.display_off ? "display-on" : "display-off", ok: true },
                              { icon: "󱐋", tip: tile.s.has_takeover ? "End the override" : "Override with a playlist for a while", go: tile.s.has_takeover ? "end-override" : "pick-override", ok: true },
                              { icon: "󰄀", tip: tile.s.online ? "Take a fresh screenshot" : "Offline: no fresh screenshot", go: "shot", ok: tile.s.online },
                              { icon: "󰜉", tip: tile.restart.tip, go: tile.restart.action, ok: tile.restart.action !== "" },
                              { icon: "󰏌", tip: "Open in the dashboard", go: "dashboard", ok: true }
                            ]
                            Button {
                              required property var modelData
                              radius: root.rControl - Style.space(2)
                              iconText: modelData.icon
                              tooltipText: modelData.tip
                              foreground: "white"
                              opacity: modelData.ok ? 1 : 0.3
                              onClicked: {
                                var a = modelData.go
                                if (!modelData.ok) return
                                if (a === "pick-switch") root.picker = { screenId: tile.s.id, label: tile.s.label, action: "switch" }
                                else if (a === "pick-override") root.picker = { screenId: tile.s.id, label: tile.s.label, action: "override" }
                                else if (a === "dashboard") Qt.openUrlExternally("https://screenrig.ai/dashboard/screens/" + tile.s.id)
                                else if (a === "shot") root.svc.run(["act", tile.s.id, "shot"], function(ok, message) {
                                  root.svc.report(ok, message)
                                  root.shotBump++
                                })
                                else root.svc.act(tile.s.id, a)
                              }
                            }
                          }
                        }
                      }

                      // Name, seen, playlist.
                      Column {
                        x: grid.tilePad + Style.space(4)
                        y: thumb.y + thumb.height + Style.space(14)
                        width: parent.width - grid.tilePad * 2 - Style.space(8)
                        spacing: Style.space(5)
                        RowLayout {
                          width: parent.width
                          spacing: Style.space(8)
                          Label { Layout.fillWidth: true; text: tile.s.label; font.bold: true }
                          Label {
                            meta: true
                            text: "seen " + root.ago(tile.s.online ? tile.s.last_seen_at : (tile.s.last_online_at || tile.s.last_seen_at))
                          }
                        }
                        Label {
                          width: parent.width
                          meta: true
                          text: "▶  " + (tile.s.playing_name || "nothing")
                            + (tile.s.playing_source && tile.s.playing_source !== "default" ? "  ·  " + tile.s.playing_source : "")
                        }
                      }
                    }
                  }
                }

                // Playlist sheet for switch and override, sliding in from the right.
                Rectangle {
                  anchors.fill: parent
                  color: Qt.rgba(0, 0, 0, 0.45 * sheet.shown)
                  radius: root.rTile
                  visible: sheet.shown > 0.01
                  MouseArea { anchors.fill: parent; onClicked: root.picker = null }
                }
                Rectangle {
                  id: sheet
                  property real shown: root.picker ? 1 : 0
                  Behavior on shown { NumberAnimation { duration: root.d(360); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.easeOut } }
                  visible: shown > 0.01
                  width: Math.min(Style.space(460), parent.width)
                  height: parent.height
                  x: parent.width - width * shown
                  radius: root.rTile
                  color: root.surfaceTop
                  border.color: root.lineStrong
                  property var lastPicker: null
                  Connections {
                    target: root
                    function onPickerChanged() { if (root.picker) sheet.lastPicker = root.picker }
                  }
                  MouseArea { anchors.fill: parent; onClicked: {} }

                  ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.pad
                    spacing: root.gap
                    RowLayout {
                      Layout.fillWidth: true
                      Label {
                        Layout.fillWidth: true
                        title: true
                        text: sheet.lastPicker ? (sheet.lastPicker.action === "switch" ? "Switch playlist" : "Override") : ""
                      }
                      Item {
                        implicitWidth: root.controlHeight; implicitHeight: root.controlHeight
                        Label { anchors.centerIn: parent; text: "󰅖"; color: root.dim }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.picker = null }
                      }
                    }
                    Label {
                      Layout.fillWidth: true
                      meta: true
                      text: sheet.lastPicker ? sheet.lastPicker.label + (sheet.lastPicker.action === "switch" ? " plays this from now on" : " plays this, then returns to its own playlist") : ""
                    }
                    Segmented {
                      visible: !!sheet.lastPicker && sheet.lastPicker.action === "override"
                      Layout.fillWidth: true
                      equal: true
                      items: [{ id: "10", label: "10 min" }, { id: "30", label: "30 min" }, { id: "60", label: "1 h" }, { id: "240", label: "4 h" }]
                      current: String(root.pickMinutes)
                      onPicked: function(id) { root.pickMinutes = Number(id) }
                    }
                    Hairline {}
                    ListView {
                      Layout.fillWidth: true
                      Layout.fillHeight: true
                      clip: true
                      spacing: Style.space(2)
                      model: root.svc ? root.svc.playlists : []
                      delegate: Rectangle {
                        id: plRow
                        required property var modelData
                        width: ListView.view.width
                        height: Math.ceil(bodyMetrics.height) + Style.space(20)
                        radius: root.rControl
                        color: plMouse.containsMouse ? Util.alpha(root.fg, 0.07) : "transparent"
                        Behavior on color { ColorAnimation { duration: root.d(120) } }
                        RowLayout {
                          anchors.fill: parent
                          anchors.leftMargin: Style.space(10)
                          anchors.rightMargin: Style.space(10)
                          spacing: Style.space(10)
                          Label { text: "󰲸"; color: plMouse.containsMouse ? root.accent : root.dim }
                          Label { Layout.fillWidth: true; text: plRow.modelData.name }
                          Label { visible: !plRow.modelData.approved; meta: true; text: "awaiting approval" }
                          Label { text: "→"; meta: true; opacity: plMouse.containsMouse ? 1 : 0; Behavior on opacity { NumberAnimation { duration: root.d(120) } } }
                        }
                        MouseArea {
                          id: plMouse
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            var p = root.picker
                            root.picker = null
                            if (p.action === "switch") root.svc.act(p.screenId, "switch", plRow.modelData.id)
                            else root.svc.act(p.screenId, "override", plRow.modelData.id + ":" + root.pickMinutes)
                          }
                        }
                      }
                    }
                  }
                }
              }
            }

            // ----------------------------------------------------------- cast
            View {
              id: castView
              name: "cast"
              Layout.fillHeight: true
              Layout.minimumHeight: 0

              Segmented {
                visible: !root.casting
                Layout.fillWidth: true
                equal: true
                items: [
                  { id: "live", label: "Live", icon: "󰑋" },
                  { id: "capture", label: "Capture", icon: "󰹑" },
                  { id: "clipboard", label: "Clipboard", icon: "󰅇" },
                  { id: "file", label: "File", icon: "󰈙" }
                ]
                current: root.sendSource === "live" ? "live" : (root.sendKind !== "" ? root.sendSource : "")
                onPicked: function(id) {
                  if (id === "live") { root.sendSource = "live"; root.sendKind = ""; if (root.svc) root.svc.loadLiveTargets() }
                  else if (id === "capture") { root.dismiss(); root.runDetached(["capture"]) }
                  else if (id === "clipboard") root.runDetached(["clip"])
                  else { root.dismiss(); root.runDetached(["pick-file"]) }
                }
              }

              // Casting now: a large status in place of the pickers.
              RowLayout {
                id: liveNow
                visible: root.casting
                Layout.fillWidth: true
                spacing: root.pad * 1.5
                readonly property var info: root.svc ? root.svc.live : ({})
                readonly property real untilMs: info.until ? Date.parse(info.until) : 0
                readonly property real startedMs: (info.started_at || 0) * 1000
                readonly property real leftMs: untilMs ? Math.max(0, untilMs - root.tickMs) : 0
                readonly property real fixedMs: untilMs && startedMs ? untilMs - startedMs : 0

                // What the screens see, live.
                Well {
                  Layout.preferredWidth: castView.width * 0.56
                  Layout.preferredHeight: Layout.preferredWidth * 10 / 16
                  radius: root.rTile
                  Rectangle { anchors.fill: parent; color: root.well }
                  ScreencopyView {
                    id: nowCopy
                    anchors.centerIn: parent
                    readonly property real aspect: sourceSize.width > 0 ? sourceSize.width / sourceSize.height : 16 / 10
                    width: Math.min(parent.width, parent.height * aspect)
                    height: width / aspect
                    captureSource: root.casting ? root.captureFor(liveNow.info.source) : null
                    constraintSize: Qt.size(960, 600)
                    live: root.casting && castView.visible && root.revealed
                    opacity: hasContent ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: root.d(300) } }
                  }
                  Rectangle {
                    x: Style.space(12); y: Style.space(12)
                    height: Style.space(26)
                    width: nowPill.implicitWidth + Style.space(22)
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.66)
                    border.color: Util.alpha("white", 0.1)
                    Row {
                      id: nowPill
                      anchors.centerIn: parent
                      spacing: Style.space(8)
                      PulseDot { anchors.verticalCenter: parent.verticalCenter; color: root.offlineColor; pulse: true }
                      Text { anchors.verticalCenter: parent.verticalCenter; text: "LIVE"; color: "white"; font.family: root.fontFamily; font.pixelSize: root.metaSize; font.bold: true; font.letterSpacing: 1.4 }
                    }
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.alignment: Qt.AlignVCenter
                  spacing: Style.space(10)

                  Text {
                    text: "CASTING"
                    color: root.offlineColor
                    font.family: root.fontFamily
                    font.pixelSize: root.metaSize
                    font.bold: true
                    font.letterSpacing: 1.6
                  }
                  Label {
                    Layout.fillWidth: true
                    title: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    text: liveNow.info.label || "Desktop"
                  }
                  Label {
                    Layout.fillWidth: true
                    meta: true
                    wrapMode: Text.Wrap
                    text: "on " + root.screenNames(liveNow.info.screens || [])
                  }

                  Item { implicitHeight: Style.space(8) }

                  // Countdown when the cast has an end, else how long it has been live.
                  Text {
                    text: root.clock(liveNow.untilMs ? liveNow.leftMs : root.tickMs - liveNow.startedMs)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: root.titleSize * 3.6
                    font.bold: true
                    font.features: { "tnum": 1 }
                  }
                  Label {
                    meta: true
                    text: liveNow.untilMs ? "left · ends at " + new Date(liveNow.untilMs).toLocaleTimeString(Qt.locale(), "h:mm AP") : "live, until you stop it"
                  }
                  // Time left, as a draining bar.
                  Rectangle {
                    visible: liveNow.fixedMs > 0
                    Layout.fillWidth: true
                    implicitHeight: Style.space(4)
                    radius: height / 2
                    color: Util.alpha(root.fg, 0.08)
                    Rectangle {
                      height: parent.height
                      radius: height / 2
                      color: root.accent
                      width: liveNow.fixedMs > 0 ? parent.width * liveNow.leftMs / liveNow.fixedMs : 0
                      Behavior on width { NumberAnimation { duration: 950; easing.type: Easing.Linear } }
                    }
                  }

                  Item { implicitHeight: Style.space(8) }

                  // Stop: large and unmistakable.
                  Item {
                    Layout.fillWidth: true
                    implicitHeight: root.controlHeight + Style.space(16)
                    Rectangle {
                      anchors.fill: parent
                      radius: root.rTile
                      color: stopMouse.pressed ? Qt.darker(root.offlineColor, 1.15) : (stopMouse.containsMouse ? Qt.lighter(root.offlineColor, 1.08) : root.offlineColor)
                      Behavior on color { ColorAnimation { duration: root.d(140) } }
                      layer.enabled: true
                      layer.effect: MultiEffect { shadowEnabled: true; shadowColor: root.offlineColor; shadowBlur: 0.9; shadowOpacity: stopMouse.containsMouse ? 0.5 : 0.25; shadowVerticalOffset: 2 }
                    }
                    Row {
                      anchors.centerIn: parent
                      spacing: Style.space(10)
                      Text { text: root.stopping ? "󰔟" : "󰓛"; color: "white"; font.family: root.fontFamily; font.pixelSize: root.titleSize; anchors.verticalCenter: parent.verticalCenter }
                      Text { text: root.stopping ? "Stopping" : "Stop casting"; color: "white"; font.family: root.fontFamily; font.pixelSize: root.titleSize; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    }
                    scale: stopMouse.pressed ? 0.98 : 1
                    Behavior on scale { NumberAnimation { duration: root.d(120) } }
                    MouseArea {
                      id: stopMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.stopCast()
                    }
                  }
                }
              }

              RowLayout {
                visible: !root.casting
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 0
                spacing: root.pad

                // What to cast: live thumbnails, or the captured image, link or file.
                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.minimumHeight: 0
                  Layout.alignment: Qt.AlignTop
                  Layout.horizontalStretchFactor: root.sendSource === "live" ? 3 : 1
                  Layout.preferredWidth: root.sendSource === "live" ? 3 : 1
                  spacing: root.gap

                  // Live sources: each monitor, then each app window, one grid.
                  GridView {
                    id: sourceGrid
                    visible: root.sendSource === "live"
                    // Arrow keys move the selection, Return goes live.
                    keyNavigationEnabled: true
                    focus: true
                    highlightFollowsCurrentItem: false
                    function syncIndex() {
                      var list = root.liveSourceList
                      for (var i = 0; i < list.length; i++) if (list[i].id === root.liveSource) { currentIndex = i; return }
                    }
                    function revealCurrent() {
                      if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)
                    }
                    onHeightChanged: Qt.callLater(revealCurrent)
                    Connections {
                      target: root
                      function onLiveSourceChanged() { sourceGrid.syncIndex() }
                      function onLiveSourceListChanged() { sourceGrid.syncIndex() }
                    }
                    Component.onCompleted: syncIndex()
                    onCurrentIndexChanged: {
                      var item = root.liveSourceList[currentIndex]
                      if (item && item.id !== root.liveSource) { root.liveSource = item.id; root.liveLabel = item.title }
                      Qt.callLater(revealCurrent)
                    }
                    Keys.onReturnPressed: root.goLive()
                    Keys.onEnterPressed: root.goLive()
                    Layout.fillWidth: true
                    // Leave room for setup, consent and the Cast action; scroll the sources.
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    Layout.preferredHeight: cellHeight * Math.max(1, Math.min(3, Math.ceil(count / columns)))
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    readonly property int columns: Math.max(2, Math.floor(width / Style.space(200)))
                    cellWidth: Math.floor(width / columns)
                    cellHeight: (cellWidth - Style.space(12)) * 10 / 16 + Math.ceil(bodyMetrics.height) + Math.ceil(metaMetrics.height) + Style.space(26)
                    model: root.liveSources()
                    delegate: Item {
                      id: srcCell
                      required property var modelData
                      readonly property bool chosen: root.liveSource === modelData.id
                      width: sourceGrid.cellWidth
                      height: sourceGrid.cellHeight
                      property real hot: srcMouse.containsMouse ? 1 : 0
                      Behavior on hot { NumberAnimation { duration: root.d(180); easing.type: Easing.OutCubic } }
                      Column {
                        x: Style.space(6)
                        y: Style.space(6)
                        width: parent.width - Style.space(12)
                        spacing: Style.space(6)
                        Well {
                          id: thumbWell
                          width: parent.width
                          height: width * 10 / 16
                          radius: root.rControl
                          transform: Translate { y: -srcCell.hot * Style.space(2) }
                          Rectangle { anchors.fill: parent; color: root.well }
                          ScreencopyView {
                            id: copy
                            anchors.centerIn: parent
                            readonly property real aspect: sourceSize.width > 0 ? sourceSize.width / sourceSize.height : 16 / 10
                            width: Math.min(parent.width, parent.height * aspect)
                            height: width / aspect
                            captureSource: srcCell.modelData.capture
                            constraintSize: Qt.size(480, 300)
                            live: castView.visible && root.revealed && (srcCell.chosen || srcMouse.containsMouse)
                            opacity: hasContent ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: root.d(300) } }
                          }
                          Label {
                            anchors.centerIn: parent
                            visible: !copy.hasContent
                            text: srcCell.modelData.kind === "screen" ? "󰍹" : "󰖯"
                            color: Util.alpha(root.fg, 0.25)
                            font.pixelSize: root.titleSize * 2
                          }
                        }
                        RowLayout {
                          width: parent.width
                          spacing: Style.space(6)
                          Label { text: srcCell.modelData.kind === "screen" ? "󰍹" : "󰖯"; meta: true; color: srcCell.chosen ? root.accent : root.dim }
                          Label { Layout.fillWidth: true; text: srcCell.modelData.title; font.bold: srcCell.chosen }
                        }
                        Label { width: parent.width; meta: true; text: srcCell.modelData.detail }
                      }
                      // Selection ring.
                      Rectangle {
                        x: Style.space(3); y: Style.space(3)
                        width: parent.width - Style.space(6)
                        height: thumbWell.height + Style.space(6)
                        radius: root.rControl + Style.space(3)
                        color: "transparent"
                        border.width: 2
                        border.color: srcCell.chosen ? root.accent : Util.alpha(root.accent, 0.4 * srcCell.hot)
                        Behavior on border.color { ColorAnimation { duration: root.d(160) } }
                      }
                      Timer {
                        // Refresh still thumbnails now and then.
                        interval: 3000
                        repeat: true
                        running: castView.visible && root.revealed && !copy.live
                        triggeredOnStart: true
                        onTriggered: copy.captureFrame()
                      }
                      MouseArea {
                        id: srcMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.liveSource = srcCell.modelData.id; root.liveLabel = srcCell.modelData.title }
                      }
                    }
                  }

                  Well {
                    visible: root.sendSource !== "live"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    Layout.preferredHeight: width * 9 / 16
                    radius: root.rTile
                    Rectangle { anchors.fill: parent; color: root.well }
                    Image {
                      id: preview
                      anchors.fill: parent
                      visible: root.sendKind === "file" && root.isImage(root.sendPath)
                      source: visible ? "file://" + root.sendPath : ""
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      opacity: status === Image.Ready ? 1 : 0
                      Behavior on opacity { NumberAnimation { duration: root.d(420) } }
                    }
                    Column {
                      anchors.centerIn: parent
                      visible: !preview.visible
                      spacing: Style.space(14)
                      Logomark {
                        anchors.horizontalCenter: parent.horizontalCenter
                        size: Style.space(44)
                        color: Util.alpha(root.fg, root.sendKind === "" ? 0.12 : 0.5)
                      }
                      Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(implicitWidth, preview.width - root.pad * 2)
                        horizontalAlignment: Text.AlignHCenter
                        meta: root.sendKind === ""
                        text: root.sendKind === "url" ? root.sendUrl
                          : (root.sendKind === "file" ? root.sendPath.split("/").pop()
                          : "Capture a region, use the clipboard, or pick a file")
                      }
                    }
                  }

                  Label {
                    Layout.fillWidth: true
                    meta: true
                    visible: root.sendSource !== "live" && root.sendKind !== ""
                    text: root.sendKind === "url" ? "Web page  ·  shown live on the screen"
                      : root.sendPath.split("/").pop()
                        + (preview.status === Image.Ready ? "  ·  " + preview.sourceSize.width + "×" + preview.sourceSize.height : "")
                  }
                }

                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: root.line }

                // Where to show it.
                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  Layout.minimumHeight: 0
                  Layout.alignment: Qt.AlignTop
                  Layout.horizontalStretchFactor: root.sendSource === "live" ? 2 : 1
                  Layout.preferredWidth: root.sendSource === "live" ? 2 : 1
                  spacing: Style.space(8)

                  RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.controlHeight
                    Label { Layout.fillWidth: true; text: "Show on"; title: true }
                    Label {
                      visible: root.castTargets().length > 0
                      text: root.allTargetsSelected() ? "Clear" : "Select all"
                      color: linkMouse.containsMouse ? Qt.lighter(root.accent, 1.15) : root.accent
                      MouseArea { id: linkMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectAllTargets() }
                    }
                  }
                  Label {
                    visible: root.sendSource === "live"
                    Layout.fillWidth: true
                    meta: true
                    wrapMode: Text.Wrap
                    text: !root.svc || !root.svc.liveTargets.ok ? "Finding Android and Qt screens on this network"
                      : (root.castTargets().length === 0
                        ? "No Android or Qt screens are on this network. Live casts reach screens on the same network as this laptop"
                          + (root.svc.liveTargets.elsewhere ? " (" + root.svc.liveTargets.elsewhere + " are elsewhere)." : ".")
                        : "Android and Qt screens on this network")
                  }
                  ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    Layout.preferredHeight: Math.min(contentHeight, (Math.ceil(bodyMetrics.height) + Style.space(20)) * 12)
                    clip: true
                    spacing: Style.space(2)
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.castTargets()
                    delegate: Rectangle {
                      id: sendRow
                      required property var modelData
                      readonly property bool picked: !!root.sendSelected[modelData.id]
                      width: ListView.view.width
                      height: Math.ceil(bodyMetrics.height) + Style.space(18)
                      radius: root.rControl
                      color: picked ? Util.alpha(root.accent, 0.08) : (rowMouse.containsMouse && modelData.online ? Util.alpha(root.fg, 0.05) : "transparent")
                      Behavior on color { ColorAnimation { duration: root.d(140) } }
                      opacity: modelData.online ? 1 : 0.4
                      RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(10)
                        anchors.rightMargin: Style.space(10)
                        spacing: Style.space(12)
                        Rectangle {
                          implicitWidth: Style.space(16); implicitHeight: implicitWidth
                          radius: Style.space(4)
                          color: sendRow.picked ? root.accent : "transparent"
                          border.color: sendRow.picked ? root.accent : root.lineStrong
                          Behavior on color { ColorAnimation { duration: root.d(140) } }
                          Text {
                            anchors.centerIn: parent
                            text: "󰄬"
                            color: root.onAccent
                            font.family: root.fontFamily
                            font.pixelSize: root.metaSize
                            font.bold: true
                            scale: sendRow.picked ? 1 : 0.2
                            opacity: sendRow.picked ? 1 : 0
                            Behavior on scale { NumberAnimation { duration: root.d(260); easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
                            Behavior on opacity { NumberAnimation { duration: root.d(120) } }
                          }
                        }
                        PulseDot { color: sendRow.modelData.online ? root.onlineColor : root.offlineColor; implicitWidth: Style.space(6) }
                        Label { Layout.fillWidth: true; Layout.preferredWidth: 3; text: sendRow.modelData.label }
                        Label {
                          Layout.fillWidth: true; Layout.preferredWidth: 2
                          horizontalAlignment: Text.AlignRight
                          meta: true
                          text: root.sendSource === "live" ? (sendRow.modelData.platform === "qt" ? "Linux" : "Android")
                            : (sendRow.modelData.online ? (sendRow.modelData.playing_name || "") : "Offline")
                        }
                      }
                      MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: sendRow.modelData.online
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggleSend(sendRow.modelData.id)
                      }
                    }
                  }
                }
              }

              // What live casting changes on this laptop, allowed once.
              Rectangle {
                visible: root.needsConsent && !root.casting
                Layout.fillWidth: true
                implicitHeight: consentRow.implicitHeight + Style.space(24)
                radius: root.rTile
                color: Util.alpha(root.accent, 0.08)
                border.color: Util.alpha(root.accent, 0.35)
                RowLayout {
                  id: consentRow
                  anchors.fill: parent
                  anchors.margins: Style.space(12)
                  anchors.leftMargin: Style.space(16)
                  spacing: Style.space(14)
                  Label { text: "󰒃"; color: root.accent; font.pixelSize: root.titleSize; Layout.alignment: Qt.AlignTop }
                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(4)
                    Label { text: "Allow live casting on this laptop"; font.bold: true }
                    Label {
                      visible: root.needsFirewall
                      Layout.fillWidth: true
                      meta: true
                      wrapMode: Text.Wrap
                      text: "The firewall (ufw) lets screens on " + (root.liveSetup.subnet || "your network") + " reach TCP " + (root.liveSetup.port || 8554)
                        + " here." + (root.liveSetup.firewall === "no-sudo" ? " This needs your password once: Allow shows the command." : "")
                    }
                    Label {
                      visible: root.needsPicker
                      Layout.fillWidth: true
                      meta: true
                      wrapMode: Text.Wrap
                      text: "Window casts answer the desktop's screen-share picker for the window you pick here; your own picker still handles every other screen share. Uninstalling restores it."
                    }
                  }
                  PrimaryButton {
                    iconText: "󰄬"; text: "Allow"
                    onClicked: root.allowLive()
                  }
                }
              }

              Hairline { visible: !root.casting }

              RowLayout {
                visible: !root.casting
                Layout.fillWidth: true
                spacing: Style.space(12)
                Label { text: "Show for"; meta: true }
                Segmented {
                  visible: root.sendSource === "live"
                  items: [{ id: "15", label: "15 min" }, { id: "60", label: "1 h" }, { id: "240", label: "4 h" }, { id: "0", label: "Until I stop" }]
                  current: String(root.liveMinutes)
                  onPicked: function(id) { root.liveMinutes = Number(id) }
                }
                Segmented {
                  visible: root.sendSource !== "live"
                  items: [{ id: "5", label: "5 min" }, { id: "10", label: "10 min" }, { id: "30", label: "30 min" }, { id: "60", label: "1 h" }]
                  current: String(root.sendMinutes)
                  onPicked: function(id) { root.sendMinutes = Number(id) }
                }
                Item { Layout.fillWidth: true }
                PrimaryButton {
                  readonly property int n: root.selectedIds().length
                  readonly property bool liveMode: root.sendSource === "live"
                  busy: root.sending
                  iconText: liveMode ? "󰑋" : "󰄘"
                  text: root.sending ? (liveMode ? "Going live" : "Casting")
                    : (n === 0 ? "Pick screens" : (liveMode ? "Go live on " : "Cast to ") + n + " screen" + (n === 1 ? "" : "s"))
                  enabled: n > 0 && !root.sending && (liveMode ? root.liveSource !== "" && !root.needsConsent : root.sendKind !== "")
                  onClicked: liveMode ? root.goLive() : root.doSend()
                }
              }
            }

            // --------------------------------------------------------- player
            View {
              name: "player"

              RowLayout {
                Layout.fillWidth: true
                spacing: root.gap
                Rectangle {
                  Layout.alignment: Qt.AlignTop
                  implicitWidth: Style.space(44); implicitHeight: implicitWidth; radius: root.rTile
                  color: Util.alpha(root.playerInfo.running ? root.onlineColor : root.accent, 0.12)
                  border.color: Util.alpha(root.playerInfo.running ? root.onlineColor : root.accent, 0.35)
                  Behavior on color { ColorAnimation { duration: root.d(240) } }
                  Label { anchors.centerIn: parent; text: "󰐊"; color: root.playerInfo.running ? root.onlineColor : root.accent; font.pixelSize: root.titleSize }
                }
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(6)
                  Label { text: "Make this machine a screen"; title: true }
                  Label {
                    Layout.fillWidth: true
                    meta: true
                    wrapMode: Text.Wrap
                    text: "The screenRIG Player for Linux runs fullscreen on the monitor you pick and joins "
                      + (root.svc && root.svc.project.name ? root.svc.project.name : "the project")
                      + " as its own screen through this machine's fleet link. No pairing code. Close it with Stop or Super+W."
                  }
                }
              }

              Hairline {}

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)
                visible: !!root.playerInfo.native
                Label { text: "Monitor"; meta: true }
                Segmented {
                  items: (root.playerInfo.monitors || []).map(function(m) { return { id: m.name, label: m.name + "  " + m.width + "×" + m.height, icon: "󰍹" } })
                  current: root.playerMonitor
                  onPicked: function(id) { root.playerMonitor = id }
                }
                Item { Layout.fillWidth: true }
                Row {
                  spacing: Style.space(8)
                  PulseDot { anchors.verticalCenter: parent.verticalCenter; color: root.playerInfo.running ? root.onlineColor : root.dim; pulse: !!root.playerInfo.running }
                  Label { anchors.verticalCenter: parent.verticalCenter; text: root.playerInfo.running ? "Running" : "Stopped"; meta: !root.playerInfo.running }
                }
                PrimaryButton {
                  visible: !root.playerInfo.running
                  iconText: "󰐊"; text: "Start"
                  busy: root.playerBusy
                  enabled: !root.playerBusy
                  onClicked: {
                    root.playerBusy = true
                    root.svc.run(["player", "start", "--monitor", root.playerMonitor], function(ok, message) {
                      root.playerBusy = false
                      root.svc.report(ok, message)
                      if (ok) { headerLogo.celebrate(); root.dismiss() }
                    })
                  }
                }
                QuietButton {
                  visible: !!root.playerInfo.running
                  iconText: "󰓛"; text: "Stop"
                  onClicked: root.svc.run(["player", "stop"], function(ok, message) {
                    root.svc.report(ok, message)
                    root.refreshPlayer()
                  })
                }
              }

              // No Player yet: point at the Linux Player download.
              Label {
                visible: !root.playerInfo.native
                Layout.fillWidth: true
                meta: true
                wrapMode: Text.Wrap
                text: "Install the screenRIG Player for Linux from screenrig.ai/docs/players to run it here."
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)
                Rectangle {
                  implicitHeight: Style.space(24)
                  implicitWidth: linkRow.implicitWidth + Style.space(20)
                  radius: height / 2
                  color: Util.alpha(root.playerInfo.provisioned ? root.onlineColor : root.fg, 0.08)
                  border.color: Util.alpha(root.playerInfo.provisioned ? root.onlineColor : root.fg, 0.2)
                  Row {
                    id: linkRow
                    anchors.centerIn: parent
                    spacing: Style.space(8)
                    Label { anchors.verticalCenter: parent.verticalCenter; text: "󰌹"; color: root.playerInfo.provisioned ? root.onlineColor : root.dim }
                    Label {
                      anchors.verticalCenter: parent.verticalCenter
                      meta: true
                      text: root.playerInfo.provisioned ? "Fleet link ready" : "A fleet link is made on first start"
                    }
                  }
                }
                Item { Layout.fillWidth: true }
                Label {
                  visible: !!root.playerInfo.provisioned
                  text: "Forget this machine"
                  color: forgetMouse.containsMouse ? root.fg : root.dim
                  font.underline: forgetMouse.containsMouse
                  MouseArea {
                    id: forgetMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.svc.run(["player", "forget"], function(ok, message) {
                      root.svc.report(ok, message)
                      root.refreshPlayer()
                    })
                  }
                }
              }
            }

            // ---------------------------------------------------------- agent
            View {
              id: agentView
              name: "agent"
              Layout.fillHeight: true

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)
                Rectangle {
                  implicitHeight: Style.space(26)
                  implicitWidth: agentBadge.implicitWidth + Style.space(22)
                  radius: height / 2
                  color: Util.alpha(root.accent, 0.10)
                  border.color: Util.alpha(root.accent, 0.3)
                  Row {
                    id: agentBadge
                    anchors.centerIn: parent
                    spacing: Style.space(8)
                    PulseDot {
                      anchors.verticalCenter: parent.verticalCenter
                      color: root.svc && root.svc.agentRunning ? root.accent : root.onlineColor
                      pulse: !!root.svc && root.svc.agentRunning
                    }
                    Label {
                      anchors.verticalCenter: parent.verticalCenter
                      text: root.svc && root.svc.agentName ? root.svc.agentName : "Agent"
                      font.bold: true
                    }
                  }
                }
                Label {
                  meta: true
                  text: root.svc && root.svc.agentRunning ? "working" : (root.svc && root.svc.chat.count ? "resumes this conversation" : "")
                }
                Item { Layout.fillWidth: true }
                QuietButton {
                  iconText: "󰐕"; text: "New chat"
                  enabled: !!root.svc && !root.svc.agentRunning && root.svc.chat.count > 0
                  opacity: enabled ? 1 : 0.4
                  onClicked: root.svc.agentReset()
                }
              }

              // Transcript.
              Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Column {
                  anchors.centerIn: parent
                  visible: !!root.svc && root.svc.chat.count === 0
                  spacing: Style.space(16)
                  LogoCharacter {
                    anchors.horizontalCenter: parent.horizontalCenter
                    size: Style.space(84)
                    alive: agentView.visible && root.revealed
                  }
                  Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    meta: true
                    text: (root.svc && root.svc.agentName ? root.svc.agentName : "Your agent") + "  ·  "
                      + (root.svc && root.svc.project.name ? root.svc.project.name : "")
                  }
                }

                ListView {
                  id: chatList
                  anchors.fill: parent
                  clip: true
                  spacing: Style.space(10)
                  model: root.svc ? root.svc.chat : null
                  boundsBehavior: Flickable.StopAtBounds
                  property bool follow: true
                  onMovementEnded: follow = atYEnd
                  Connections {
                    target: root.svc
                    function onChatUpdated() { if (chatList.follow) Qt.callLater(function() { chatList.positionViewAtEnd() }) }
                  }
                  footer: Item {
                    width: chatList.width
                    height: root.svc && root.svc.agentRunning ? Style.space(36) : Style.space(4)
                    Row {
                      visible: !!root.svc && root.svc.agentRunning
                      x: Style.space(4)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(6)
                      Repeater {
                        model: 3
                        Rectangle {
                          id: typingDot
                          required property int index
                          width: Style.space(7); height: width; radius: width / 2
                          color: root.accent
                          opacity: 0.25
                          SequentialAnimation on opacity {
                            running: !!root.svc && root.svc.agentRunning && root.revealed
                            loops: Animation.Infinite
                            PauseAnimation { duration: typingDot.index * 160 }
                            NumberAnimation { to: 1; duration: 320; easing.type: Easing.OutCubic }
                            NumberAnimation { to: 0.25; duration: 420; easing.type: Easing.InCubic }
                            PauseAnimation { duration: (2 - typingDot.index) * 160 }
                          }
                        }
                      }
                    }
                  }

                  delegate: Item {
                    id: msg
                    required property int index
                    required property string role
                    required property string text
                    required property string title
                    required property string status
                    required property string output
                    width: chatList.width
                    height: role === "tool" ? toolRow.implicitHeight : bubble.height

                    property real arrive: 0
                    Component.onCompleted: arriveAnim.start()
                    NumberAnimation { id: arriveAnim; target: msg; property: "arrive"; from: 0; to: 1; duration: root.d(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.easeOut }
                    opacity: arrive
                    transform: Translate { y: (1 - msg.arrive) * Style.space(8) }

                    // User and agent messages, and errors.
                    Rectangle {
                      id: bubble
                      visible: msg.role !== "tool"
                      readonly property bool mine: msg.role === "user"
                      readonly property real maxWidth: chatList.width * (mine ? 0.72 : 0.86)
                      x: mine ? chatList.width - width : 0
                      width: Math.min(maxWidth, msgText.implicitWidth + Style.space(28))
                      height: msgText.implicitHeight + Style.space(20)
                      radius: root.rTile
                      color: mine ? Util.alpha(root.accent, 0.14)
                        : (msg.role === "error" ? Util.alpha(root.offlineColor, 0.10) : root.raised)
                      border.color: mine ? Util.alpha(root.accent, 0.35)
                        : (msg.role === "error" ? Util.alpha(root.offlineColor, 0.35) : root.line)
                      TextEdit {
                        id: msgText
                        x: Style.space(14)
                        y: Style.space(10)
                        width: bubble.width - Style.space(28)
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        textFormat: msg.role === "agent" ? TextEdit.MarkdownText : TextEdit.PlainText
                        text: msg.text
                        color: msg.role === "error" ? root.offlineColor : root.fg
                        selectionColor: Util.alpha(root.accent, 0.4)
                        font.family: root.fontFamily
                        font.pixelSize: root.bodySize
                      }
                    }

                    // A tool call: one quiet line.
                    RowLayout {
                      id: toolRow
                      visible: msg.role === "tool"
                      width: chatList.width
                      spacing: Style.space(10)
                      Item {
                        implicitWidth: Style.space(16); implicitHeight: Math.ceil(metaMetrics.height)
                        Label {
                          anchors.centerIn: parent
                          text: msg.status === "running" ? "󰔟" : (msg.status === "failed" ? "󰅖" : "󰄬")
                          color: msg.status === "running" ? root.accent : (msg.status === "failed" ? root.offlineColor : root.onlineColor)
                          meta: true
                          RotationAnimation on rotation { running: msg.status === "running" && root.revealed; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
                        }
                      }
                      Label { Layout.fillWidth: true; Layout.preferredWidth: 3; meta: true; text: msg.title; color: Util.alpha(root.fg, 0.72) }
                      Label {
                        visible: msg.status === "failed" && msg.output !== ""
                        Layout.fillWidth: true; Layout.preferredWidth: 2
                        meta: true
                        color: root.offlineColor
                        text: msg.output
                        horizontalAlignment: Text.AlignRight
                      }
                    }
                  }
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)
                Field {
                  id: agentField
                  Layout.fillWidth: true
                  implicitHeight: root.controlHeight + Style.space(10)
                  glyph: "󰚩"
                  placeholderText: "Message " + (root.svc && root.svc.agentName ? root.svc.agentName : "your agent")
                  onAccepted: if (root.svc && !root.svc.agentRunning) askButton.clicked()
                }
                PrimaryButton {
                  id: askButton
                  visible: !root.svc || !root.svc.agentRunning
                  implicitHeight: root.controlHeight + Style.space(10)
                  iconText: "󰒊"; text: "Send"
                  enabled: agentField.text.trim() !== ""
                  onClicked: {
                    chatList.follow = true
                    root.svc.agentSend(agentField.text)
                    agentField.text = ""
                  }
                }
                QuietButton {
                  visible: !!root.svc && root.svc.agentRunning
                  implicitHeight: root.controlHeight + Style.space(10)
                  iconText: "󰓛"; text: "Stop"
                  onClicked: root.svc.agentStop()
                }
              }
            }

            // ---------------------------------------------------------- theme
            View {
              id: themeView
              name: "theme"

              Label { text: "Match cards to your Omarchy theme"; title: true }
              Label {
                Layout.fillWidth: true
                meta: true
                wrapMode: Text.Wrap
                text: "Recolors every card in " + (root.svc && root.svc.project.name ? root.svc.project.name : "the project")
                  + " with this theme's accent, background and text. Restore puts each card's own colors back."
              }
              RowLayout {
                Layout.fillWidth: true
                spacing: root.pad

                // A card as it will look on glass, animating in.
                Item {
                  id: previewCard
                  Layout.fillWidth: true
                  implicitHeight: Style.space(190)
                  property real grow: themeView.visible && root.revealed ? 1 : 0
                  Behavior on grow { NumberAnimation { duration: root.d(1100); easing.type: Easing.OutCubic } }
                  Rectangle {
                    anchors.fill: parent
                    radius: root.rTile
                    color: Commons.Color.background
                    border.color: root.line
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowBlur: 0.7; shadowOpacity: 0.5; shadowVerticalOffset: Style.space(8) }
                  }
                  ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.pad
                    spacing: Style.space(6)
                    Label { text: "VISITORS TODAY"; color: Util.alpha(Commons.Color.foreground, 0.7); font.letterSpacing: 1.2; meta: true }
                    RowLayout {
                      Layout.fillWidth: true
                      Layout.fillHeight: true
                      spacing: root.pad
                      ColumnLayout {
                        spacing: Style.space(4)
                        Text {
                          text: Math.round(1284 * previewCard.grow).toLocaleString(Qt.locale(), "f", 0)
                          color: Commons.Color.foreground
                          font.family: root.fontFamily
                          font.pixelSize: root.titleSize * 3.2
                          font.bold: true
                        }
                        Label { text: "▲ 12% vs last week"; color: Commons.Color.accent }
                      }
                      Item { Layout.fillWidth: true }
                      Row {
                        Layout.alignment: Qt.AlignBottom
                        spacing: Style.space(7)
                        Repeater {
                          model: [0.42, 0.58, 0.5, 0.72, 0.64, 1.0]
                          Rectangle {
                            required property var modelData
                            required property int index
                            anchors.bottom: parent.bottom
                            width: Style.space(16)
                            height: Style.space(96) * modelData * Math.max(0, Math.min(1, previewCard.grow * 1.6 - index * 0.12))
                            radius: Style.space(3)
                            color: index === 5 ? Commons.Color.accent : Util.alpha(Commons.Color.foreground, 0.22)
                          }
                        }
                      }
                    }
                  }
                }

                ColumnLayout {
                  spacing: Style.space(12)
                  Repeater {
                    model: [
                      { name: "Accent", color: Commons.Color.accent },
                      { name: "Background", color: Commons.Color.background },
                      { name: "Text", color: Commons.Color.foreground }
                    ]
                    RowLayout {
                      required property var modelData
                      spacing: Style.space(12)
                      Rectangle {
                        implicitWidth: Style.space(44); implicitHeight: Style.space(44)
                        radius: root.rControl
                        color: modelData.color
                        border.color: root.lineStrong
                        Behavior on color { ColorAnimation { duration: root.d(600) } }
                      }
                      ColumnLayout {
                        spacing: Style.space(2)
                        Label { text: modelData.name }
                        Label { text: root.hex(modelData.color); meta: true }
                      }
                    }
                  }
                }
              }
              Hairline {}
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(14)
                PrimaryButton {
                  iconText: "󰏘"; text: "Match cards now"
                  onClicked: { root.svc.report(true, "Matching cards"); root.svc.run(["theme-sync", "apply"], function(ok, message) { root.svc.report(ok, message) }) }
                }
                ToggleSwitch {
                  checked: root.themeSyncOn
                  onToggled: root.svc.run(["theme-sync", root.themeSyncOn ? "off" : "on"], function(ok, message) {
                    root.svc.report(ok, message)
                    root.refreshTheme()
                  })
                }
                Label { text: "Keep matched when the theme changes" }
                Item { Layout.fillWidth: true }
                QuietButton {
                  iconText: "󰕍"; text: "Restore original colors"
                  onClicked: root.svc.run(["theme-sync", "restore"], function(ok, message) { root.svc.report(ok, message) })
                }
              }
            }
          }

          // Project menu: dismiss by clicking anywhere else.
          MouseArea {
            anchors.fill: parent
            visible: root.projectMenu
            onClicked: root.projectMenu = false
          }
          Rectangle {
            id: projectPop
            readonly property point at: projectButton.mapToItem(card, 0, projectButton.height)
            property real shown: root.projectMenu ? 1 : 0
            Behavior on shown { NumberAnimation { duration: root.d(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.easeOut } }
            visible: shown > 0.01
            opacity: shown
            x: at.x
            y: at.y + Style.space(6) - (1 - shown) * Style.space(6)
            width: Math.max(Style.space(320), projectButton.width)
            height: popColumn.implicitHeight + Style.space(12)
            radius: root.rTile
            color: root.surfaceTop
            border.color: root.lineStrong
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: "black"; shadowBlur: 0.8; shadowOpacity: 0.6; shadowVerticalOffset: Style.space(10) }
            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
              id: popColumn
              x: Style.space(6)
              y: Style.space(6)
              width: parent.width - Style.space(12)
              spacing: Style.space(2)

              Repeater {
                model: root.svc ? root.svc.projects : []
                Column {
                  id: projEntry
                  required property var modelData
                  required property int index
                  width: popColumn.width
                  readonly property bool newOrg: index === 0 || root.svc.projects[index - 1].organization !== modelData.organization
                  Text {
                    visible: projEntry.newOrg
                    leftPadding: Style.space(10)
                    topPadding: Style.space(8)
                    bottomPadding: Style.space(6)
                    text: projEntry.modelData.organization.toUpperCase()
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: root.metaSize
                    font.letterSpacing: 1
                  }
                  Rectangle {
                    width: parent.width
                    height: Math.ceil(bodyMetrics.height) + Style.space(20)
                    radius: root.rControl
                    color: projMouse.containsMouse ? Util.alpha(root.fg, 0.08) : (projEntry.modelData.current ? Util.alpha(root.accent, 0.08) : "transparent")
                    Behavior on color { ColorAnimation { duration: root.d(120) } }
                    RowLayout {
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      spacing: Style.space(10)
                      Label { text: "󰉋"; color: projEntry.modelData.current ? root.accent : root.dim }
                      Label { Layout.fillWidth: true; text: projEntry.modelData.name; font.bold: projEntry.modelData.current }
                      Label { meta: true; text: projEntry.modelData.screens + " screens" }
                      Label { text: projEntry.modelData.current ? "󰄬" : ""; color: root.accent; Layout.preferredWidth: Style.space(14) }
                    }
                    MouseArea {
                      id: projMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.projectMenu = false
                        if (!projEntry.modelData.current) root.svc.switchProject(projEntry.modelData.id)
                      }
                    }
                  }
                }
              }
              Label {
                visible: !root.svc || root.svc.projects.length === 0
                leftPadding: Style.space(10)
                topPadding: Style.space(10)
                bottomPadding: Style.space(10)
                meta: true
                text: "Loading projects"
              }
              Rectangle { width: parent.width; height: 1; color: root.line }
              // Add a project: approve this sign-in for it in the dashboard.
              Rectangle {
                width: parent.width
                height: addCol.implicitHeight + Style.space(20)
                radius: root.rControl
                color: addMouse.containsMouse ? Util.alpha(root.fg, 0.08) : "transparent"
                Column {
                  id: addCol
                  x: Style.space(10)
                  y: Style.space(10)
                  width: parent.width - Style.space(20)
                  spacing: Style.space(6)
                  RowLayout {
                    width: parent.width
                    spacing: Style.space(10)
                    Label {
                      text: root.svc && root.svc.pendingLogin ? "󰔟" : "󰐕"
                      color: root.accent
                      RotationAnimation on rotation { running: !!root.svc && !!root.svc.pendingLogin && root.revealed; from: 0; to: 360; duration: 1100; loops: Animation.Infinite }
                    }
                    Label {
                      Layout.fillWidth: true
                      text: root.svc && root.svc.pendingLogin ? "Approve in the dashboard" : "Add another project"
                    }
                    Label { visible: !!root.svc && !!root.svc.pendingLogin; meta: true; text: "open again" }
                  }
                  Row {
                    visible: !!root.svc && !!root.svc.pendingLogin
                    leftPadding: Style.space(26)
                    spacing: Style.space(8)
                    Label { meta: true; text: "Code"; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                      text: root.svc && root.svc.pendingLogin ? root.svc.pendingLogin.code : ""
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: root.titleSize
                      font.bold: true
                      font.letterSpacing: 2
                    }
                  }
                  Label {
                    visible: !!root.svc && !!root.svc.pendingLogin
                    width: parent.width
                    leftPadding: Style.space(26)
                    meta: true
                    wrapMode: Text.Wrap
                    text: "Switch the dashboard to the project you want, then press Connect. It joins this list."
                  }
                }
                MouseArea {
                  id: addMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.svc.addProject()
                }
              }
              Rectangle {
                width: parent.width
                height: Math.ceil(bodyMetrics.height) + Style.space(20)
                radius: root.rControl
                color: manageMouse.containsMouse ? Util.alpha(root.fg, 0.08) : "transparent"
                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  spacing: Style.space(10)
                  Label { text: "󰏌"; color: root.dim }
                  Label { Layout.fillWidth: true; text: "Manage projects in the dashboard"; meta: !manageMouse.containsMouse }
                }
                MouseArea {
                  id: manageMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.projectMenu = false; Qt.openUrlExternally("https://screenrig.ai/dashboard/") }
                }
              }
            }
          }

          // Toast: the last action's answer, floating up from the bottom edge.
          Rectangle {
            id: toast
            readonly property string message: !root.svc ? "" : (root.svc.statusMessage !== "" ? root.svc.statusMessage
              : (!root.svc.connected && root.svc.ready && root.svc.lastError !== "" ? root.svc.lastError : ""))
            property string shownText: ""
            onMessageChanged: if (message !== "") shownText = message
            property real shown: message !== "" ? 1 : 0
            Behavior on shown { NumberAnimation { duration: root.d(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.easeOut } }
            visible: shown > 0.01
            opacity: shown
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - height - root.pad + (1 - shown) * Style.space(16)
            width: Math.min(toastRow.implicitWidth + Style.space(32), parent.width - root.pad * 2)
            height: root.controlHeight
            radius: height / 2
            color: Qt.rgba(0.07, 0.07, 0.08, 0.94)
            border.color: Util.alpha("white", 0.10)
            Row {
              id: toastRow
              anchors.centerIn: parent
              spacing: Style.space(10)
              PulseDot {
                anchors.verticalCenter: parent.verticalCenter
                color: root.svc && root.svc.statusOk && root.svc.connected ? root.onlineColor : Commons.Color.urgent
                pulse: true
              }
              Label {
                anchors.verticalCenter: parent.verticalCenter
                text: toast.shownText
                color: "white"
              }
            }
          }
        }
      }
    }
  }
}
