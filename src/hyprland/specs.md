# Hyprland strings (`src/hyprland`)

What the plugin reads from and writes to Hyprland as text: the workspace animation, the selection state for the hook, and the decoration options. Pure: strings and numbers in, strings and numbers out. Behaviour as in [SPEC.md](../../SPEC.md#hyprlands-workspace-animation).

## Workspace animation

Input: the output of `hyprctl animations -j`. That is either a list of animations or a list whose first element is that list (followed by the curves).

The animation call for the leaf `workspaces`, rebuilt as Lua:

- Not found: an empty string.
- Disabled, and no style given: `hl.animation({ leaf = "workspaces", enabled = false })`.
- Otherwise `hl.animation({ leaf = "workspaces", enabled = true, speed = <speed>, <curve>, style = "<style>" })`:
  - the curve is `spring = "<name>"` when Hyprland reports `bezier` as `spring:<name>`, else `bezier = "<name>"`, left out when empty;
  - the style is the given style (to set the mode's style with the theme's curve and speed), else the animation's own, left out when neither exists.
- Input that is not JSON throws.

The off call is also available on its own, for a flight's switch.

## Card travel

How far cards travel with a workspace switch, following Hyprland's style string:

- No `slide` in the style: 0.
- A percentage in the style (`slidefade 10%`): that share of the monitor's extent on the slide's axis.
- Otherwise the whole extent.
- The axis is vertical when the style contains `vert` (height), else horizontal (width).

## Selection state for the hook

The `hyprctl eval` string that hands the plugin's state to `hypr.lua`:

- Mode off: `if periphery_close then periphery_close() end`.
- Mode on: `if periphery_open then periphery_open(<left>, <right>, <x0>, <x1>, <y0>, <y1>); periphery_select(<selected>) end`
  - `left`, `right`: whether each band has cards (`true`/`false`);
  - `x0`, `x1`: the focus area's left and right edge, `y0`, `y1`: the monitor's top and bottom, global pixels, rounded;
  - `selected`: the address in double quotes, or `nil`.
- An address that is not `0x` followed by hex digits counts as no selection: nothing but an address ever reaches Lua code.
- The `if … then` guard keeps the eval harmless when the hook is not loaded.

## Decoration

From the output of `hyprctl -j getoption general:border_size; hyprctl -j getoption decoration:rounding` (two JSON objects, one after the other): the border width and the rounding, each as an integer, or absent when not found.
