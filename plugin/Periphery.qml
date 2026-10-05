import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "lib/hyprland.mjs" as Hypr
import "lib/layout.mjs" as Layout
import "lib/selection.mjs" as Selection

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
  // A card-click flight is running (flight), or set up and waiting for
  // Hyprland to switch (flightPending).
  property bool flight: false
  property bool flightPending: false
  // Address -> true while a ghost flies for that window; its card waits.
  property var ghosted: ({})
  // Resolved wallpaper file for the backdrop.
  property string wallpaper: ""
  // Hyprland's own workspace slide is off while the mode is on; this holds
  // the Lua that turns it back on.
  property bool hyprSlideOff: false
  // While the mode is on, Hyprland animates workspace switches itself, with
  // the theme's curve and speed but this style: a short slide stays mostly
  // inside the focus area (a full slide would cross the bands, as windows
  // are drawn above them).
  readonly property string workspaceStyle: "slidefade 10%"
  // How far arriving and leaving cards travel, along with the focus area
  // (src/hyprland/specs.md).
  readonly property var cardTravel: Hypr.cardTravel(workspaceStyle, monW, monH)
  readonly property bool cardSlideVertical: cardTravel.vertical
  readonly property real cardSlide: cardTravel.distance
  // The workspace in the focus area, and which way the last switch went:
  // 1 to a higher workspace (Hyprland slides the content left or up), -1 to
  // a lower one.
  property int shownWorkspace: -1
  property int switchDir: 0
  // The hl.animation call for that, built from the theme's animation.
  property string hyprModeLua: 'hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "default", style = "' + workspaceStyle + '" })'
  readonly property string hyprOffLua: Hypr.workspacesOffLua
  property string hyprSlideRestore: ""
  // Address -> true for windows we turned the shadow off for, during a
  // card-click flight: the windows of the target workspace, whose shadows
  // would show past the backdrop ahead of their ghosts (they are hidden
  // until the switch, so they lose nothing).
  property var shadowless: ({})
  // The periphery selection: the card that has the focus instead of a focus
  // area window, set by hovering a card or by the focus keys moving past the
  // focus area's edge (latest input wins). hypr.lua points the close and
  // fullscreen keys at it and greys the active window's border.
  property string selected: ""
  // The window that was active when the card got selected.
  property string selectedOver: ""
  // Which bands have cards, for the focus keys to move into.
  property bool cardsLeft: false
  property bool cardsRight: false
  // The state last sent to hypr.lua, and the one to send.
  property string luaSent: ""
  readonly property string luaState: Hypr.hookStateLua({
    opened: root.opened, cardsLeft: root.cardsLeft, cardsRight: root.cardsRight,
    monX: root.monX, monY: root.monY, monW: root.monW, monH: root.monH, sideW: root.sideW,
    selected: root.selected,
  })
  onLuaStateChanged: root.sendLuaState()

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color selectedText: Color.menu.selectedText
  property color accent: Color.accent
  readonly property int cornerRadius: Style.cornerRadius
  // Cards are drawn like windows, in the theme's border: the inactive border
  // at rest, the active one (Hyprland's active-border gradient, from the
  // theme's [hyprland] shell tokens) when selected. The theme's popups border
  // is its Hyprland inactive border. Width and rounding are Hyprland's.
  property int windowBorder: 1
  property int windowRounding: 0
  readonly property var activeBorder: Border.hyprlandActiveSpec(root.accent, root.windowBorder)
  readonly property var inactiveBorder: Border.surfaceSpec("popups", "border", root.border, root.windowBorder)
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
    root.shownWorkspace = root.currentWorkspaceId()
    root.layoutSignature = ""
    root.disableHyprSlide()
    if (!wallpaperProc.running) wallpaperProc.running = true
    if (!decorProc.running) decorProc.running = true
    Hyprland.refreshToplevels()
    Hyprland.refreshWorkspaces()
    Hyprland.refreshMonitors()
    refreshTimer.restart()
  }

  function close() {
    root.clearSelection()
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
    Quickshell.execDetached(["hyprctl", "eval", "if periphery_close then periphery_close() end"])
  }

  // One hyprctl at a time, so the states reach hypr.lua in order; a state
  // that changed meanwhile goes after.
  function sendLuaState() {
    if (luaProc.running || root.luaState === root.luaSent) return
    root.luaSent = root.luaState
    luaProc.command = ["hyprctl", "eval", root.luaState]
    luaProc.running = true
  }

  Process {
    id: luaProc
    // Not onExited: `running` is still true there, so the next state waited
    // for good.
    onRunningChanged: if (!running) root.sendLuaState()
  }

  // over: the active window, when known better than activeToplevel (which
  // can lag behind a focus change).
  function select(address, over) {
    if (!root.opened || root.dragAddress !== "" || !root.winData[address]) return
    var t = Hyprland.activeToplevel
    if (over !== undefined) root.selectedOver = over
    else if (!root.selected) root.selectedOver = t ? root.normalizeAddress(t.address) : ""
    root.selected = address
  }

  function clearSelection() {
    root.selected = ""
  }

  // A focus key moved past the focus area's edge towards a band ("l" or
  // "r"), from the active window (src/selection/specs.md).
  function enterBand(dir, active) {
    if (!root.opened) return
    var best = Selection.enterBand(root.winData, dir, root.focusRects[active] || null, root.monW, root.monH)
    if (best) root.select(best, active)
  }

  // A focus key on the selected card (src/selection/specs.md).
  function stepSelection(dir) {
    var step = Selection.stepSelection(root.winData, root.selected, dir, root.focusRects, root.monW, root.sideW)
    if (step.kind === "select") root.select(step.address)
    else if (step.kind === "focus") {
      root.clearSelection()
      if (step.address) root.activateWindow(step.address)
    } else if (step.kind === "clear") root.clearSelection()
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

  // Reads the theme's workspaces animation, so it can be put back, and
  // switches it to workspaceStyle with the same curve and speed.
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

  Process {
    id: slideProc
    command: ["hyprctl", "animations", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          root.hyprSlideRestore = Hypr.workspaceAnimationLua(text)
          var mode = Hypr.workspaceAnimationLua(text, root.workspaceStyle)
          if (mode) root.hyprModeLua = mode
        } catch (e) { root.hyprSlideRestore = "" }
        if (root.hyprSlideOff) Quickshell.execDetached(["hyprctl", "eval", root.hyprModeLua])
      }
    }
    // The mode went off before the slide was disabled: put it back now.
    onExited: if (!root.hyprSlideOff) { root.hyprSlideOff = true; root.restoreHyprSlide() }
  }

  // Hyprland's border width and rounding, for the cards.
  Process {
    id: decorProc
    command: ["sh", "-c", "hyprctl -j getoption general:border_size; hyprctl -j getoption decoration:rounding"]
    stdout: StdioCollector {
      onStreamFinished: {
        var decoration = Hypr.parseDecoration(text)
        if (decoration.borderSize !== undefined) root.windowBorder = decoration.borderSize
        if (decoration.rounding !== undefined) root.windowRounding = decoration.rounding
      }
    }
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

  // Card click: the Exposé flight. Unlike a keyboard switch, the plugin
  // starts this one, so it can get ahead of Hyprland: it puts the backdrop
  // up with ghosts of the current focus windows on their tiles (the screen
  // looks the same), waits until that is on screen, then turns Hyprland's
  // workspace animation off for this switch and switches. beginSwitch flies
  // the ghosts; finishSwitch turns the animation back on.
  function flyTo(address) {
    var ws = root.targetMonitor ? root.targetMonitor.activeWorkspace : null
    // Only a window with a card switches workspace: one in the focus area,
    // on another monitor or on a special workspace would leave the flight
    // waiting for a switch that never comes.
    if (!root.opened || root.dragAddress !== "" || root.transitioning || (ws && ws.hasFullscreen)
        || !root.winData[address]) {
      root.activateWindow(address)
      return
    }
    root.clearSelection()
    wallBlurTex.scheduleUpdate()
    var ghosted = {}
    for (var a in root.focusRects) {
      if (!root.ghostItems[a]) continue
      root.ghostItems[a].launch(root.focusRects[a])
      ghosted[a] = true
    }
    root.ghosted = ghosted
    root.flight = true
    root.flightPending = true
    root.transitioning = true
    root.switchStarted = Date.now()
    // The target workspace's windows lose their shadow until the landing.
    var target = root.winData[address].wsId
    var shadowless = {}
    for (var w in root.winData) if (root.winData[w].wsId === target) shadowless[w] = true
    root.shadowless = shadowless
    flightTimer.address = address
    flightTimer.restart()
  }

  Timer {
    id: flightTimer
    property string address: ""
    // Two frames at 60 Hz: the backdrop is on screen before Hyprland switches.
    interval: 34
    onTriggered: Quickshell.execDetached(["hyprctl", "--batch", Object.keys(root.shadowless).map(function(a) {
        return 'dispatch hl.dsp.window.set_prop({ window = "address:' + a + '", prop = "no_shadow", value = "1" })'
      }).concat(["eval " + root.hyprOffLua, 'dispatch hl.dsp.focus({ window = "address:' + address + '" })']).join(" ; ")])
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
    return Selection.groupAt(root.headers, x, y, root.bandMargin, root.groupGap)
  }

  function inBand(x) {
    return x < root.sideW || x > root.monW - root.sideW
  }

  // Lowest workspace number with nothing on it, for drops on empty band.
  function freeWorkspaceId() {
    var occupied = []
    var list = Hyprland.workspaces.values
    for (var i = 0; i < list.length; i++)
      if (list[i].id > 0 && list[i].toplevels && list[i].toplevels.values.length > 0) occupied.push(list[i].id)
    return Selection.freeWorkspaceId(occupied, root.currentWorkspaceId())
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

    // Goes to a window the way a card click does (the Exposé flight).
    function flyTo(address: string): void {
      root.flyTo(root.normalizeAddress(address))
    }

    // From hypr.lua: a focus key ("l", "r", "u", "d") past the focus area's
    // edge (enter), or on a selected card (step).
    function enter(dir: string, active: string): void {
      root.enterBand(dir, active === "none" ? "" : root.normalizeAddress(active))
    }

    function step(dir: string): void {
      root.stepSelection(dir)
    }

    // From hypr.lua: Return on a selected card goes to its window (the
    // Exposé flight).
    function activate(): void {
      if (root.selected) root.flyTo(root.selected)
    }

    // From hypr.lua: Escape, or the pointer moved over the focus area, whose
    // windows get the focus back.
    function clear(): void {
      root.clearSelection()
    }

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
    root.clearSelection()
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
    var others = []
    var focus = {}
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < toplevels.length; i++) {
      var t = toplevels[i]
      var ipc = t.lastIpcObject
      if (!ipc || !ipc.workspace || !ipc.at || !ipc.size) continue
      if (ipc.mapped === false || ipc.hidden === true) continue
      if (root.monId >= 0 && ipc.monitor !== undefined && ipc.monitor !== root.monId) continue
      var wsId = ipc.workspace.id
      var address = normalizeAddress(ipc.address || t.address)
      if (wsId === current) {
        focus[address] = { address: address, toplevel: t, fullscreen: !!ipc.fullscreen,
                           x: ipc.at[0] - root.monX, y: ipc.at[1] - root.monY,
                           w: Math.max(1, ipc.size[0]), h: Math.max(1, ipc.size[1]) }
        continue
      }
      if (wsId <= 0) continue
      others.push({
        toplevel: t,
        address: address,
        title: ipc.title || t.title || "",
        appClass: ipc["class"] || "",
        floating: !!ipc.floating,
        wsId: wsId,
        wsName: String(ipc.workspace.name || wsId),
        rx: ipc.at[0],
        ry: ipc.at[1],
        rw: Math.max(1, ipc.size[0]),
        rh: Math.max(1, ipc.size[1]),
      })
    }

    others.sort(function(a, b) { return a.address < b.address ? -1 : a.address > b.address ? 1 : 0 })
    var signature = JSON.stringify([root.sideW, current, others.map(function(w) {
      return [w.address, w.wsId, w.wsName, w.title, w.floating, w.rx, w.ry, w.rw, w.rh]
    }), Object.keys(focus).map(function(a) { var f = focus[a]; return [a, f.fullscreen, f.x, f.y, f.w, f.h] })])
    if (signature === root.layoutSignature) return
    root.layoutSignature = signature
    root.focusRects = focus

    // See src/layout/specs.md.
    var layout = Layout.layoutBands(others, current, {
      monW: root.monW, monH: root.monH, sideW: root.sideW, bandMargin: root.bandMargin,
      cardGap: root.cardGap, groupGap: root.groupGap, headerHeight: root.headerHeight,
      maxStretch: root.maxStretch,
    })
    root.winData = layout.cards
    root.headers = layout.headers
    if (root.selected && !layout.cards[root.selected]) root.clearSelection()
    root.cardsLeft = layout.left.length > 0
    root.cardsRight = layout.right.length > 0
    syncSlots(Object.keys(layout.cards))
    // Ghosts for every window on the monitor, band or focus area.
    syncModel(ghosts, Object.keys(layout.cards).concat(Object.keys(focus)))
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

  // Cards: a card for a new band window is added; a card whose window left
  // the bands is not removed here but fades out first and then removes
  // itself (removeSlot). A window back before that just fades in again.
  function syncSlots(addresses) {
    for (var j = 0; j < addresses.length; j++) {
      var found = false
      for (var k = 0; k < slots.count; k++)
        if (slots.get(k).address === addresses[j]) found = true
      if (!found) slots.append({ address: addresses[j] })
    }
  }

  function removeSlot(address) {
    if (root.winData[address]) return
    for (var i = slots.count - 1; i >= 0; i--)
      if (slots.get(i).address === address) slots.remove(i)
  }

  function liveRect(item) {
    return { x: item.x, y: item.y, w: item.width, h: item.height }
  }

  // FLIP over a workspace switch. Reads where every window is drawn now,
  // relays out for the new workspace at once from the cached geometry, then
  // flies a ghost for each window that crosses between the focus area and a
  // band. The refresh that follows the switch retargets ghosts whose real
  // tiles differ from the cache (hidden workspaces keep their old tiling).
  function beginSwitch() {
    if (!root.opened) return
    var current = root.currentWorkspaceId()
    root.clearSelection()
    root.switchDir = current > root.shownWorkspace ? 1 : current < root.shownWorkspace ? -1 : 0
    root.shownWorkspace = current
    // A switch the plugin didn't start (keyboard, bar): Hyprland animates the
    // focus area; the cards move to their new places right away.
    if (!root.flightPending) {
      root.rebuild()
      return
    }
    root.flightPending = false
    var oldFocus = root.focusRects
    var from = {}
    for (var a in oldFocus) from[a] = oldFocus[a]
    for (var c in root.cardItems) if (root.cardItems[c].visible) from[c] = root.liveRect(root.cardItems[c])

    root.rebuild()

    var ws = root.targetMonitor ? root.targetMonitor.activeWorkspace : null
    var fullscreen = ws && ws.hasFullscreen
    for (var o in oldFocus) if (oldFocus[o].fullscreen) fullscreen = true
    if (fullscreen) { root.finishSwitch(); return }

    var ghosted = Object.assign({}, root.ghosted)
    var crossing = Object.keys(oldFocus).filter(function(addr) { return !root.focusRects[addr] && root.winData[addr] })
      .concat(Object.keys(root.focusRects).filter(function(addr) { return !oldFocus[addr] }))
    for (var i = 0; i < crossing.length; i++) {
      var addr = crossing[i]
      // The outgoing ghosts are up already, on their tiles.
      if (ghosted[addr] || !from[addr] || !root.ghostItems[addr]) continue
      root.ghostItems[addr].launch(from[addr])
      ghosted[addr] = true
    }
    root.ghosted = ghosted
    for (var g in ghosted) if (root.ghostItems[g]) root.ghostItems[g].fly()
    root.switchStarted = Date.now()
  }

  function checkLanded() {
    var elapsed = Date.now() - root.switchStarted
    // Waiting for Hyprland to switch: the ghosts sit on their tiles, landed.
    if (root.flightPending && elapsed < root.switchMaxMs) return
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
    root.flightPending = false
    if (root.flight && root.opened) Quickshell.execDetached(["hyprctl", "eval", root.hyprModeLua])
    if (root.flight) root.restoreShadows()
    root.flight = false
  }

  ListModel { id: ghosts }

  Connections {
    target: root.targetMonitor
    enabled: root.opened
    function onActiveWorkspaceChanged() { root.beginSwitch() }
  }

  // Focus moved to a window (pointer, keys, anything): it has the focus now,
  // not the card.
  Connections {
    target: Hyprland
    enabled: root.opened
    function onActiveToplevelChanged() {
      var t = Hyprland.activeToplevel
      if (t && root.normalizeAddress(t.address) !== root.selectedOver) root.clearSelection()
    }
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
      // A reload starts hypr.lua afresh: it gets the state again.
      // A theme switch reloads too: the border width and rounding may change.
      if (event.name === "configreloaded") {
        root.luaSent = ""
        root.sendLuaState()
        if (!decorProc.running) decorProc.running = true
      }
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
        // The last placement, so a leaving card fades out where it was.
        property var shown: entry
        onEntryChanged: if (entry) shown = entry
        // Its window left the bands (onto the focus area, or closed).
        readonly property bool leaving: !entry
        // Placement animates only once the card has settled in, so a new
        // card appears in place and fades in rather than flying from 0,0.
        property bool settled: false

        host: root
        win: shown || ({ address: address, title: "", appClass: "", toplevel: null })
        enabled: !leaving
        // Hidden, not faded, while its ghost flies: the ghost lands on it.
        visible: !!shown && !root.ghosted[address]
        x: shown ? shown.x : 0
        y: shown ? shown.y : 0
        width: shown ? shown.w : 0
        height: shown ? shown.h : 0
        // Cards fade in and out while they travel with the focus area, the
        // way Hyprland slides the workspace: an arriving card (its window
        // just slid out of the focus area) comes from the switch side, a
        // leaving card (its window slides in) goes towards it. Not during a
        // flight: the ghost lands on the card, which must be in place.
        readonly property real travel: root.flight ? 0 : -root.switchDir * root.cardSlide
        readonly property real arriveFrom: -travel
        property real leaveTo: 0
        property real slide: leaving ? leaveTo : (settled ? 0 : arriveFrom)
        transform: Translate {
          x: root.cardSlideVertical ? 0 : card.slide
          y: root.cardSlideVertical ? card.slide : 0
        }
        opacity: settled && !leaving ? (dragging ? 0.35 : 1) : 0
        onOpacityChanged: if (leaving && opacity === 0) root.removeSlot(address)
        onLeavingChanged: {
          if (leaving) leaveTo = travel
          if (leaving && opacity === 0) root.removeSlot(address)
        }

        Behavior on x { enabled: card.settled; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on y { enabled: card.settled; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on width { enabled: card.settled; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on height { enabled: card.settled; SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }
        Behavior on opacity { NumberAnimation { duration: root.slideDuration; easing.type: Easing.OutCubic } }
        // The theme's spring, like Hyprland's workspace slide it travels with.
        Behavior on slide { SpringAnimation { spring: root.springStrength; damping: root.springDamping; epsilon: root.springEpsilon } }

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
        }

        function fly() {
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

      BorderOverlay {
        borderSpec: root.activeBorder
        radius: root.windowRounding
      }
    }
  }
}
