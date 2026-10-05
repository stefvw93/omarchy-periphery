-- Periphery exposé, the Hyprland side. Loaded from ~/.config/hypr/hyprland.lua
-- before Omarchy's defaults (see README.md).
--
-- Hyprland binds are opaque (`hyprctl binds` shows only a Lua ref), so the
-- plugin can't look up which key closes a window. Instead this wraps the
-- actions themselves: every bind made after this file runs with
-- hl.dsp.window.close(), hl.dsp.window.fullscreen() or
-- hl.dsp.focus({ direction = ... }), on whatever key, first checks for a
-- selected card in the periphery.
--
-- The plugin drives the state below through hyprctl eval: periphery_open(),
-- periphery_select(address), periphery_close(). A config reload starts a
-- fresh Lua state; the plugin sends its state again on reload.

-- nil while the mode is off; while on: { bands = { l = bool, r = bool },
-- focus = { x0, x1, y0, y1 }, selected = "0x…" | nil, cursor = Vec2 | nil }.
-- bands: which bands have cards to move focus into. focus: the focus area,
-- in global pixels. cursor: where the pointer was when the card got selected.
periphery = nil

local window = hl.dsp.window
local close, fullscreen, focus, set_prop = window.close, window.fullscreen, hl.dsp.focus, window.set_prop

local function shell(args)
  hl.exec_cmd("omarchy-shell -q stef.periphery " .. args)
end

-- A config gradient as a set_prop value. set_prop drops the first colour of
-- a gradient, so a dummy one goes first.
local function gradient(key)
  local g = hl.get_config(key)
  if type(g) ~= "table" then return "0x00000000 " .. tostring(g) end
  return "0x00000000 " .. table.concat(g.colors, " ") .. " " .. math.floor((g.angle or 0) + 0.5) .. "deg"
end

-- While a card is selected, the active window draws its border in the
-- inactive colour: the card has the focus, not the window.
local greyed = nil

local function set_border(address, value)
  pcall(hl.dispatch, set_prop({ window = "address:" .. address, prop = "active_border_color", value = value }))
end

local function sync_border()
  local active = periphery and periphery.selected and hl.get_active_window()
  local want = active and active.address or nil
  if greyed and greyed ~= want then
    set_border(greyed, gradient("general.col.active_border"))
    greyed = nil
  end
  if want and not greyed then
    set_border(want, gradient("general.col.inactive_border"))
    greyed = want
  end
end

-- Return and Escape belong to the card while one is selected, and are bound
-- only then: Return goes to the card's window, Escape lets go of the card.
local card_keys = nil

local function sync_keys()
  local want = periphery ~= nil and periphery.selected ~= nil
  if want and not card_keys then
    local go = function() shell("activate") end
    card_keys = {
      hl.bind("Return", go, { description = "Periphery: go to the selected card" }),
      hl.bind("KP_Enter", go, { description = "Periphery: go to the selected card" }),
      hl.bind("Escape", function()
        periphery_select(nil)
        shell("clear")
      end, { description = "Periphery: let go of the selected card" }),
    }
  elseif not want and card_keys then
    for _, key in ipairs(card_keys) do pcall(function() key:remove() end) end
    card_keys = nil
  end
end

function periphery_open(left, right, x0, x1, y0, y1)
  periphery = periphery or {}
  periphery.bands = { l = left, r = right }
  periphery.focus = { x0 = x0, x1 = x1, y0 = y0, y1 = y1 }
end

function periphery_select(address)
  if not periphery then return end
  if address ~= periphery.selected then
    periphery.selected = address
    periphery.cursor = address and hl.get_cursor_pos() or nil
  end
  sync_border()
  sync_keys()
end

function periphery_close()
  if periphery then periphery_select(nil) end
  periphery = nil
end

local function selected()
  return periphery and periphery.selected
end

local function with_window(args, address)
  local copy = {}
  if type(args) == "table" then for k, v in pairs(args) do copy[k] = v end end
  copy.window = "address:" .. address
  return copy
end

-- A call that names its window keeps the native action.
local function targeted(args)
  return type(args) == "table" and args.window ~= nil
end

window.close = function(args)
  local native = close(args)
  if targeted(args) then return native end
  return function()
    local address = selected()
    if address then hl.dispatch(close({ window = "address:" .. address }))
    else hl.dispatch(native) end
  end
end

-- On a card: go to its window (Hyprland switches to its workspace), then
-- fullscreen it there.
window.fullscreen = function(args)
  local native = fullscreen(args)
  if targeted(args) then return native end
  return function()
    local address = selected()
    if not address then return hl.dispatch(native) end
    periphery_select(nil)
    hl.dispatch(focus({ window = "address:" .. address }))
    hl.dispatch(fullscreen(with_window(args, address)))
  end
end

-- Whether the active window has no tiled window beyond it towards `dir`
-- ("l" or "r") on its workspace. Hyprland's focus wraps round at the edge,
-- so whether focus moved can't tell.
local function at_edge(dir)
  local active = hl.get_active_window()
  if not active or not active.workspace then return true end
  local function left(w) return w.at.x or w.at[1] end
  local function right(w) return left(w) + (w.size.x or w.size[1]) end
  for _, w in ipairs(active.workspace:get_windows()) do
    if w.address ~= active.address and w.mapped and not w.hidden and not w.floating then
      if dir == "l" and left(w) < left(active) - 2 then return false end
      if dir == "r" and right(w) > right(active) + 2 then return false end
    end
  end
  return true
end

-- Focus moves on into the bands: past the left or right edge of the focus
-- area it selects a card, and on a card it moves between cards (the plugin
-- knows the layout).
hl.dsp.focus = function(args)
  local native = focus(args)
  local dir = type(args) == "table" and args.direction
  if not dir then return native end
  dir = string.sub(tostring(dir), 1, 1)
  return function()
    if not periphery then return hl.dispatch(native) end
    if periphery.selected then return shell("step " .. dir) end
    if periphery.bands and periphery.bands[dir] and at_edge(dir) then
      -- The active window goes along: the plugin's view of it can lag.
      local active = hl.get_active_window()
      return shell("enter " .. dir .. " " .. (active and active.address or "none"))
    end
    hl.dispatch(native)
  end
end

-- Pointer motion over the focus area reaches neither the plugin (its surface
-- takes input in the bands only) nor a Hyprland event. While a card is
-- selected, this watches the cursor: once it moves over the focus area, the
-- windows there get the focus back (latest input wins; a pointer resting in
-- the focus area during a keyboard selection doesn't count).
hl.timer(function()
  local from = periphery and periphery.selected and periphery.cursor
  local f = periphery and periphery.focus
  if not from or not f then return end
  local p = hl.get_cursor_pos()
  if not p or math.abs(p.x - from.x) + math.abs(p.y - from.y) < 4 then return end
  if p.x <= f.x0 or p.x >= f.x1 or p.y < f.y0 or p.y >= f.y1 then return end
  periphery_select(nil)
  shell("clear")
end, { timeout = 50, type = "repeat" })
