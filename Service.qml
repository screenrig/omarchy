import QtQuick
import Quickshell
import Quickshell.Io

// Owns the follower process and the latest project snapshot. The bar chip and
// the panel read this one instance; actions run the helper and report back.
Item {
  id: root
  visible: false
  width: 0
  height: 0

  property var shell: null
  property var manifest: null

  readonly property string helper: Qt.resolvedUrl("bin/screenrig-omarchy").toString().replace("file://", "")

  property var screens: []
  property var playlists: []
  property var project: ({})
  property var credits: ({})
  property bool ready: false
  property bool connected: false
  property string lastError: ""
  property double snapshotAt: 0
  readonly property int onlineCount: count(true)
  readonly property int offlineCount: screens.length - onlineCount
  // Screens that went offline since the panel was last opened.
  property var droppedIds: []
  property string statusMessage: ""
  property bool statusOk: true
  property int busyCount: 0

  property var projects: []
  property bool switching: false

  // Fresh screenshots: the follower asks one online screen at a time while the panel shows the screens
  // (`screensShown`). `freshShots` maps a screen id to the image that landed since the last snapshot,
  // `shootingId` names the screen the rotation is asking now and `pressedIds` those the person asked.
  property bool screensShown: false
  property var freshShots: ({})
  property string shootingId: ""
  property var pressedIds: ({})
  onScreensShownChanged: tellFollower(screensShown ? "shown" : "hidden")

  function tellFollower(line) {
    if (follow.running) follow.write(line + "\n")
  }

  // The person's own capture comes first; the rotation leaves that screen alone for a while.
  function takeShot(screenId, done) {
    pressed(screenId, true)
    tellFollower("shot " + screenId)
    run(["act", screenId, "shot"], function(ok, message, answer) {
      root.pressed(screenId, false)
      if (done) done(ok, message, answer)
    })
  }

  function pressed(screenId, on) {
    var ids = Object.assign({}, pressedIds)
    if (on) ids[screenId] = true
    else delete ids[screenId]
    pressedIds = ids
  }

  signal actionFinished(bool ok, string message)
  // ------------------------------------------------------------ agent chat
  // One headless session with the default agent, resumed on every message.
  // Roles: user, agent, tool (title, status running|done|failed, output), error.
  property ListModel chat: ListModel {}
  property bool agentRunning: false
  property string agentName: ""
  property bool chatLoaded: false
  signal chatUpdated()

  function loadChat() {
    if (agentRunning || chatLoaded) return
    run(["agent-history"], function(ok, message, answer) {
      if (!ok || root.agentRunning) return
      root.agentName = answer.name || ""
      root.chat.clear()
      var entries = answer.entries || []
      for (var i = 0; i < entries.length; i++) root.addChat(entries[i])
      root.chatLoaded = true
      root.chatUpdated()
    })
  }

  function addChat(e) {
    chat.append({ role: e.role || "agent", text: e.text || "", title: e.title || "", status: e.status || "",
                  output: e.output || "", toolId: e.id || "" })
  }

  function agentSend(text) {
    text = String(text || "").trim()
    if (text === "" || agentRunning) return
    addChat({ role: "user", text: text })
    agentRunning = true
    // In the environment, not an argument: every account on the machine can read a command line.
    agentProc.environment = ({ "SCREENRIG_AGENT_MESSAGE": text })
    agentProc.command = [root.helper, "agent-send"]
    agentProc.running = true
    chatUpdated()
  }

  function agentStop() {
    if (agentProc.running) agentProc.signal(15)
  }

  function agentReset() {
    if (agentRunning) return
    run(["agent-reset"], function() {
      root.chat.clear()
      root.chatUpdated()
    })
  }

  function agentEvent(line) {
    var ev
    try { ev = JSON.parse(line) } catch (e) { return }
    if (ev.kind === "start") {
      agentName = ev.name || agentName
    } else if (ev.kind === "text") {
      addChat({ role: "agent", text: ev.text })
    } else if (ev.kind === "tool") {
      for (var i = chat.count - 1; i >= 0 && i >= chat.count - 40; i--) {
        var row = chat.get(i)
        if (row.role === "tool" && row.toolId === ev.id) {
          chat.setProperty(i, "status", ev.status || row.status)
          if (ev.title) chat.setProperty(i, "title", ev.title)
          if (ev.output) chat.setProperty(i, "output", ev.output)
          chatUpdated()
          return
        }
      }
      addChat({ role: "tool", id: ev.id, title: ev.title, status: ev.status, output: ev.output })
    } else if (ev.kind === "error") {
      addChat({ role: "error", text: ev.text })
    } else if (ev.kind === "done") {
      agentRunning = false
    }
    chatUpdated()
  }

  Process {
    id: agentProc
    stdout: SplitParser { onRead: function(line) { root.agentEvent(line) } }
    onExited: function() {
      root.agentRunning = false
      // A tool left running when the turn ended did not finish.
      for (var i = 0; i < root.chat.count; i++)
        if (root.chat.get(i).status === "running") root.chat.setProperty(i, "status", "failed")
      root.chatUpdated()
    }
  }


  function loadProjects() {
    run(["projects"], function(ok, message, answer) {
      if (ok) root.projects = answer.projects || []
    })
  }

  // ------------------------------------------------------------- live cast
  property var live: ({ live: false })
  property var liveTargets: ({ ok: false, screens: [] })

  function refreshLive() {
    run(["live-status"], function(ok, message, answer) { root.live = answer || { live: false } })
  }

  function loadLiveTargets() {
    run(["live-targets"], function(ok, message, answer) {
      root.liveTargets = ok ? answer : { ok: true, screens: [], elsewhere: 0, error: message }
    })
  }

  function liveStart(source, label, screens, minutes, done) {
    run(["live-start", "--source", source, "--label", label, "--screens", screens.join(","), "--minutes", String(minutes)],
        function(ok, message) {
          root.refreshLive()
          if (done) done(ok, message)
        })
  }

  function liveStop() {
    run(["live-stop"], function(ok, message) {
      root.report(ok, message)
      root.refreshLive()
    })
  }

  // While live: keep the status fresh, and end the capture once a timed cast is over.
  Timer {
    interval: 5000
    repeat: true
    running: !!root.live.live
    onTriggered: {
      if (root.live.until && Date.parse(root.live.until) <= Date.now()) root.liveStop()
      else root.refreshLive()
    }
  }

  // Add a project to this sign-in: the person approves it in the dashboard.
  property var pendingLogin: null

  function addProject() {
    if (pendingLogin) {
      Quickshell.execDetached(["xdg-open", pendingLogin.url])
      return
    }
    run(["login-start"], function(ok, message, answer) {
      if (!ok) { root.report(false, message || "Could not start the approval"); return }
      root.pendingLogin = { code: answer.code, url: answer.url, login: answer.login }
      root.run(["login-wait", answer.login], function(ok2, message2) {
        root.pendingLogin = null
        root.report(ok2, message2)
        if (!ok2) return
        root.ready = false
        root.screens = []
        root.playlists = []
        root.droppedIds = []
        reconnect.interval = 100
        follow.running = false
        root.loadProjects()
      })
    })
  }

  // Select another project, then follow it from a clean slate.
  function switchProject(id) {
    if (!id || id === project.id || switching) return
    switching = true
    run(["project-use", id], function(ok, message) {
      root.switching = false
      root.report(ok, message)
      if (!ok) return
      root.ready = false
      root.screens = []
      root.playlists = []
      root.droppedIds = []
      reconnect.interval = 100
      follow.running = false
      root.loadProjects()
    })
  }

  function count(online) {
    var n = 0
    for (var i = 0; i < screens.length; i++) if (screens[i].online === online) n++
    return n
  }

  function screenById(id) {
    for (var i = 0; i < screens.length; i++) if (screens[i].id === id) return screens[i]
    return null
  }

  function droppedNames() {
    var names = []
    for (var i = 0; i < droppedIds.length; i++) {
      var s = screenById(droppedIds[i])
      names.push(s ? s.label : droppedIds[i])
    }
    return names
  }

  function acknowledge() {
    if (droppedIds.length) droppedIds = []
  }

  function ingest(line) {
    var msg
    try { msg = JSON.parse(line) } catch (e) { return }
    if (msg.kind === "snapshot") {
      var before = {}
      for (var i = 0; i < screens.length; i++) before[screens[i].id] = screens[i].online
      var dropped = droppedIds.slice()
      for (var j = 0; j < msg.screens.length; j++) {
        var s = msg.screens[j]
        var at = dropped.indexOf(s.id)
        if (ready && before[s.id] === true && !s.online && at < 0) dropped.push(s.id)
        if (s.online && at >= 0) dropped.splice(at, 1)
      }
      screens = msg.screens
      playlists = msg.playlists
      project = msg.project || {}
      if (msg.credits) credits = msg.credits
      snapshotAt = msg.at * 1000
      droppedIds = dropped
      freshShots = ({})
      ready = true
      lastError = ""
    } else if (msg.kind === "shot") {
      var shots = Object.assign({}, freshShots)
      shots[msg.id] = { shot: msg.shot, mtime: msg.shot_mtime }
      freshShots = shots
    } else if (msg.kind === "shooting") {
      shootingId = msg.id || ""
    } else if (msg.kind === "status") {
      connected = !!msg.ok
      if (!msg.ok) lastError = msg.error || "Disconnected"
    } else if (msg.kind === "event") {
      connected = true
    }
  }

  // Run the helper with args; done(ok, message, payload) gets its JSON answer.
  function run(args, done) {
    var proc = runner.createObject(root, { command: [root.helper].concat(args), done: done || null })
    busyCount++
    proc.running = true
  }

  function act(screenId, action, arg) {
    var args = ["act", screenId, action]
    if (arg !== undefined && arg !== null) args.push(String(arg))
    run(args, function(ok, message) {
      root.report(ok, message)
    })
  }

  function report(ok, message) {
    statusOk = ok
    statusMessage = message || (ok ? "Done" : "Failed")
    actionFinished(ok, statusMessage)
    clearStatus.restart()
  }

  Timer {
    id: clearStatus
    interval: 8000
    onTriggered: root.statusMessage = ""
  }

  Component {
    id: runner
    Process {
      id: proc
      property var done: null
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          var lines = String(text || "").trim().split("\n")
          var answer = {}
          try { answer = JSON.parse(lines[lines.length - 1] || "{}") } catch (e) {}
          root.busyCount = Math.max(0, root.busyCount - 1)
          if (proc.done) proc.done(answer.ok === true, String(answer.message || ""), answer)
          proc.destroy()
        }
      }
    }
  }

  // `omarchy plugin add` only clones the plugin: link the helper and menus on first load.
  // A cast outlives a shell restart: pick it up, so its status and Stop come back.
  Component.onCompleted: {
    run(["setup"])
    refreshLive()
  }

  Process {
    id: follow
    running: true
    command: [root.helper, "follow", "--notify"]
    // The panel tells the follower when it shows the screens and when the person takes a screenshot.
    stdinEnabled: true
    onStarted: if (root.screensShown) root.tellFollower("shown")
    stdout: SplitParser {
      onRead: function(line) { root.ingest(line) }
    }
    stderr: SplitParser {
      onRead: function(line) { if (String(line).trim() !== "") root.lastError = String(line) }
    }
    onExited: function() {
      root.connected = false
      root.shootingId = ""
      reconnect.restart()
    }
  }

  Timer {
    id: reconnect
    interval: 3000
    onTriggered: { follow.running = true; interval = 3000 }
  }
}
