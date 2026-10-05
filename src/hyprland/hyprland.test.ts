import { describe, expect, it } from "vite-plus/test"
import {
  cardTravel,
  hookStateLua,
  parseDecoration,
  workspaceAnimationLua,
  workspacesOffLua,
} from "./hyprland.ts"

// Shapes as `hyprctl animations -j` prints them (Hyprland 0.56).
const workspaces = (fields: Record<string, unknown>) => ({
  name: "workspaces",
  overridden: true,
  bezier: "spring:omaterial_spatial_default",
  enabled: true,
  speed: 3,
  style: "slide",
  ...fields,
})
const nested = (...animations: object[]) =>
  JSON.stringify([
    [
      { name: "global", overridden: true, bezier: "default", enabled: true, speed: 10, style: "" },
      ...animations,
    ],
    [{ name: "quick", X0: 0.15, Y0: 0, X1: 0.1, Y1: 1 }],
  ])

describe("workspaceAnimationLua", () => {
  it("rebuilds a spring animation with its own style", () => {
    expect(workspaceAnimationLua(nested(workspaces({})))).toBe(
      'hl.animation({ leaf = "workspaces", enabled = true, speed = 3, spring = "omaterial_spatial_default", style = "slide" })',
    )
  })

  it("rebuilds a bezier animation", () => {
    expect(workspaceAnimationLua(nested(workspaces({ bezier: "easeOutQuint", speed: 6 })))).toBe(
      'hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "easeOutQuint", style = "slide" })',
    )
  })

  it("puts the given style in place of the animation's own", () => {
    expect(workspaceAnimationLua(nested(workspaces({})), "slidefade 10%")).toBe(
      'hl.animation({ leaf = "workspaces", enabled = true, speed = 3, spring = "omaterial_spatial_default", style = "slidefade 10%" })',
    )
  })

  it("leaves out an empty curve and a missing style", () => {
    expect(workspaceAnimationLua(nested(workspaces({ bezier: "", style: "" })))).toBe(
      'hl.animation({ leaf = "workspaces", enabled = true, speed = 3 })',
    )
  })

  it("turns a disabled animation off, unless a style is given", () => {
    expect(workspaceAnimationLua(nested(workspaces({ enabled: false })))).toBe(workspacesOffLua)
    expect(workspaceAnimationLua(nested(workspaces({ enabled: false })), "fade")).toContain(
      'style = "fade"',
    )
  })

  it("reads a flat list too", () => {
    expect(workspaceAnimationLua(JSON.stringify([workspaces({})]))).toContain('leaf = "workspaces"')
  })

  it("returns an empty string without a workspaces animation", () => {
    expect(workspaceAnimationLua(nested())).toBe("")
  })

  it("throws on output that is not JSON", () => {
    expect(() => workspaceAnimationLua("not json")).toThrow()
  })

  it("has the off call", () => {
    expect(workspacesOffLua).toBe('hl.animation({ leaf = "workspaces", enabled = false })')
  })
})

describe("cardTravel", () => {
  it.each([
    { style: "slidefade 10%", distance: 256, vertical: false },
    { style: "slide", distance: 2560, vertical: false },
    { style: "slidevert", distance: 1440, vertical: true },
    { style: "slidefadevert 20%", distance: 288, vertical: true },
    { style: "slidefade 12.5%", distance: 320, vertical: false },
    { style: "fade", distance: 0, vertical: false },
  ])("$style → $distance px", ({ style, distance, vertical }) => {
    expect(cardTravel(style, 2560, 1440)).toEqual({ distance, vertical })
  })
})

describe("hookStateLua", () => {
  const on = {
    opened: true,
    cardsLeft: true,
    cardsRight: false,
    monX: 0,
    monY: 0,
    monW: 2560,
    monH: 1440,
    sideW: 380,
    selected: "",
  }

  it("closes the hook's state when the mode is off", () => {
    expect(hookStateLua({ ...on, opened: false })).toBe(
      "if periphery_close then periphery_close() end",
    )
  })

  it("opens it with the bands and the focus area, nothing selected", () => {
    expect(hookStateLua(on)).toBe(
      "if periphery_open then periphery_open(true, false, 380, 2180, 0, 1440); periphery_select(nil) end",
    )
  })

  it("passes the selected address and the monitor's offset", () => {
    expect(hookStateLua({ ...on, monX: 2560, monY: 100.4, selected: "0x56c7bf423bd0" })).toBe(
      'if periphery_open then periphery_open(true, false, 2940, 4740, 100, 1540); periphery_select("0x56c7bf423bd0") end',
    )
  })

  it("never lets anything but an address into the Lua", () => {
    expect(hookStateLua({ ...on, selected: '0x1") os.execute("rm -rf /' })).toContain(
      "periphery_select(nil)",
    )
    expect(hookStateLua({ ...on, selected: "56c7bf423bd0" })).toContain("periphery_select(nil)")
  })
})

describe("parseDecoration", () => {
  it("reads the border width and rounding", () => {
    const text =
      '{"option": "general:border_size", "int": 1, "set": true }\n{"option": "decoration:rounding", "int": 8, "set": true }\n'
    expect(parseDecoration(text)).toEqual({ borderSize: 1, rounding: 8 })
  })

  it("leaves out what it can't find", () => {
    expect(parseDecoration('{"option": "general:border_size", "int": 2, "set": true }')).toEqual({
      borderSize: 2,
    })
    expect(parseDecoration("")).toEqual({})
  })
})
