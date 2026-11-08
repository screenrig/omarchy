import QtQuick
import QtQuick.Shapes
import qs.Commons

// The colour screenRIG logomark as a living idle character: a QML port of
// screenrig.logomark/v1, the character screenRIG Players and the dashboard
// use. It glances around with anticipation, looks at the
// pointer when `target` is set, blinks, slowly gets bored (lids droop, it
// yawns, dozes, startles awake) and `celebrate()` wakes it into a smile and a
// hop. Springs drive every part, so it never loops visibly. `alive: false`, or
// Omarchy's reduced motion, shows the still mark.
Item {
  id: root

  property real size: 32
  property bool alive: true
  // A point in this item's coordinates to glance at, or null.
  property var target: null
  property color frameColor: "#F8B334"
  property color faceColor: "#2A3547"
  property color eyeColor: "#FFFFFF"

  readonly property real unit: size / 224
  implicitWidth: size
  implicitHeight: 176 * unit
  width: implicitWidth
  height: implicitHeight

  // ------------------------------------------------------------ character state

  readonly property real eyeRadius: 14
  readonly property var eyeXs: [100, 166]
  readonly property real eyeY: 118
  readonly property real boredMs: 95000

  property var springs: ({
    gx: mk(0, 5.5, 0.62), gy: mk(0, 5.5, 0.62), lid: mk(0, 3, 0.9), shut: mk(0, 1.1, 0.95),
    wide: mk(0, 5, 0.45), squint: mk(0, 4, 0.8), rot: mk(0, 1.8, 0.55), hx: mk(0, 1.6, 0.7),
    hy: mk(0, 1.6, 0.7), squash: mk(0, 5, 0.45), smile: mk(0, 4.5, 0.6), hop: mk(0, 5, 0.5)
  })
  property real clock: 0
  property real nextAction: 0.8
  property real boredomStart: 0
  property bool asleep: false
  property bool happy: false
  property real wakeAt: 0
  property var blink: null
  property real nextBlink: 2.5
  property real breath: 0
  property var pending: []
  property var prevEye: [{ x: 100, y: 118 }, { x: 166, y: 118 }]

  // Rendered values, written once per frame.
  property real headX: 0
  property real headY: 0
  property real headRot: 0
  property real headSx: 1
  property real headSy: 1
  property var eyes: [eyeShape(0, 100, 118), eyeShape(1, 166, 118)]

  function mk(v, freq, damping) { return { x: v, v: 0, target: v, freq: freq, damping: damping } }
  function s(name) { return springs[name] }
  function rand(a, b) { return a + (b - a) * Math.random() }
  function later(delay, run) { pending.push({ at: clock + delay, run: run }) }
  function boredom() { return Math.min(1, (clock - boredomStart) * 1000 / boredMs) }

  function eyeShape(i, x, y) {
    return { x: x, y: y, rx: eyeRadius, ry: eyeRadius, lidX: x - eyeRadius - 4, lidY: y - eyeRadius - 3, lidH: 0,
             cheekY: y + eyeRadius * 3.2, cheekR: eyeRadius * 1.35 }
  }

  function stepSpring(sp, dt) {
    var omega = 2 * Math.PI * sp.freq
    var slices = Math.max(1, Math.ceil(dt / (1 / 240)))
    var h = dt / slices
    for (var i = 0; i < slices; i++) {
      sp.v += (omega * omega * (sp.target - sp.x) - 2 * sp.damping * omega * sp.v) * h
      sp.x += sp.v * h
    }
  }

  function targetGaze() {
    if (!target) return { x: 12, y: -9 }
    var dx = target.x - width / 2
    var dy = target.y - height / 2
    var length = Math.sqrt(dx * dx + dy * dy) || 1
    return { x: dx / length * 15, y: dy / length * 11 }
  }

  function look(x, y, anticipate) {
    if (anticipate === undefined) anticipate = Math.random() < 0.35
    var speed = 5.5 - 2.5 * boredom()
    s("gx").freq = speed
    s("gy").freq = speed
    var go = function() {
      s("gx").target = x; s("gy").target = y
      s("hx").target = x * 0.18; s("hy").target = y * 0.12; s("rot").target = x * 0.12
    }
    if (anticipate) {
      var dx = x - s("gx").x, dy = y - s("gy").x
      var length = Math.sqrt(dx * dx + dy * dy) || 1
      s("gx").target = s("gx").x - dx / length * 1.6
      s("gy").target = s("gy").x - dy / length * 1.2
      later(0.09, go)
    } else go()
  }

  function blinkNow(slow) {
    blink = slow ? { start: clock, close: 0.16, hold: 0.12, open: 0.3 } : { start: clock, close: 0.065, hold: 0.04, open: 0.11 }
  }

  function act() {
    var bored = boredom()
    if (bored >= 1) { doze(); return }
    var r = Math.random()
    var t = targetGaze()
    if (bored > 0.55 && r < 0.18 * bored) { yawn(); nextAction = clock + rand(3.5, 5); return }
    if (bored > 0.4 && r < 0.3) {
      look(rand(-6, 6), rand(4, 9), false)
      s("squash").target = 0.05
      later(0.5, function() { s("squash").target = 0 })
    } else if (r < 0.3) {
      look(t.x, t.y)
      if (Math.random() < 0.4) later(0.6, function() { s("wide").target = 0.6; later(0.25, function() { s("wide").target = 0 }) })
    } else if (r < 0.5) {
      look(0, 0)
    } else if (r < 0.62) {
      look(-t.x * 0.6, rand(-4, 4), false)
      later(0.55, function() { look(t.x, t.y, true) })
      later(0.7, function() { s("wide").target = 1; later(0.2, function() { s("wide").target = 0 }) })
    } else {
      look(rand(-16, 16), rand(-10, 9))
    }
    s("lid").target = Math.max(0, bored - 0.25) * 0.75
    nextAction = clock + rand(1.2, 3.4) * (1 + 1.4 * bored)
  }

  function yawn() {
    look(0, -3, false)
    s("squint").target = 1
    s("squash").target = -0.07
    later(1.3, function() { s("squint").target = 0; s("squash").target = 0.04 })
    later(1.7, function() { s("squash").target = 0; blinkNow(true) })
  }

  function doze() {
    if (asleep) return
    asleep = true
    look(0, 5, false)
    s("lid").freq = 1.2; s("lid").target = 0.35
    s("shut").target = 1
    wakeAt = clock + rand(14, 24)
  }

  function wake() {
    asleep = false
    s("lid").freq = 3; s("lid").target = 0
    s("shut").x = 0; s("shut").target = 0
    s("wide").target = 1.2
    s("squash").target = -0.08
    later(0.12, function() { s("squash").target = 0 })
    later(0.35, function() { s("wide").target = 0; look(-14, -2, false) })
    later(0.8, function() { look(15, -1, false) })
    later(1.4, function() { var t = targetGaze(); look(t.x, t.y, false) })
    boredomStart = clock
    nextAction = clock + 3
  }

  // Something good happened: wake if dozing, smile, hop, then settle back to idling.
  function celebrate() {
    happy = true
    pending = []
    asleep = false
    blink = null
    s("shut").target = 0
    s("lid").freq = 4; s("lid").target = 0
    look(0, 0, false)
    s("wide").target = 1
    later(0.18, function() { s("wide").target = 0; s("smile").target = 1 })
    later(0.25, function() { s("squash").target = 0.08 })
    later(0.37, function() { s("squash").target = -0.07; s("hop").target = -12 })
    later(0.55, function() { s("hop").target = 0 })
    later(0.7, function() { s("squash").target = 0.1 })
    later(0.82, function() { s("squash").target = 0 })
    later(1.6, function() { s("hop").target = -6; s("squash").target = -0.04 })
    later(1.75, function() { s("hop").target = 0; s("squash").target = 0.05 })
    later(1.9, function() { s("squash").target = 0 })
    later(3.2, function() { s("smile").target = 0; happy = false; boredomStart = clock; nextAction = clock + 1 })
  }

  // Wake fresh each time it is shown.
  function refresh() {
    asleep = false
    happy = false
    s("shut").x = 0; s("shut").target = 0; s("lid").target = 0; s("smile").target = 0
    boredomStart = clock
    nextAction = clock + 0.6
  }

  function blinkAmount() {
    var b = blink
    if (!b) return 0
    var t = clock - b.start
    if (t < b.close) return Math.pow(t / b.close, 2)
    if (t < b.close + b.hold) return 1
    var o = (t - b.close - b.hold) / b.open
    if (o >= 1) { blink = null; return 0 }
    return Math.pow(1 - o, 3)
  }

  function tick(dt) {
    clock += dt
    if (pending.length) {
      var due = pending.filter(function(p) { return p.at <= clock })
      pending = pending.filter(function(p) { return p.at > clock })
      for (var i = 0; i < due.length; i++) due[i].run()
    }
    if (happy) {
    } else if (asleep) {
      breath += dt
      if (clock >= wakeAt) wake()
    } else {
      if (clock >= nextAction) act()
      if (clock >= nextBlink) {
        blinkNow(boredom() > 0.6)
        if (Math.random() < 0.18) later(0.28, function() { blinkNow(false) })
        nextBlink = clock + rand(2.2, 5.5) * (1 - 0.3 * boredom())
      }
    }
    for (var k in springs) stepSpring(springs[k], dt)
    render(dt)
  }

  function render(dt) {
    var breathing = asleep ? Math.sin(breath * 2 * Math.PI / 4.2) * 0.018 : 0
    var q = s("squash").x + breathing
    headSx = 1 + q
    headSy = 1 / (1 + q)
    headX = s("hx").x
    headY = s("hy").x + s("hop").x
    headRot = s("rot").x
    var bl = Math.max(blinkAmount(), s("shut").x)
    var wide = 1 + 0.13 * s("wide").x
    var squint = s("squint").x
    var smile = s("smile").x
    var out = []
    for (var i = 0; i < 2; i++) {
      var side = i === 0 ? -1 : 1
      var gx = s("gx").x, gy = s("gy").x
      var far = Math.max(0, side * gx / 16)
      var near = Math.max(0, -side * gx / 16)
      var x = eyeXs[i] + gx * (1 + 0.18 * near - 0.18 * far)
      var y = eyeY + gy
      var prev = prevEye[i]
      var speed = dt > 0 ? Math.sqrt((x - prev.x) * (x - prev.x) + (y - prev.y) * (y - prev.y)) / dt : 0
      prev.x = x; prev.y = y
      var stretch = Math.min(0.22, speed / 1700) * (1 - bl)
      var r = eyeRadius * wide
      out.push({
        x: x,
        y: y + 3.5 * bl,
        rx: eyeRadius * wide * (1 - 0.13 * far + 0.04 * near) * (1 + 0.06 * bl) * (1 + 0.1 * squint) * (1 + stretch),
        ry: eyeRadius * wide * Math.max(0.08, 1 - 0.92 * bl) * (1 - 0.55 * squint) / (1 + stretch),
        lidX: x - eyeRadius - 4,
        lidY: y - r - 3,
        lidH: Math.max(0, s("lid").x * (r * 2 + 3)),
        cheekY: y + r * (3.2 - 2.0 * smile),
        cheekR: r * 1.35
      })
    }
    eyes = out
  }

  readonly property bool running: alive && visible && Style.duration(1) > 0
  onRunningChanged: if (running) refresh()

  FrameAnimation {
    running: root.running
    onTriggered: root.tick(Math.min(0.1, frameTime))
  }

  // ----------------------------------------------------------------- drawing

  Item {
    x: -16 * root.unit
    y: -40 * root.unit
    width: 256
    height: 256
    scale: root.unit
    transformOrigin: Item.TopLeft

    Item {
      id: head
      width: 256
      height: 256
      transform: [
        Scale { origin.x: 128; origin.y: 216; xScale: root.headSx; yScale: root.headSy },
        Rotation { origin.x: 128; origin.y: 128; angle: root.headRot },
        Translate { x: root.headX; y: root.headY }
      ]

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: root.faceColor
          strokeColor: "transparent"
          PathSvg { path: "M108 60H220V168Q220 196 192 196H36V154L86 72Q94 60 108 60Z" }
        }
      }

      Repeater {
        model: 2
        Item {
          id: eyeItem
          required property int index
          readonly property var e: root.eyes[index]
          anchors.fill: parent
          Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
              fillColor: root.eyeColor
              strokeColor: "transparent"
              startX: eyeItem.e.x + eyeItem.e.rx
              startY: eyeItem.e.y
              PathAngleArc {
                centerX: eyeItem.e.x; centerY: eyeItem.e.y
                radiusX: eyeItem.e.rx; radiusY: eyeItem.e.ry
                startAngle: 0; sweepAngle: 360
              }
            }
          }
          // Lid.
          Rectangle {
            x: eyeItem.e.lidX
            y: eyeItem.e.lidY
            width: root.eyeRadius * 2 + 8
            height: eyeItem.e.lidH
            color: root.faceColor
          }
          // Cheek: rises under the eye into a smile.
          Rectangle {
            x: eyeItem.e.x - eyeItem.e.cheekR
            y: eyeItem.e.cheekY - eyeItem.e.cheekR
            width: eyeItem.e.cheekR * 2
            height: width
            radius: width / 2
            color: root.faceColor
          }
        }
      }

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          fillColor: root.frameColor
          strokeColor: "transparent"
          fillRule: ShapePath.OddEvenFill
          PathSvg { path: "M40 40H216Q240 40 240 64V192Q240 216 216 216H40Q16 216 16 192V64Q16 40 40 40Z M108 60H220V168Q220 196 192 196H36V154L86 72Q94 60 108 60Z" }
        }
      }
    }
  }
}
