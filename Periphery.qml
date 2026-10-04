import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// Periphery exposé, after Scott Jenson's widescreen prototype: tiling and the
// bar are squeezed into a centred focus area (5:4 of the monitor height by
// default), and the windows of the other occupied workspaces sit exploded in
// the side bands, grouped per workspace and kept near their real relative
// positions. Lower-numbered workspaces go left, higher go right. Click a
// window to go to it; drag it into the focus area to pull it onto the current
// workspace, or onto another group to send it there. SUPER-dragging a real
// window onto a band sends it away too (see dropWindow and the release bind
// in hypr/bindings.lua).
//
// Two invisible Bottom-layer surfaces reserve the side bands. Hyprland lays
// out Bottom before Top, so the bar (Top layer) and the tiler both end up in
// the centre. Cards are drawn on one fullscreen Bottom-layer surface (below
// windows, above the wallpaper) so they can slide between sides; a dragged
// card is drawn on an Overlay surface so it stays above the focus windows.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  // Focus area width as a multiple of the monitor height; override per
  // invocation with a payload like '{"ratio": 1.333}'.
  property real ratio: 1.25

  // Window address -> { address, toplevel, title, appClass, wsId, x, y, w, h }.
  property var winData: ({})
  // Workspace groups: [{ id, label, x, y, w, h }], also the drop targets.
  property var headers: []
  property string layoutSignature: ""

  // Drag state; dragAddress is empty when nothing is being dragged.
  property string dragAddress: ""
  property var dragWin: null
  property real dragX: 0
  property real dragY: 0
  property real dragW: 0
  property real dragH: 0
  property real grabX: 0
  property real grabY: 0
  readonly property bool dragOverFocus: dragAddress !== "" && dragX > sideW && dragX < monW - sideW
  // Group under the dragged card, or null.
  readonly property var dragTarget: dragAddress !== "" && !dragOverFocus ? groupAt(dragX, dragY) : null

  // Window address -> { address, toplevel, fullscreen, x, y, w, h }: the
  // windows of the current workspace, monitor-local. Incoming ghosts fly here.
  property var focusRects: ({})
  // Address -> live card or ghost item, so a switch starts each flight from
  // where the window is drawn right now, mid-slide or not.
  property var cardItems: ({})
  property var ghostItems: ({})
  // Workspace switch: ghosts fly between the focus area and the bands while
  // a wallpaper backdrop hides the real, already switched, focus windows.
  property bool transitioning: false
  property double switchStarted: 0
  property int landedTicks: 0
  // Address -> true while a ghost flies for that window; its card waits.
  property var ghosted: ({})
  // Resolved wallpaper file for the backdrop.
  property string wallpaper: ""
  // Hyprland's own workspace slide is off while the mode is on; this holds
  // the Lua that turns it back on.
  property bool hyprSlideOff: false
  // easeInOutCubic is one of Omarchy's default curves; speed 1.5 = 150 ms.
  readonly property string hyprSwitchFade: 'hl.animation({ leaf = "workspaces", enabled = true, speed = 1.5, bezier = "easeInOutCubic", style = "fade" })'
  property string hyprSlideRestore: ""
  // Address -> true for windows we turned the shadow off for. Band windows
  // are hidden, so they lose nothing; a window then arrives in the focus
  // area without a shadow showing ahead of it, and gets it back on landing.
  property var shadowless: ({})
  // Set while a switch relays out, before it knows whether ghosts fly.
  property bool holdShadows: false

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily

  readonly property int bandMargin: Style.space(16)
  readonly property int cardGap: Style.space(10)
  readonly property int groupGap: Style.space(20)
  readonly property int headerHeight: Style.font.body + Style.spacing.sm * 2
  // How far a group's map may stretch vertically to use a tall band.
  readonly property real maxStretch: 6
  // Global animation speed: 1 is normal, 0.25 plays every animation 4x
  // slower to inspect it, 2 twice as fast. Scales durations, timeouts and
  // the springs (strength by speed², damping by speed keeps their shape).
  readonly property real animSpeed: 1
  function ms(duration) { return Math.round(duration / root.animSpeed) }

  readonly property int slideDuration: ms(320)
  readonly property int fadeDuration: ms(150)
  // Qt SpringAnimation, tuned to the theme's spatial_default spring
  // (stiffness 700, damping ratio 0.9): settles in ~340 ms, no overshoot.
  readonly property real springStrength: 11.2 * animSpeed * animSpeed
  // Qt steps springs in fixed 16 ms ticks, and at normal speed those coarse
  // ticks damp the overshoot away. Slowed down, the same spring overshoots
  // ~2%; the extra damping below cancels that, so slow motion shows the
  // normal-speed curve (simulated: 0.2 px per 1000 px at animSpeed 0.1).
  readonly property real springDamping: 0.65 * animSpeed * (1 + 0.22 * Math.max(0, 1 - animSpeed))
  readonly property real springEpsilon: 0.25
  // Ghosts settle at least this long before the hand-off, so the refresh
  // that follows a switch can still retarget them; and at most this long.
  readonly property int switchMinMs: ms(120)
  readonly property int switchMaxMs: ms(1500)
  // How far the switch backdrop reaches into the bands, to cover the border
  // (general:border_size) of a window tiled flush against the band.
  readonly property int coverBleed: 2
  // Hyprland blurs what is behind a translucent window as it draws it; a
  // window capture has no blur of its own. Ghosts get the wallpaper blurred
  // to look like decoration:blur (size 6, 3 passes; matched by eye against
  // a real foot window, as dual-kawase has no exact radius; contrast 0.89
  // and vibrancy 0.17 map to MultiEffect -0.11 and 0.17).
  readonly property int ghostBlur: 96
  readonly property real ghostBlurContrast: -0.11
  readonly property real ghostBlurSaturation: 0.17

  property var targetScreen: null
  // The Hyprland monitor the mode runs on; it keeps it when focus moves away.
  property var targetMonitor: null
  property int monId: -1
  property real monX: 0
  property real monY: 0
  property real monW: 1920
  property real monH: 1080
  readonly property real focusW: Math.min(monW, Math.round(monH * ratio))
  readonly property real sideW: Math.max(0, Math.floor((monW - focusW) / 2))
  // Reserved [left, top, right, bottom], for the bar above the tiling area.
  readonly property var reserved: targetMonitor && targetMonitor.lastIpcObject
    && targetMonitor.lastIpcObject.reserved ? targetMonitor.lastIpcObject.reserved : [0, 0, 0, 0]

  function open(payloadJson) {
    try {
      var payload = JSON.parse(payloadJson || "{}")
      if (payload && payload.ratio > 0) root.ratio = payload.ratio
    } catch (e) {}
    var mon = Hyprland.focusedMonitor
    if (mon) {
      var scale = mon.scale > 0 ? mon.scale : 1
      root.targetMonitor = mon
      root.monId = mon.id
      root.monX = mon.x
      root.monY = mon.y
      root.monW = mon.width / scale
      root.monH = mon.height / scale
      var screens = Quickshell.screens
      root.targetScreen = null
      for (var i = 0; i < screens.length; i++)
        if (screens[i].name === mon.name) root.targetScreen = screens[i]
    }
    root.opened = true
    root.layoutSignature = ""
    root.disableHyprSlide()
    if (!wallpaperProc.running) wallpaperProc.running = true
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshMonitors()
    refreshTimer.restart()
  }

  function close() {
    root.opened = false
    root.finishSwitch()
    root.restoreHyprSlide()
    root.restoreShadows()
    root.targetMonitor = null
    root.layoutSignature = ""
    root.cancelDrag()
    root.winData = ({})
    root.focusRects = ({})
    root.headers = []
    slots.clear()
    ghosts.clear()
  }

  Component.onDestruction: {
    root.restoreHyprSlide()
    root.restoreShadows()
  }

  function setShadow(address, on) {
    Hyprland.dispatch('hl.dsp.window.set_prop({ window = "address:' + address
      + '", prop = "no_shadow", value = "' + (on ? "unset" : "1") + '" })')
  }

  // Band windows shadowless, focus windows back to their own setting
  // ("unset" keeps a window rule's no_shadow). Waits for a switch to land.
  function syncShadows() {
    if (!root.opened || root.transitioning || root.holdShadows) return
    var next = {}
    for (var a in root.winData) {
      next[a] = true
      if (!root.shadowless[a]) root.setShadow(a, false)
    }
    for (var f in root.focusRects) if (root.shadowless[f]) root.setShadow(f, true)
    root.shadowless = next
  }

  // Also runs on plugin unload, when the dispatch socket may already be
  // gone, so it goes through hyprctl.
  function restoreShadows() {
    var batch = Object.keys(root.shadowless).map(function(a) {
      return 'dispatch hl.dsp.window.set_prop({ window = "address:' + a + '", prop = "no_shadow", value = "unset" })'
    })
    root.shadowless = ({})
    if (batch.length > 0) Quickshell.execDetached(["hyprctl", "--batch", batch.join(" ; ")])
  }

  // Our ghosts animate the switch; Hyprland's slide would run underneath.
  // Off is not enough: Hyprland shows the new workspace one frame before
  // our first frame, a visible flash. A short fade that starts very slowly
  // instead shows it under 1% on that frame; from the next frame on the
  // backdrop hides the rest of the fade. Reads the current animation first
  // so it can be put back.
  function disableHyprSlide() {
    if (root.hyprSlideOff) return
    root.hyprSlideOff = true
    root.hyprSlideRestore = ""
    slideProc.running = true
  }

  function restoreHyprSlide() {
    if (!root.hyprSlideOff) return
    root.hyprSlideOff = false
    if (root.hyprSlideRestore) Quickshell.execDetached(["hyprctl", "eval", root.hyprSlideRestore])
    else Quickshell.execDetached(["hyprctl", "reload", "config-only"])
  }

  // `hyprctl animations -j` entry -> the hl.animation call that recreates it.
  function slideRestoreLua(json) {
    var lists = JSON.parse(json)
    var all = Array.isArray(lists[0]) ? lists[0] : lists
    for (var i = 0; i < all.length; i++) {
      var a = all[i]
      if (a.name !== "workspaces") continue
      if (!a.enabled) return 'hl.animation({ leaf = "workspaces", enabled = false })'
      var parts = ['leaf = "workspaces"', "enabled = true", "speed = " + a.speed]
      var curve = String(a.bezier || "")
      if (curve.indexOf("spring:") === 0) parts.push('spring = "' + curve.slice(7) + '"')
      else if (curve) parts.push('bezier = "' + curve + '"')
      if (a.style) parts.push('style = "' + a.style + '"')
      return "hl.animation({ " + parts.join(", ") + " })"
    }
    return ""
  }

  Process {
    id: slideProc
    command: ["bash", "-c", "hyprctl animations -j && hyprctl eval " + Util.shellQuote(root.hyprSwitchFade) + " >/dev/null"]
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.hyprSlideRestore = root.slideRestoreLua(text) } catch (e) { root.hyprSlideRestore = "" }
      }
    }
    // The mode went off before the slide was disabled: put it back now.
    onExited: if (!root.hyprSlideOff) { root.hyprSlideOff = true; root.restoreHyprSlide() }
  }

  Process {
    id: wallpaperProc
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      onStreamFinished: root.wallpaper = String(text || "").trim()
    }
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "stef.periphery")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function normalizeAddress(address) {
    if (!address) return ""
    var a = String(address)
    return a.indexOf("0x") === 0 ? a : "0x" + a
  }

  function activateWindow(address) {
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  // The workspace shown in the focus area: the target monitor's, not the
  // focused one, which is on another monitor when focus moves away.
  function currentWorkspaceId() {
    var ws = root.targetMonitor ? root.targetMonitor.activeWorkspace : Hyprland.focusedWorkspace
    return ws ? ws.id : -1
  }

  function moveToWorkspace(address, wsId) {
    Hyprland.dispatch('hl.dsp.window.move({ workspace = "' + wsId + '", follow = false, window = "address:' + address + '" })')
  }

  // Pulls a window onto the current workspace. Dwindle opens it next to the
  // tiled window under the cursor, which is where it was dropped.
  function moveToFocus(address) {
    var current = root.currentWorkspaceId()
    if (current <= 0) return
    root.moveToWorkspace(address, current)
    Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
  }

  function groupAt(x, y) {
    for (var i = 0; i < root.headers.length; i++) {
      var g = root.headers[i]
      if (x >= g.x - root.bandMargin && x <= g.x + g.w + root.bandMargin
          && y >= g.y - root.groupGap / 2 && y <= g.y + g.h + root.groupGap / 2) return g
    }
    return null
  }

  function inBand(x) {
    return x < root.sideW || x > root.monW - root.sideW
  }

  // Lowest workspace number with nothing on it, for drops on empty band.
  function freeWorkspaceId() {
    var used = {}
    var list = Hyprland.workspaces.values
    for (var i = 0; i < list.length; i++)
      if (list[i].id > 0 && list[i].toplevels && list[i].toplevels.values.length > 0) used[list[i].id] = true
    used[root.currentWorkspaceId()] = true
    for (var id = 1; id < 100; id++) if (!used[id]) return id
    return 100
  }

  // Sends a window to the workspace group under (x, y) in a band, or to a
  // fresh workspace when dropped on empty band.
  function dropInBand(address, x, y) {
    var group = root.groupAt(x, y)
    root.moveToWorkspace(address, group ? group.id : root.freeWorkspaceId())
  }

  // Called from the SUPER+mouse:272 release bind with the active window
  // (Hyprland focuses the window it drags) and the cursor position.
  IpcHandler {
    target: "stef.periphery"

    function dropWindow(address: string, x: string, y: string): void {
      if (!root.opened) return
      var px = parseFloat(x) - root.monX
      var py = parseFloat(y) - root.monY
      if (!(px >= 0 && px <= root.monW && py >= 0 && py <= root.monH) || !root.inBand(px)) return
      var a = root.normalizeAddress(address)
      Hyprland.refreshToplevels()
      root.dropInBand(a, px, py)
    }
  }

  function beginDrag(win, w, h, gx, gy) {
    root.dragWin = win
    root.dragW = w
    root.dragH = h
    root.grabX = gx
    root.grabY = gy
    root.dragAddress = win.address
  }

  function updateDrag(x, y) {
    root.dragX = x
    root.dragY = y
  }

  function endDrag(x, y) {
    root.updateDrag(x, y)
    var address = root.dragAddress
    var win = root.dragWin
    var toFocus = root.dragOverFocus
    var group = root.groupAt(x, y)
    root.cancelDrag()
    if (!address) return
    if (toFocus) root.moveToFocus(address)
    else if (group && win && group.id !== win.wsId) root.moveToWorkspace(address, group.id)
    else if (!group && root.inBand(x)) root.moveToWorkspace(address, root.freeWorkspaceId())
  }

  function cancelDrag() {
    root.dragAddress = ""
    root.dragWin = null
  }

  function rebuild() {
    if (!root.opened) return
    var current = root.currentWorkspaceId()
    var byWs = {}
    var focus = {}
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var t = toplevels[i]
      var ipc = t.lastIpcObject
      if (!ipc || !ipc.workspace || !ipc.at || !ipc.size) continue
      if (ipc.mapped === false || ipc.hidden === true) continue
      if (root.monId >= 0 && ipc.monitor !== undefined && ipc.monitor !== root.monId) continue
      var wsId = ipc.workspace.id
      if (wsId === current) {
        var fa = normalizeAddress(ipc.address || t.address)
        focus[fa] = { address: fa, toplevel: t, fullscreen: !!ipc.fullscreen,
                      x: ipc.at[0] - root.monX, y: ipc.at[1] - root.monY,
                      w: Math.max(1, ipc.size[0]), h: Math.max(1, ipc.size[1]) }
        continue
      }
      if (wsId <= 0) continue
      if (!byWs[wsId]) byWs[wsId] = { id: wsId, label: String(ipc.workspace.name || wsId), windows: [] }
      byWs[wsId].windows.push({
        toplevel: t,
        address: normalizeAddress(ipc.address || t.address),
        title: ipc.title || t.title || "",
        appClass: ipc["class"] || "",
        floating: !!ipc.floating,
        wsId: wsId,
        rx: ipc.at[0],
        ry: ipc.at[1],
        rw: Math.max(1, ipc.size[0]),
        rh: Math.max(1, ipc.size[1]),
      })
    }

    var ids = Object.keys(byWs).map(Number).sort(function(a, b) { return a - b })
    for (var g = 0; g < ids.length; g++) {
      // Reading order: tiled left-to-right then top-to-bottom, floating last.
      byWs[ids[g]].windows.sort(function(a, b) {
        if (a.floating !== b.floating) return a.floating ? 1 : -1
        if (Math.abs(a.rx - b.rx) > 4) return a.rx - b.rx
        return a.ry - b.ry
      })
    }
    var left = ids.filter(function(id) { return id < current })
    var right = ids.filter(function(id) { return id > current })
    // On the first workspace the last one wraps round to the left, and on
    // the last workspace the first one wraps round to the right.
    if (left.length === 0 && right.length >= 2) left.push(right.pop())
    else if (right.length === 0 && left.length >= 2) right.push(left.shift())

    var signature = JSON.stringify([root.sideW, current, left, right, ids.map(function(id) {
      return byWs[id].windows.map(function(w) { return [w.address, w.title, w.rx, w.ry, w.rw, w.rh] })
    }), Object.keys(focus).map(function(a) { var f = focus[a]; return [a, f.fullscreen, f.x, f.y, f.w, f.h] })])
    if (signature === root.layoutSignature) return
    root.layoutSignature = signature
    root.focusRects = focus

    var wins = {}
    var headers = []
    placeSide(left.map(function(id) { return byWs[id] }), root.bandMargin, wins, headers)
    placeSide(right.map(function(id) { return byWs[id] }), root.monW - root.sideW + root.bandMargin, wins, headers)
    root.winData = wins
    root.headers = headers
    syncModel(slots, Object.keys(wins))
    // Ghosts for every window on the monitor, band or focus area.
    syncModel(ghosts, Object.keys(wins).concat(Object.keys(focus)))
    syncShadows()
  }

  // Expose-style placement that keeps windows near their real relative
  // positions. Each group gets a slice of the band; window centres are
  // mapped from the group's bounding box into that slice (stretched
  // vertically up to maxStretch to use the tall band), then cards at a
  // shared scale are nudged apart until none overlap. The scale is the
  // largest at which every group of this side resolves.
  function placeSide(groups, bandX, wins, headers) {
    if (groups.length === 0) return
    var bandW = root.sideW - root.bandMargin * 2
    var availH = root.monH - root.bandMargin * 2
      - groups.length * root.headerHeight - (groups.length - 1) * root.groupGap

    // Group bounding boxes and their height when mapped at band width.
    var natural = 0
    for (var g = 0; g < groups.length; g++) {
      var ws = groups[g].windows
      var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
      for (var i = 0; i < ws.length; i++) {
        x0 = Math.min(x0, ws[i].rx); y0 = Math.min(y0, ws[i].ry)
        x1 = Math.max(x1, ws[i].rx + ws[i].rw); y1 = Math.max(y1, ws[i].ry + ws[i].rh)
      }
      groups[g].box = { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) }
      groups[g].naturalH = bandW * groups[g].box.h / groups[g].box.w
      natural += groups[g].naturalH
    }
    var stretch = Math.min(root.maxStretch, availH / natural)
    var bodies = groups.map(function(group) { return group.naturalH * stretch })
    var used = bodies.reduce(function(a, b) { return a + b }, 0)
      + groups.length * root.headerHeight + (groups.length - 1) * root.groupGap
    var top = (root.monH - used) / 2

    var regions = []
    var y = top
    for (var r = 0; r < groups.length; r++) {
      regions.push({ x: bandX, y: y + root.headerHeight, w: bandW, h: bodies[r] })
      y += root.headerHeight + bodies[r] + root.groupGap
    }

    var lo = 0.02
    var hi = 1
    for (var k = 0; k < groups.length; k++)
      for (var m = 0; m < groups[k].windows.length; m++)
        hi = Math.min(hi, bandW / groups[k].windows[m].rw, bodies[k] / groups[k].windows[m].rh)
    var best = null
    for (var iter = 0; iter < 16; iter++) {
      var mid = (lo + hi) / 2
      var trial = []
      var ok = true
      for (var t = 0; t < groups.length && ok; t++) {
        var placed = root.resolve(groups[t], regions[t], mid)
        if (!placed) ok = false
        else trial.push(placed)
      }
      if (ok) { lo = mid; best = trial } else hi = mid
    }
    if (!best) {
      best = []
      for (var f = 0; f < groups.length; f++) best.push(root.resolve(groups[f], regions[f], lo, true))
    }

    for (var h = 0; h < groups.length; h++) {
      // The label sits just above the group's topmost card.
      var minY = Infinity, maxY = -Infinity
      for (var e = 0; e < best[h].length; e++) {
        minY = Math.min(minY, best[h][e].y)
        maxY = Math.max(maxY, best[h][e].y + best[h][e].h)
      }
      headers.push({ id: groups[h].id, label: groups[h].label, x: bandX, y: minY - root.headerHeight,
                     w: bandW, h: maxY - minY + root.headerHeight })
      for (var c = 0; c < best[h].length; c++) wins[best[h][c].address] = best[h][c]
    }
  }

  // Places one group's cards at `scale` inside `region`, starting from their
  // mapped positions and pushing overlapping pairs apart along the shallower
  // axis (or the other one when both cards sit against that axis's walls).
  // Returns the cards, or null when they can't be separated.
  function resolve(group, region, scale, force) {
    var box = group.box
    var gap = root.cardGap
    var cards = group.windows.map(function(w) {
      var cw = w.rw * scale
      var ch = w.rh * scale
      return {
        address: w.address, toplevel: w.toplevel, title: w.title, appClass: w.appClass, wsId: w.wsId,
        w: cw, h: ch,
        cx: region.x + ((w.rx + w.rw / 2 - box.x) / box.w) * region.w,
        cy: region.y + ((w.ry + w.rh / 2 - box.y) / box.h) * region.h,
      }
    })
    function clamp(c) {
      c.cx = Math.max(region.x + c.w / 2, Math.min(region.x + region.w - c.w / 2, c.cx))
      c.cy = Math.max(region.y + c.h / 2, Math.min(region.y + region.h - c.h / 2, c.cy))
    }
    cards.forEach(clamp)

    var clear = false
    for (var pass = 0; pass < 120 && !clear; pass++) {
      clear = true
      for (var i = 0; i < cards.length; i++) {
        for (var j = i + 1; j < cards.length; j++) {
          var a = cards[i], b = cards[j]
          var dx = b.cx - a.cx, dy = b.cy - a.cy
          var ox = (a.w + b.w) / 2 + gap - Math.abs(dx)
          var oy = (a.h + b.h) / 2 + gap - Math.abs(dy)
          if (ox <= 0.5 || oy <= 0.5) continue
          clear = false
          // Ties keep reading order: the earlier window goes left/up.
          var sx = dx > 0 || (dx === 0 && i < j) ? 1 : -1
          var sy = dy > 0 || (dy === 0 && i < j) ? 1 : -1
          var xRoom = (a.cx - a.w / 2 - region.x) * (sx > 0 ? 1 : 0) + (region.x + region.w - a.cx - a.w / 2) * (sx < 0 ? 1 : 0)
                    + (region.x + region.w - b.cx - b.w / 2) * (sx > 0 ? 1 : 0) + (b.cx - b.w / 2 - region.x) * (sx < 0 ? 1 : 0)
          var yRoom = (a.cy - a.h / 2 - region.y) * (sy > 0 ? 1 : 0) + (region.y + region.h - a.cy - a.h / 2) * (sy < 0 ? 1 : 0)
                    + (region.y + region.h - b.cy - b.h / 2) * (sy > 0 ? 1 : 0) + (b.cy - b.h / 2 - region.y) * (sy < 0 ? 1 : 0)
          // Prefer the shallower axis if there's room to separate along it,
          // else whichever axis has room, else the one with more of it.
          var canX = xRoom >= ox - 0.5
          var canY = yRoom >= oy - 0.5
          var useX = canX && canY ? ox <= oy : canX || canY ? canX : xRoom / ox >= yRoom / oy
          if (useX) { a.cx -= sx * ox / 2; b.cx += sx * ox / 2 }
          else { a.cy -= sy * oy / 2; b.cy += sy * oy / 2 }
          clamp(a)
          clamp(b)
        }
      }
    }
    if (!clear && !force) return null
    return cards.map(function(c) {
      return { address: c.address, toplevel: c.toplevel, title: c.title, appClass: c.appClass, wsId: c.wsId,
               x: c.cx - c.w / 2, y: c.cy - c.h / 2, w: c.w, h: c.h }
    })
  }

  // Keeps one delegate per window alive across rebuilds: a card whose
  // workspace changes side slides there instead of being recreated, and a
  // ghost keeps its capture warm.
  function syncModel(model, addresses) {
    for (var i = model.count - 1; i >= 0; i--)
      if (addresses.indexOf(model.get(i).address) < 0) model.remove(i)
    for (var j = 0; j < addresses.length; j++) {
      var found = false
      for (var k = 0; k < model.count; k++)
        if (model.get(k).address === addresses[j]) found = true
      if (!found) model.append({ address: addresses[j] })
    }
  }

  ListModel { id: slots }

  function liveRect(item) {
    return { x: item.x, y: item.y, w: item.width, h: item.height }
  }

  // FLIP over a workspace switch. Reads where every window is drawn now,
  // relays out for the new workspace at once from the cached geometry, then
  // flies a ghost for each window that crosses between the focus area and a
  // band. The refresh that follows the switch retargets ghosts whose real
  // tiles differ from the cache (hidden workspaces keep their old tiling).
  function beginSwitch() {
    if (!root.opened || root.dragAddress !== "") return
    wallBlurTex.scheduleUpdate()
    var oldFocus = root.focusRects
    var from = {}
    for (var a in oldFocus) from[a] = oldFocus[a]
    for (var c in root.cardItems) if (root.cardItems[c].visible) from[c] = root.liveRect(root.cardItems[c])

    root.holdShadows = true
    root.rebuild()
    root.holdShadows = false

    var ws = root.targetMonitor ? root.targetMonitor.activeWorkspace : null
    var fullscreen = ws && ws.hasFullscreen
    for (var o in oldFocus) if (oldFocus[o].fullscreen) fullscreen = true
    if (fullscreen) { root.finishSwitch(); return }

    var ghosted = Object.assign({}, root.ghosted)
    var crossing = Object.keys(oldFocus).filter(function(addr) { return !root.focusRects[addr] && root.winData[addr] })
      .concat(Object.keys(root.focusRects).filter(function(addr) { return !oldFocus[addr] }))
    for (var i = 0; i < crossing.length; i++) {
      var addr = crossing[i]
      // A window already in flight keeps its ghost, which retargets.
      if (ghosted[addr] || !from[addr] || !root.ghostItems[addr]) continue
      root.ghostItems[addr].launch(from[addr])
      ghosted[addr] = true
    }
    root.ghosted = ghosted
    if (Object.keys(ghosted).length > 0) {
      root.transitioning = true
      root.switchStarted = Date.now()
    } else root.syncShadows()
  }

  function checkLanded() {
    var elapsed = Date.now() - root.switchStarted
    if (elapsed < root.switchMinMs) return
    if (elapsed < root.switchMaxMs) {
      for (var a in root.ghosted)
        if (root.ghostItems[a] && !root.ghostItems[a].landed) { root.landedTicks = 0; return }
      // Twice in a row, so a spring passing through its target doesn't count.
      if (++root.landedTicks < 2) return
    }
    root.finishSwitch()
  }

  // Hand-off: ghosts and backdrop go in the same frame, revealing the real
  // windows they sit on and the cards they landed on.
  function finishSwitch() {
    root.transitioning = false
    root.landedTicks = 0
    for (var a in root.ghosted) if (root.ghostItems[a]) root.ghostItems[a].land()
    root.ghosted = ({})
    root.syncShadows()
  }

  ListModel { id: ghosts }

  Connections {
    target: root.targetMonitor
    enabled: root.opened
    function onActiveWorkspaceChanged() { root.beginSwitch() }
  }

  Timer {
    interval: 16
    repeat: true
    running: root.transitioning
    onTriggered: root.checkLanded()
  }

  // Structural window/workspace events only; title and layout events fire on
  // ordinary use and would rebuild for nothing.
  readonly property var refreshEvents: [
    "openwindow", "closewindow", "movewindow", "movewindowv2", "changefloatingmode",
    "createworkspace", "createworkspacev2", "destroyworkspace", "destroyworkspacev2",
    "moveworkspace", "moveworkspacev2", "workspace", "workspacev2", "focusedmon",
    "fullscreen", "pin", "renameworkspace",
  ]

  Connections {
    target: Hyprland
    enabled: root.opened
    function onRawEvent(event) {
      if (root.refreshEvents.indexOf(event.name) < 0) return
      if (!refreshTimer.running) {
        Hyprland.refreshToplevels()
        Hyprland.refreshWorkspaces()
        refreshTimer.restart()
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 80
    onTriggered: root.rebuild()
  }

  // Titles and sizes that change without a structural event are picked
  // up by a slow resync.
  Timer {
    interval: 3000
    repeat: true
    running: root.opened && root.dragAddress === ""
    onTriggered: {
      Hyprland.refreshToplevels()
      refreshTimer.restart()
    }
  }

  // Reserves a side band. 1px wide and input-transparent: only its exclusive
  // zone matters.
  component Reserve: PanelWindow {
    visible: root.opened && root.sideW > 0
    screen: root.targetScreen
    implicitWidth: 1
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: root.sideW
    mask: Region {}
    WlrLayershell.namespace: "omarchy-periphery-reserve"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  }

  Reserve { anchors { top: true; bottom: true; left: true } }
  Reserve { anchors { top: true; bottom: true; right: true } }

  PanelWindow {
    id: stage
    visible: root.opened && root.sideW > 0
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-periphery"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Only the side bands take input; the focus area stays click-through.
    // A drag keeps the pointer grab past the band edge.
    mask: Region {
      item: leftBand
      Region { item: rightBand; intersection: Intersection.Combine }
    }

    Item { id: leftBand; x: 0; width: root.sideW; height: parent.height }
    Item { id: rightBand; x: parent.width - root.sideW; width: root.sideW; height: parent.height }

    Repeater {
      model: root.headers

      delegate: Text {
        required property var modelData
        x: modelData.x
        y: modelData.y
        width: modelData.w
        height: root.headerHeight
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        text: modelData.label
        color: root.foreground
        opacity: 0.8
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    Repeater {
      model: slots

      delegate: WindowCard {
        id: card
        required property string address
        readonly property var entry: root.winData[address]
        // Placement animates only once the card has settled in, so a new
        // card appears in place and fades in rather than flying from 0,0.
        property bool settled: false

        host: root
        win: entry || ({ address: address, title: "", appClass: "", toplevel: null })
        // Hidden, not faded, while its ghost flies: the ghost lands on it.
        visible: !!entry && !root.ghosted[address]
        x: entry ? entry.x : 0
        y: entry ? entry.y : 0
        width: entry ? entry.w : 0
        height: entry ? entry.h : 0
        opacity: settled ? (dragging ? 0.35 : 1) : 0

        Behavior on x { enabled: card.settled; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on y { enabled: card.settled; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on width { enabled: card.settled; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on height { enabled: card.settled; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on opacity { NumberAnimation { duration: root.slideDuration; easing.type: Easing.OutCubic } }

        Component.onCompleted: {
          root.cardItems[address] = card
          Qt.callLater(function() { card.settled = true })
        }
        Component.onDestruction: if (root.cardItems[address] === card) delete root.cardItems[address]
      }
    }
  }

  // Above everything: the switch ghosts over a wallpaper backdrop, and the
  // dragged card with its drop hints. Mapped for as long as the mode is on,
  // so a switch draws its first frame without waiting for a new surface.
  PanelWindow {
    visible: root.opened && root.sideW > 0
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.namespace: "omarchy-periphery-fx"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Covers the tiling area (the bar stays visible) so the real windows of
    // the new workspace, already in place, show only once the ghosts land.
    Item {
      x: root.sideW - root.coverBleed
      y: root.reserved[1]
      width: root.focusW + root.coverBleed * 2
      height: root.monH - root.reserved[1] - root.reserved[3]
      clip: true
      visible: root.transitioning

      Rectangle {
        anchors.fill: parent
        color: root.background
      }

      // Lined up with the full-screen wallpaper underneath.
      Image {
        x: -parent.x
        y: -parent.y
        width: root.monW
        height: root.monH
        source: Util.fileUrl(root.wallpaper)
        fillMode: Image.PreserveAspectCrop
        cache: true
      }
    }

    // The wallpaper, blurred once into a texture that each ghost samples.
    Item {
      id: wallSource
      width: root.monW
      height: root.monH
      visible: false

      Image {
        anchors.fill: parent
        source: Util.fileUrl(root.wallpaper)
        fillMode: Image.PreserveAspectCrop
        cache: true
      }
    }

    MultiEffect {
      id: wallBlur
      source: wallSource
      width: root.monW
      height: root.monH
      visible: false
      blurEnabled: true
      // MultiEffect blurs up to blurMax; blurMultiplier stretches past it.
      blurMax: 64
      blur: Math.min(1, root.ghostBlur / 64)
      blurMultiplier: Math.max(0, root.ghostBlur / 64 - 1)
      contrast: root.ghostBlurContrast
      saturation: root.ghostBlurSaturation
    }

    ShaderEffectSource {
      id: wallBlurTex
      sourceItem: wallBlur
      width: root.monW
      height: root.monH
      visible: false
      // Rendered once per switch (beginSwitch): rendering every frame cost
      // frames, and a texture rendered only once came back blank later.
      live: false
    }

    Repeater {
      model: ghosts

      // One per window on the monitor, for as long as the mode is on: a new
      // ScreencopyView takes a few hundred ms to get its first frame, so a
      // ghost made at switch time flew empty. Hidden until launched.
      delegate: Item {
        id: flyer
        required property string address
        // Where the window is going: its tile, or its card. Follows rebuilds.
        readonly property var target: root.focusRects[address] || root.winData[address] || null
        // Kept when the window closes mid-flight, so the ghost doesn't jump.
        property var lastTarget: target
        // The from rect of the current flight.
        property real fx: 0
        property real fy: 0
        property real fw: 0
        property real fh: 0
        // launched puts the ghost at its from rect; armed enables the springs
        // a step before flying moves it on to the target.
        property bool launched: false
        property bool armed: false
        property bool flying: false
        // Behavior-driven animations don't update `running`, so landing is
        // measured: on the target, to within half a pixel.
        readonly property bool landed: !target || (Math.abs(x - target.x) < 0.5 && Math.abs(y - target.y) < 0.5
          && Math.abs(width - target.w) < 0.5 && Math.abs(height - target.h) < 0.5)

        function launch(r) {
          armed = false
          flying = false
          fx = r.x; fy = r.y; fw = r.w; fh = r.h
          launched = true
          Qt.callLater(function() { flyer.armed = true; flyer.flying = true })
        }

        function land() {
          armed = false
          flying = false
          launched = false
        }

        onTargetChanged: if (target) lastTarget = target
        // At rest it sits on its target, at full size, so it keeps capturing.
        x: launched && !flying ? fx : (lastTarget ? lastTarget.x : 0)
        y: launched && !flying ? fy : (lastTarget ? lastTarget.y : 0)
        width: launched && !flying ? fw : (lastTarget ? lastTarget.w : 1)
        height: launched && !flying ? fh : (lastTarget ? lastTarget.h : 1)
        visible: !!root.ghosted[address]
        opacity: target ? 1 : 0

        Behavior on x { enabled: flyer.armed; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on y { enabled: flyer.armed; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on width { enabled: flyer.armed; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on height { enabled: flyer.armed; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration } }
        Component.onCompleted: root.ghostItems[address] = flyer
        Component.onDestruction: if (root.ghostItems[address] === flyer) delete root.ghostItems[address]

        // How far along its flight the ghost is, 0 at the start, 1 landed.
        readonly property real travel: {
          if (!lastTarget) return 1
          var d = Math.hypot(lastTarget.x - fx, lastTarget.y - fy)
          return d < 1 ? 1 : Math.min(1, Math.hypot(x - fx, y - fy) / d)
        }

        // The blurred wallpaper behind the window, as Hyprland draws it in
        // the focus area. Cards sit on the sharp wallpaper, so the blur
        // fades in over the first half of the way into the focus area (the
        // spring's slow tail would leave it short at landing) and out over
        // the first half of the way back.
        Item {
          anchors.fill: parent
          clip: true
          opacity: {
            var t = Math.min(1, flyer.travel * 2)
            return root.focusRects[flyer.address] ? t : 1 - t
          }

          ShaderEffect {
            x: -flyer.x
            y: -flyer.y
            width: root.monW
            height: root.monH
            property variant source: wallBlurTex
          }
        }

        // ScreencopyView doesn't blend: it overwrites what is under it with
        // the window's own pixels and alpha. A translucent window (foot) then
        // wiped the blur patch and left the surface translucent, so the real
        // window behind showed through. Rendered alone into its own layer,
        // it is drawn over the patch with normal blending.
        ScreencopyView {
          anchors.fill: parent
          layer.enabled: flyer.visible
          captureSource: flyer.lastTarget && flyer.lastTarget.toplevel ? flyer.lastTarget.toplevel.wayland : null
          live: root.opened
        }
      }
    }

    Rectangle {
      x: root.sideW + root.bandMargin / 2
      y: root.bandMargin / 2
      width: root.focusW - root.bandMargin
      height: root.monH - root.bandMargin
      radius: root.cornerRadius * 2
      color: Util.alpha(root.accent, 0.06)
      border.color: root.accent
      border.width: Math.max(2, Style.space(2))
      opacity: root.dragOverFocus ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: root.fadeDuration } }
    }

    // The workspace group the card would land in.
    Repeater {
      model: root.headers

      delegate: Rectangle {
        required property var modelData
        x: modelData.x - root.bandMargin / 2
        y: modelData.y - root.bandMargin / 2
        width: modelData.w + root.bandMargin
        height: modelData.h + root.bandMargin
        radius: root.cornerRadius * 2
        color: Util.alpha(root.accent, 0.06)
        border.color: root.accent
        border.width: Math.max(2, Style.space(2))
        opacity: root.dragTarget && root.dragTarget.id === modelData.id
          && root.dragWin && root.dragWin.wsId !== modelData.id ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.fadeDuration } }
      }
    }

    Item {
      id: ghost
      visible: root.dragAddress !== ""
      // Grows a little once it's over the focus area.
      readonly property real grow: root.dragOverFocus ? 1.25 : 1.05
      width: root.dragW * grow
      height: root.dragH * grow
      x: root.dragX - root.grabX * grow
      y: root.dragY - root.grabY * grow
      Behavior on width { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: root.fadeDuration; easing.type: Easing.OutCubic } }

      Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.background
      }

      // Own layer so it blends, like the switch ghosts (see there).
      ScreencopyView {
        anchors.fill: parent
        layer.enabled: ghost.visible
        captureSource: root.dragWin && root.dragWin.toplevel ? root.dragWin.toplevel.wayland : null
        live: root.dragAddress !== ""
      }

      Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: "transparent"
        border.color: root.accent
        border.width: Math.max(2, Style.space(2))
      }
    }
  }
}
