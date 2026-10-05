-- Tests for plugin/hypr.lua against a fake `hl`. Plain Lua, no framework:
-- `lua tests/hypr.test.lua` from the repo root. The behaviour is specified in
-- SPEC.md, "Periphery selection".

local failures, count = 0, 0

local function test(name, fn)
  count = count + 1
  local ok, err = pcall(fn)
  if ok then
    print("ok    " .. name)
  else
    failures = failures + 1
    print("FAIL  " .. name .. "\n      " .. tostring(err))
  end
end

local function eq(actual, expected, what)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", what or "value", tostring(expected), tostring(actual)), 2)
  end
end

-- A fake `hl`: dispatcher constructors return plain tables, and everything
-- the hook does is recorded in `log`.
local function fake()
  local log = { dispatched = {}, exec = {}, binds = {}, timers = {} }
  local state = {
    active = { address = "0xA", at = { x = 380, y = 26 }, size = { x = 900, y = 1400 }, mapped = true },
    windows = {},
    cursor = { x = 1000, y = 500 },
  }
  local function ctor(kind)
    return function(args) return { kind = kind, args = args } end
  end
  local hl = {
    dsp = {
      window = {
        close = ctor("close"),
        fullscreen = ctor("fullscreen"),
        set_prop = ctor("set_prop"),
      },
      focus = ctor("focus"),
    },
  }
  function hl.dispatch(d)
    if type(d) == "function" then return d() end
    table.insert(log.dispatched, d)
  end
  function hl.exec_cmd(cmd) table.insert(log.exec, cmd) end
  function hl.bind(key, fn, opts)
    local bind = { key = key, fn = fn, opts = opts, removed = false }
    function bind:remove() self.removed = true end
    table.insert(log.binds, bind)
    return bind
  end
  function hl.timer(fn, opts) table.insert(log.timers, { fn = fn, opts = opts }) end
  function hl.get_active_window()
    if not state.active then return nil end
    local w = state.active
    w.workspace = {
      get_windows = function() return state.windows end,
    }
    return w
  end
  function hl.get_cursor_pos() return state.cursor end
  function hl.get_config(key)
    if key == "general.col.active_border" then return { colors = { "0xFFB8CACA", "0xFF919190" }, angle = 54.99 } end
    if key == "general.col.inactive_border" then return { colors = { "0xFF464747" }, angle = 0 } end
  end

  _G.hl = hl
  _G.periphery = nil
  dofile("plugin/hypr.lua")
  return log, state
end

