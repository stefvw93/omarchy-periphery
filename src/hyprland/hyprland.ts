// Hyprland strings: the workspace animation, the hook's state, the
// decoration options. See specs.md.

/** Turns Hyprland's workspace animation off (a flight's switch). */
export const workspacesOffLua = 'hl.animation({ leaf = "workspaces", enabled = false })'

interface Animation {
  name: string
  enabled: boolean
  speed: number
  bezier?: string
  style?: string
}

/** The `workspaces` animation from `hyprctl animations -j` as an `hl.animation` call. */
export function workspaceAnimationLua(animationsJson: string, style?: string): string {
  const lists = JSON.parse(animationsJson) as unknown[]
  const all = (Array.isArray(lists[0]) ? lists[0] : lists) as Animation[]
  const a = all.find((x) => x.name === "workspaces")
  if (!a) return ""
  if (!a.enabled && !style) return workspacesOffLua
  const parts = ['leaf = "workspaces"', "enabled = true", `speed = ${a.speed}`]
  const curve = String(a.bezier ?? "")
  if (curve.startsWith("spring:")) parts.push(`spring = "${curve.slice(7)}"`)
  else if (curve) parts.push(`bezier = "${curve}"`)
  const finalStyle = style || a.style
  if (finalStyle) parts.push(`style = "${finalStyle}"`)
  return `hl.animation({ ${parts.join(", ")} })`
}

export interface CardTravel {
  distance: number
  vertical: boolean
}

/** How far cards travel with a workspace switch in this animation style. */
export function cardTravel(style: string, monW: number, monH: number): CardTravel {
  const vertical = /vert/.test(style)
  if (!/slide/.test(style)) return { distance: 0, vertical }
  const extent = vertical ? monH : monW
  const percent = /(\d+(?:\.\d+)?)%/.exec(style)
  return { distance: percent ? (extent * parseFloat(percent[1]!)) / 100 : extent, vertical }
}

export interface HookState {
  opened: boolean
  cardsLeft: boolean
  cardsRight: boolean
  monX: number
  monY: number
  monW: number
  monH: number
  sideW: number
  selected: string
}

/** The `hyprctl eval` string that hands the plugin's state to hypr.lua. */
export function hookStateLua(state: HookState): string {
  if (!state.opened) return "if periphery_close then periphery_close() end"
  const bounds = [
    state.monX + state.sideW,
    state.monX + state.monW - state.sideW,
    state.monY,
    state.monY + state.monH,
  ].map(Math.round)
  // Nothing but an address ever reaches Lua code.
  const selected = /^0x[0-9a-fA-F]+$/.test(state.selected) ? `"${state.selected}"` : "nil"
  return (
    `if periphery_open then periphery_open(${[state.cardsLeft, state.cardsRight, ...bounds].join(", ")}); ` +
    `periphery_select(${selected}) end`
  )
}

export interface Decoration {
  borderSize?: number
  rounding?: number
}

/** Border width and rounding from two `hyprctl -j getoption` outputs. */
export function parseDecoration(text: string): Decoration {
  const read = (option: string) => {
    const m = new RegExp(`"${option}",\\s*"int":\\s*(\\d+)`).exec(text)
    return m ? parseInt(m[1]!, 10) : undefined
  }
  const result: Decoration = {}
  const borderSize = read("general:border_size")
  const rounding = read("decoration:rounding")
  if (borderSize !== undefined) result.borderSize = borderSize
  if (rounding !== undefined) result.rounding = rounding
  return result
}
