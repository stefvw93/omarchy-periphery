# Periphery exposé (`stef.periphery`)

An Omarchy shell plugin for wide monitors. One key squeezes tiling and the bar into a centred focus area. The windows of your other workspaces stay visible as live cards in the side bands. Hover a card or move focus onto it with the arrow keys, and your close and fullscreen keys act on it. Press Enter or click a card to fly to its window. Drag a card to move its window between workspaces.

[SPEC.md](SPEC.md) describes the behaviour and the internals in detail.

## Install

The plugin needs three pieces of configuration. All three are mandatory.

### 1. `~/.config/hypr/hyprland.lua`: the hook

Add these lines right after the bootstrap `dofile`, **before** `require("default.hypr.omarchy")`:

```lua
-- Periphery exposé: wraps the close, fullscreen and focus-direction actions
-- so they reach the periphery's selected card. Must load before Omarchy's
-- bindings below; see ~/.config/omarchy/plugins/stef.periphery/README.md.
local periphery_hook = os.getenv("HOME") .. "/.config/omarchy/plugins/stef.periphery/hypr.lua"
if io.open(periphery_hook) then dofile(periphery_hook) end
```

[`hypr.lua`](hypr.lua) wraps three Hyprland actions: `hl.dsp.window.close()`, `hl.dsp.window.fullscreen()` and `hl.dsp.focus({ direction = … })`. Every key bound to one of these after the hook loads first checks for a selected card. That covers Omarchy's `SUPER + W`, `SUPER + F` and `SUPER + arrows`, and any key you bind to these actions yourself, now or later. When the mode is off, the wrapped actions behave exactly like the native ones.

**Why here, and not in `bindings.lua` or the theme:** Hyprland binds are opaque, so the plugin can't find out which key does what. It can only wrap the actions before the binds are made. `~/.config/hypr/bindings.lua` and the theme's `hyprland.lua` both load _after_ Omarchy's bindings. By then `SUPER + W`, `SUPER + F` and the arrows are already bound to the native actions, and wrapping does nothing for them.

Run `hyprctl reload` once after adding the lines.

### 2. `~/.config/hypr/bindings.lua`: the toggle and the window drop

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

The release bind is `non_consuming`, so Omarchy's window drag on the same keys still works. Pass a payload to change the focus area, e.g. `'{"ratio": 1.333}'` for 4:3.

### 3. `~/.config/omarchy/shell.json`: load the plugin

```json
"plugins": [
  { "id": "stef.periphery" }
]
```

Then run `omarchy restart shell` and press `SUPER + E`.

## Check that it works

```bash
hyprctl eval 'error(type(periphery_select))'   # "function": the hook is loaded
hyprctl monitors -j | jq '.[].reserved'         # [380, 26, 380, 0] with the mode on, on a 2560×1440 monitor
```

Hover a card: it gets your theme's active border, and the active window's border turns inactive. `SUPER + W` now closes the card's window, not the window in the focus area. Enter goes to it.

## Development

The source lives in its own repo, outside the plugin folder: the shell reloads plugins on any write under `~/.config/omarchy/plugins/`. Tooling is [Vite+](https://viteplus.dev) (`vp`): Oxfmt, Oxlint with type checking, Vitest, and tsdown for the bundles.

```bash
git clone https://github.com/stefvw93/omarchy-periphery.git ~/Projects/omarchy-periphery
cd ~/Projects/omarchy-periphery
vp install && vp config   # dependencies, git hooks
vp run verify             # format, lint + types, tests, bundles, QML lint, Lua tests
vp run deploy             # pack and copy plugin/ into ~/.config/omarchy/plugins/stef.periphery
omarchy restart shell
vp run smoke              # live checks against the running session
```

The logic is TypeScript in `src/<module>/` (spec, code, tests), bundled to `plugin/lib/*.mjs` for the QML to import. [CLAUDE.md](CLAUDE.md) has the workflow: spec → `declare` → failing tests → implementation → `vp run verify`.
