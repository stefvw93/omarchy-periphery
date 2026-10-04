# Periphery exposé (`stef.periphery`)

Proof of concept. Status: works on one monitor (DP-3, 2560×1440, scale 1), Hyprland 0.56.2, Omarchy shell.

## Problem

A wide monitor puts windows at the far edges of the screen. Content there is hard to read, but it is also out of the way. Tiling uses the full width for the current workspace. Windows on other workspaces are not visible.

Scott Jenson showed a prototype at a KDE event (["Are we really going to use the same Desktop UX forever?"](https://www.youtube.com/watch?v=V7AfAcQwLW0)). It keeps the active work in a centred area and keeps other work at small scale in the periphery.

## Value

- The current workspace tiles in a centred area of good reading width.
- The windows of the other workspaces stay visible, live, at the screen sides.
- One click goes to a window. One drag moves a window between the focus area and other workspaces.
- One key turns the mode on and off. When the mode is off, the desktop is unchanged.

## Ubiquitous language

| Term | Definition |
|------|------------|
| Focus area | The centred part of the monitor. Tiling and the bar use only this area. |
| Band | The part of the monitor at the left or right of the focus area. |
| Periphery | The two bands together. |
| Card | The live thumbnail of one window in a band. |
| Group | The cards of one workspace, with the workspace label above them. |
| Ratio | Focus area width divided by monitor height. The default is `1.25` (5:4). |
| Side width (`sideW`) | The width of one band: `(monW - round(monH × ratio)) / 2`. |
| Drop | The release of a drag. The drop position selects the target workspace. |

## Behaviour

### Toggle

`SUPER + E` toggles the mode. The mode stays on until the next toggle, a shell restart, or a plugin reload.

When the mode turns on, Hyprland re-tiles the current workspace into the focus area. The bar shrinks to the focus area width. When the mode turns off, both return to full width.

On DP-3 with the default ratio: focus area 1800 px, each band 380 px.

### Placement of groups

The plugin shows the occupied regular workspaces (id > 0) of the focused monitor. It does not show the current workspace or special workspaces.

- Workspaces with a lower id than the current workspace go in the left band.
- Workspaces with a higher id go in the right band.
- Each band orders its groups by id, from top to bottom.
- Wrap rule: if the left band is empty and the right band has 2 or more groups, the group with the highest id moves to the left band. If the right band is empty and the left band has 2 or more groups, the group with the lowest id moves to the right band.

Example, with workspaces 1, 2, 3 and 4 occupied:

| Current | Left band | Right band |
|---------|-----------|------------|
| 1 | 4 | 2, 3 |
| 2 | 1 | 3, 4 |
| 4 | 2, 3 | 1 |

### Placement of cards

The cards in a group keep the relative positions of their windows on the workspace (macOS exposé style):

1. Each group gets a vertical slice of the band. The slice height is proportional to the group's bounding box height at band width. The slice can stretch vertically up to `maxStretch` (6) to use a tall band.
2. The centre of each window maps from the group's bounding box into the slice. The map can be anisotropic.
3. All cards in a band use one scale. A card keeps the aspect ratio of its window.
4. A solver pushes overlapping cards apart. It pushes along the axis with the smaller overlap if there is room on that axis. If not, it uses the other axis.
5. A binary search finds the largest scale at which all groups of the band have no overlap.

Two tiled windows next to each other do not fit next to each other in a 348 px band. The solver stacks them vertically with a small horizontal offset. The offset shows which window was on the left.

The workspace label is above the top card of its group.

### Workspace switch animation

When the workspace of the monitor changes (keyboard, bar, card click), each window flies from where it is drawn to where it goes:

- Windows of the new workspace fly from their card to their tile in the focus area.
- Windows of the old workspace fly from their tile to their new card in a band.
- The other cards slide to their new places in the bands.

The plugin cannot move real windows. It flies a ghost (a live `ScreencopyView`) per window on the Overlay layer. Each window on the monitor has a ghost for as long as the mode is on, hidden and capturing: a new `ScreencopyView` takes a few hundred ms to get its first frame, so a ghost made at switch time flew empty. Hyprland switches the workspace at once underneath. A wallpaper backdrop covers the tiling area (not the bar) until the ghosts land. Then ghosts and backdrop go in one frame and show the real windows and cards under them.

1. On `activeWorkspaceChanged` of the monitor, the plugin reads the current rects: tiles from the cache, cards and ghosts from their live items (a card that is still sliding starts from where it is).
2. It relays out at once from the cached geometry. A hidden workspace can have old tiling, so the incoming targets can be wrong.
3. The refresh 80 ms later gives the real tiles. The ghosts retarget in flight.
4. When every ghost is on its target to within half a pixel, two checks in a row (at least 120 ms, at most 1.5 s), the ghosts hand off. Qt does not update `running` for an animation driven by a `Behavior`, so landing is measured, not read.

The real windows' decorations reach past the backdrop: the shadow (60 px range) into the bands and under the translucent bar, and the 1 px border of a window tiled flush against the band (smart gaps: one window, gaps 0). So:

- Windows in the bands have `no_shadow` while the mode is on (`hl.dsp.window.set_prop`). They are hidden, so nothing changes on screen. A window arrives in the focus area without a shadow and gets it back at the hand-off (`value = "unset"`, so a window rule's `no_shadow` stays).
- The backdrop reaches `coverBleed` (2 px) into each band to cover the border.

The mode turning off or the plugin unloading gives all shadows back.

A switch during a switch keeps the ghosts in flight and retargets them; the springs keep their velocity. No animation when the old or new workspace has a fullscreen window, or during a card drag.

While the mode is on, Hyprland's workspace slide is replaced by a 150 ms fade that starts very slowly (`hl.animation({ leaf = "workspaces", enabled = true, speed = 1.5, bezier = "easeInOutCubic", style = "fade" })` through `hyprctl eval`). Turning it off is not enough: Hyprland shows the new workspace one frame before the plugin's first frame, a visible flash. With the fade, the new workspace is under 1% visible on that frame, and from the next frame on the backdrop hides the rest of the fade. The plugin reads the slide settings first from `hyprctl animations -j` and writes them back when the mode turns off or the plugin unloads. If it could not read them, it runs `hyprctl reload config-only`.

### Thumbnails

Each card is a `ScreencopyView` with `live: true`. Cards update at the screen frame rate. A video on another workspace plays smoothly in its card.

A card without a frame yet shows the window class on the theme background.

### Pointer actions on cards

| Action | Result |
|--------|--------|
| Hover | Accent border and window title. |
| Click | Focus the window. Hyprland goes to its workspace. That workspace leaves the periphery and the previous workspace enters it. |
| Drag, drop in the focus area | Move the window to the current workspace and focus it. Dwindle tiles it next to the window under the pointer. |
| Drag, drop on another group | Move the window to the workspace of that group. |
| Drag, drop on empty band space | Move the window to the lowest free workspace id. |
| Drag, drop on its own group | No change. |

During a card drag, a live copy of the window follows the pointer above all windows. The focus area or the target group gets an accent outline.

### Drag of a real window into a band

Use the existing Omarchy binding `SUPER + mouse:272` (drag a window). Release the pointer over a band:

- Over a group: the window moves to the workspace of that group.
- Over empty band space: the window moves to the lowest free workspace id.

Hyprland does not report pointer motion during its own window drag. The plugin shows no drop outline for this drag. The window leaves the focus area on release.

## Architecture

### Files

```
~/.config/omarchy/plugins/stef.periphery/
  manifest.json    plugin kind "panel", entry Periphery.qml
  Periphery.qml    state, layout solver, surfaces, drag and drop, IPC
  WindowCard.qml   one card: thumbnail, hover, click and drag input
  SPEC.md          this file
```

### Layer surfaces

The plugin creates 4 layer surfaces on the focused monitor (the reserve surface twice). All exist only while the mode is on.

| Namespace | Layer | Size | Exclusive zone | Input | Use |
|-----------|-------|------|----------------|-------|-----|
| `omarchy-periphery-reserve` (×2) | Bottom | 1 px wide, full height, left and right edge | `sideW` | none | Reserve the bands. |
| `omarchy-periphery` | Bottom | full screen | ignore | bands only | Draw the groups and cards. |
| `omarchy-periphery-fx` | Overlay | full screen | ignore | none | Draw the switch ghosts and backdrop, the dragged card and drop outlines. |

Hyprland arranges layer surfaces in layer order: Background, Bottom, Top, Overlay. A surface with an exclusive zone gets the area that is left after the surfaces before it. The reserve surfaces are on the Bottom layer, so they take the bands first. The Omarchy bar is on the Top layer, so it gets only the focus area width. The bar needs no change.

The cards are on the Bottom layer: above the wallpaper, below all windows. A floating window can move over a band and cover cards.

One full-screen surface draws both bands. A card can then animate from one band to the other.

### Data flow

1. Hyprland raw events start a refresh: window open, close, move, float change, workspace create, destroy, rename and switch, monitor focus, fullscreen and pin.
2. The refresh calls `Hyprland.refreshToplevels()`. After 80 ms it reads `lastIpcObject` of each toplevel.
3. `rebuild()` builds the groups, sorts them into bands and runs the solver.
4. A layout signature skips the rebuild if nothing changed.
5. A `ListModel` keyed by window address keeps one card delegate per window. A card that changes position moves on a spring. A new card fades in at its position (320 ms).
6. `rebuild()` also caches the tiles of the current workspace (`focusRects`), the start rects of a workspace switch.
7. A 3 s timer resyncs titles and sizes that change without a structural event. It stops during a drag.

### IPC

The plugin has an `IpcHandler` (needs `import Quickshell.Io`):

```bash
# Drop a window at global pixel position (x, y). Ignored outside the bands or when the mode is off.
omarchy-shell stef.periphery dropWindow 0x56c7bf955960 2300 300
```

The shell toggle passes an optional payload to `open()`:

```bash
omarchy-shell shell toggle stef.periphery '{}'
omarchy-shell shell toggle stef.periphery '{"ratio": 1.333}'   # 4:3 focus area
```

### Hyprland dispatches

The plugin uses Lua dispatch strings:

```lua
hl.dsp.focus({ window = "address:0x56c7bf955960" })
hl.dsp.window.move({ workspace = "2", follow = false, window = "address:0x56c7bf955960" })
```

`hyprctl dispatch workspace 3` fails with the Lua config. Use `hyprctl dispatch 'hl.dsp.focus({ workspace = "3" })'`.

## Configuration

### `~/.config/hypr/bindings.lua`

```lua
-- Periphery exposé: tiling + bar in a centred 5:4 focus area, other workspaces in the side bands
o.bind("SUPER + E", "Periphery exposé", "omarchy-shell shell toggle stef.periphery '{}'")

-- Periphery: when a SUPER-drag ends over a side band, send the dragged window
-- (Hyprland focuses the window it drags) to the workspace group under the cursor.
-- The plugin ignores drops outside the bands, or when the mode is off.
hl.bind("SUPER + mouse:272", function()
  local win = hl.get_active_window()
  local pos = hl.get_cursor_pos()
  if not win or not pos then return end
  hl.exec_cmd(string.format("omarchy-shell -q stef.periphery dropWindow %s %d %d", win.address, math.floor(pos.x), math.floor(pos.y)))
end, { release = true, non_consuming = true })
```

The release bind is `non_consuming`. The Omarchy drag bind on the same keys still works.

### `~/.config/omarchy/shell.json`

```json
"plugins": [
  { "id": "stef.overview" },
  { "id": "stef.periphery" }
]
```

### Tunables (top of `Periphery.qml`)

Durations are given at `animSpeed: 1`.

| Property | Default | Effect |
|----------|---------|--------|
| `ratio` | `1.25` | Focus area width / monitor height. |
| `bandMargin` | `Style.space(16)` | Space between band edge and cards. |
| `cardGap` | `Style.space(10)` | Minimum space between cards. |
| `groupGap` | `Style.space(20)` | Space between groups. |
| `maxStretch` | `6` | Maximum vertical stretch of a group's position map. |
| `animSpeed` | `1` | Global animation speed. `0.25` plays all animations 4× slower (to inspect them), `2` twice as fast. Scales every duration, the switch timeouts and the springs. |
| `slideDuration` | `320` | Card fade-in time in ms. |
| `fadeDuration` | `150` | Ghost, drop outline and drag grow time in ms. |
| `springStrength` | `11.2` | Qt `SpringAnimation.spring` for cards and ghosts. Matches the theme spring `spatial_default` (stiffness 700 × 16 ms step). |
| `springDamping` | `0.65` | Qt `SpringAnimation.damping`. With `11.2`: ~340 ms, no overshoot. Lower is bouncier. Below `animSpeed` 1 it gets up to 22% extra: Qt steps springs in fixed 16 ms ticks that damp the overshoot at normal speed, and slow motion would otherwise overshoot ~2%. |
| `ghostBlur` | `96` | Blur radius in px of the wallpaper behind ghosts. Matched by eye to `decoration:blur` size 6, 3 passes (dual-kawase has no exact radius); past 64 px it uses `blurMultiplier`. `ghostBlurContrast` (`-0.11`) and `ghostBlurSaturation` (`0.17`) match its contrast 0.89 and vibrancy 0.17. |
| `coverBleed` | `2` | How far the switch backdrop reaches into the bands, to cover a flush window's border. At least `general:border_size`. |
| `switchMinMs` / `switchMaxMs` | `120` / `1500` | Shortest and longest switch flight before the hand-off. |

Colours and fonts come from the theme `[menu]` tokens (`Color.menu.*`, `Style.*`) and follow theme changes.

## Constraints and gotchas

- **Plugin reload turns the mode off.** A save of any plugin file reloads the plugin. Press `SUPER + E` again. The hot reload is not reliable: after an edit, run `omarchy restart shell`.
- **Hidden workspaces keep their old tiling.** Hyprland re-tiles only the visible workspace when the reserved area changes. A workspace that was tiled at full width keeps that layout until you visit it. Its cards still show the correct relative positions.
- **Frame rate costs GPU.** Every card captures at the screen frame rate. Many windows in the periphery increase GPU load.
- **Floating windows keep their position.** A floating window that you drop in the focus area stays floating at its last position. It does not move to the drop point.
- **Dropped real window: active window.** The release bind uses `hl.get_active_window()`. This is correct because Hyprland focuses the window it drags. A release with SUPER held and no drag also calls the plugin. The plugin ignores it if the pointer is in the focus area. Over a band, the focused window moves (a SUPER-click on empty band space).
- **One monitor.** The mode uses the monitor that has focus when it turns on. It does not follow a monitor focus change: the bands keep showing the workspaces around that monitor's active workspace. Multi-monitor is not tested.
- **Fullscreen** windows cover the full monitor, bands included.
- **Narrow bands.** On a 16:9 monitor the bands are narrow (380 px at 5:4). The solver stacks cards vertically. A wider monitor or a smaller ratio gives larger cards.
- **Hyprland fade while on.** `hyprctl reload` while the mode is on turns the slide back on under the ghosts. Toggle the mode off and on.
- **Switch starts a frame late.** Hyprland shows the new workspace before the plugin gets the event (~8 ms) and draws its first frame. The slow-start fade hides that frame; see [Workspace switch animation](#workspace-switch-animation).
- **ScreencopyView does not blend.** A `ScreencopyView` overwrites what is under it with the window's own pixels and alpha. Over the backdrop, a translucent window (foot) made the Overlay surface translucent, and the real window behind showed through as a faint second copy; inside a ghost it wiped the blur patch. The `ScreencopyView` itself has `layer.enabled: true`: it renders alone into a texture that is drawn with normal blending. A layer on a parent item does not help, as the overwrite then happens inside that layer.
- **Hand-off border and shadow.** Ghosts have no Hyprland border or shadow. Both show when the ghosts hand off.
- **No drop outline for real-window drags.** See [Drag of a real window into a band](#drag-of-a-real-window-into-a-band).

## Verification

```bash
omarchy restart shell
omarchy-shell shell toggle stef.periphery '{}'

hyprctl monitors -j | jq '.[].reserved'          # [380, 26, 380, 0]
hyprctl layers -j | jq '.["DP-3"].levels."2"'    # omarchy-bar: x 380, w 1800

omarchy-shell shell toggle stef.periphery '{}'
hyprctl monitors -j | jq '.[].reserved'          # [0, 26, 0, 0]
```

Manual checks:

1. Go to each workspace. Check the band of each group and the wrap rule.
2. Click a card. The window gets focus and the previous workspace enters the periphery.
3. Drag a card into the focus area, onto another group and onto empty band space.
4. `SUPER`-drag a real window onto a group in a band.
5. Play a video on another workspace. Its card plays smoothly.
6. Switch workspace. Incoming windows fly from their cards to their tiles, outgoing ones to their new cards. No double image at the hand-off.
7. Switch fast between two workspaces. Ghosts retarget, nothing stays on screen.
8. `hyprctl getprop address:<band window> no_shadow` is `true`, and `false` for focus windows. After the mode turns off, `false` for all (or the window rule's value).
9. `hyprctl animations -j | jq '.[0][] | select(.name=="workspaces")'`: `style: fade`, `speed: 1.5` while on, the theme's slide after the mode turns off.

## Out of scope

- The warped grid background from the Jenson prototype.
- Interaction with the `SUPER + SHIFT + SPACE` overview (`stef.overview`). The two plugins are independent.
- Special workspaces (scratchpad) in the periphery.
- Drop position for floating windows.