local function last(list) return list[#list] end

local function live_binds(log)
  local keys = {}
  for _, b in ipairs(log.binds) do
    if not b.removed then table.insert(keys, b.key) end
  end
  table.sort(keys)
  return table.concat(keys, ",")
end

local function selected_on(log, address)
  periphery_open(true, true, 380, 2180, 0, 1440)
  periphery_select(address)
end

-- Close ---------------------------------------------------------------------

test("close without the mode is the native close", function()
  local log = fake()
  hl.dispatch(hl.dsp.window.close())
  eq(last(log.dispatched).kind, "close")
  eq(last(log.dispatched).args, nil, "args")
end)

test("close with the mode on but nothing selected is the native close", function()
  local log = fake()
  periphery_open(true, true, 380, 2180, 0, 1440)
  hl.dispatch(hl.dsp.window.close())
  eq(last(log.dispatched).kind, "close")
  eq(last(log.dispatched).args, nil, "args")
end)

test("close on a selected card closes the card's window", function()
  local log = fake()
  selected_on(log, "0xC")
  hl.dispatch(hl.dsp.window.close())
  eq(last(log.dispatched).kind, "close")
  eq(last(log.dispatched).args.window, "address:0xC", "window")
end)

test("close that names its window keeps the native action", function()
  local log = fake()
  selected_on(log, "0xC")
  local d = hl.dsp.window.close({ window = "address:0xB" })
  eq(type(d), "table", "dispatcher type")
  hl.dispatch(d)
  eq(last(log.dispatched).args.window, "address:0xB", "window")
end)

-- Fullscreen ----------------------------------------------------------------

test("fullscreen on a selected card goes there and fullscreens it, same mode", function()
  local log = fake()
  selected_on(log, "0xC")
  hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized" }))
  local n = #log.dispatched
  eq(log.dispatched[n - 1].kind, "focus")
  eq(log.dispatched[n - 1].args.window, "address:0xC", "focus window")
  eq(log.dispatched[n].kind, "fullscreen")
  eq(log.dispatched[n].args.window, "address:0xC", "fullscreen window")
  eq(log.dispatched[n].args.mode, "maximized", "mode")
  eq(periphery.selected, nil, "selection cleared")
end)

test("fullscreen without a selection is the native fullscreen", function()
  local log = fake()
  periphery_open(true, true, 380, 2180, 0, 1440)
  hl.dispatch(hl.dsp.window.fullscreen({ mode = "fullscreen" }))
  eq(last(log.dispatched).kind, "fullscreen")
  eq(last(log.dispatched).args.window, nil, "window")
end)

-- Focus keys ----------------------------------------------------------------

test("focus by workspace or window stays native", function()
  fake()
  eq(type(hl.dsp.focus({ workspace = "3" })), "table", "workspace")
  eq(type(hl.dsp.focus({ window = "address:0x1" })), "table", "window")
end)

test("a focus key without the mode is the native focus", function()
  local log = fake()
  hl.dispatch(hl.dsp.focus({ direction = "l" }))
  eq(last(log.dispatched).kind, "focus")
  eq(#log.exec, 0, "no plugin call")
end)

test("a focus key on a selected card steps the selection", function()
  local log = fake()
  selected_on(log, "0xC")
  hl.dispatch(hl.dsp.focus({ direction = "d" }))
  eq(last(log.exec), "omarchy-shell -q stef.periphery step d")
end)

test("a focus key past the edge enters the band, with the active window", function()
  local log, state = fake()
  state.windows = { state.active, { address = "0xB", at = { x = 1290, y = 26 }, size = { x = 890, y = 1400 }, mapped = true } }
  periphery_open(true, true, 380, 2180, 0, 1440)
  hl.dispatch(hl.dsp.focus({ direction = "l" }))
  eq(last(log.exec), "omarchy-shell -q stef.periphery enter l 0xA")
end)

test("a focus key with a window beyond it moves focus natively", function()
  local log, state = fake()
  state.windows = { state.active, { address = "0xB", at = { x = 1290, y = 26 }, size = { x = 890, y = 1400 }, mapped = true } }
  periphery_open(true, true, 380, 2180, 0, 1440)
  hl.dispatch(hl.dsp.focus({ direction = "r" }))
  eq(last(log.dispatched).kind, "focus")
  eq(#log.exec, 0, "no plugin call")
end)

test("floating windows don't block the edge", function()
  local log, state = fake()
  state.windows = { state.active, { address = "0xF", at = { x = 100, y = 100 }, size = { x = 200, y = 200 }, mapped = true, floating = true } }
  periphery_open(true, true, 380, 2180, 0, 1440)
  hl.dispatch(hl.dsp.focus({ direction = "l" }))
  eq(last(log.exec), "omarchy-shell -q stef.periphery enter l 0xA")
end)

test("a band without cards keeps the native focus at the edge", function()
  local log = fake()
  periphery_open(false, true, 380, 2180, 0, 1440)
  hl.dispatch(hl.dsp.focus({ direction = "l" }))
  eq(last(log.dispatched).kind, "focus")
  eq(#log.exec, 0, "no plugin call")
end)

test("up and down never enter a band", function()
  local log = fake()
  periphery_open(true, true, 380, 2180, 0, 1440)
  hl.dispatch(hl.dsp.focus({ direction = "u" }))
  eq(last(log.dispatched).kind, "focus")
  eq(#log.exec, 0, "no plugin call")
end)

-- Border --------------------------------------------------------------------

test("a selection greys the active window's border, and clearing puts the theme's back", function()
  local log = fake()
  selected_on(log, "0xC")
  local grey = last(log.dispatched)
  eq(grey.kind, "set_prop")
  eq(grey.args.window, "address:0xA", "window")
  eq(grey.args.prop, "active_border_color", "prop")
  eq(grey.args.value, "0x00000000 0xFF464747 0deg", "inactive value, dummy first colour")
  periphery_select(nil)
  eq(last(log.dispatched).args.value, "0x00000000 0xFFB8CACA 0xFF919190 55deg", "active value restored")
end)

test("moving the selection keeps the border grey without rewriting it", function()
  local log = fake()
  selected_on(log, "0xC")
  local n = #log.dispatched
  periphery_select("0xD")
  eq(#log.dispatched, n, "no new dispatch")
end)

-- Return and Escape ---------------------------------------------------------

test("Return, keypad Enter and Escape are bound only while a card is selected", function()
  local log = fake()
  periphery_open(true, true, 380, 2180, 0, 1440)
  eq(live_binds(log), "", "before")
  periphery_select("0xC")
  eq(live_binds(log), "Escape,KP_Enter,Return", "selected")
  periphery_select("0xD")
  eq(#log.binds, 3, "not bound twice")
  periphery_select(nil)
  eq(live_binds(log), "", "after")
end)

test("Return activates the card, Escape lets go of it", function()
  local log = fake()
  selected_on(log, "0xC")
  for _, b in ipairs(log.binds) do
    if b.key == "Return" then b.fn() end
  end
  eq(last(log.exec), "omarchy-shell -q stef.periphery activate")
  for _, b in ipairs(log.binds) do
    if b.key == "Escape" then b.fn() end
  end
  eq(last(log.exec), "omarchy-shell -q stef.periphery clear")
  eq(periphery.selected, nil, "selection cleared")
end)

-- Pointer watch -------------------------------------------------------------

test("the pointer moving over the focus area clears the selection", function()
  local log, state = fake()
  state.cursor = { x = 200, y = 500 } -- in the left band
  selected_on(log, "0xC")
  local tick = log.timers[1].fn
  tick()
  eq(periphery.selected, "0xC", "still selected without motion")
  state.cursor = { x = 250, y = 700 } -- moved, still in the band
  tick()
  eq(periphery.selected, "0xC", "still selected in the band")
  state.cursor = { x = 1000, y = 700 } -- over the focus area
  tick()
  eq(periphery.selected, nil, "cleared")
  eq(last(log.exec), "omarchy-shell -q stef.periphery clear")
end)

test("a pointer resting over the focus area doesn't clear a keyboard selection", function()
  local log, state = fake()
  state.cursor = { x = 1000, y = 500 }
  selected_on(log, "0xC")
  state.cursor = { x = 1002, y = 501 } -- under 4 px
  log.timers[1].fn()
  eq(periphery.selected, "0xC", "still selected")
end)

-- Mode off ------------------------------------------------------------------

test("closing clears the selection, the binds and the state", function()
  local log = fake()
  selected_on(log, "0xC")
  periphery_close()
  eq(periphery, nil, "state")
  eq(live_binds(log), "", "binds")
  eq(last(log.dispatched).args.prop, "active_border_color", "border restored")
end)

print(string.format("\n%d tests, %d failed", count, failures))
os.exit(failures == 0 and 0 or 1)
