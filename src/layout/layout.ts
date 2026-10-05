// Layout: the other workspaces' windows as cards in the bands. See specs.md.

/** A window on another workspace, as the caller reads it from Hyprland. */
export interface LayoutWindow {
  address: string
  title: string
  appClass: string
  floating: boolean
  wsId: number
  wsName: string
  /** Real position and size, global pixels. */
  rx: number
  ry: number
  rw: number
  rh: number
}

export interface Geometry {
  monW: number
  monH: number
  sideW: number
  bandMargin: number
  cardGap: number
  groupGap: number
  headerHeight: number
  maxStretch: number
}

export interface Rect {
  x: number
  y: number
  w: number
  h: number
}

/** A card: the window's own fields, minus its real rect, plus the card rect. */
export type Card<W extends LayoutWindow = LayoutWindow> = Omit<W, "rx" | "ry" | "rw" | "rh"> & Rect

export interface Header extends Rect {
  id: number
  label: string
}

export interface Bands {
  left: number[]
  right: number[]
}

export interface Layout<W extends LayoutWindow = LayoutWindow> extends Bands {
  cards: Record<string, Card<W>>
  headers: Header[]
}

/** Sorts workspace ids into the bands, with the wrap rule. */
export function assignBands(ids: readonly number[], current: number): Bands {
  const sorted = [...ids].sort((a, b) => a - b)
  const left = sorted.filter((id) => id < current)
  const right = sorted.filter((id) => id > current)
  // On the first workspace the last one wraps round to the left, and on the
  // last workspace the first one wraps round to the right.
  if (left.length === 0 && right.length >= 2) left.push(right.pop()!)
  else if (right.length === 0 && left.length >= 2) right.push(left.shift()!)
  return { left, right }
}

/** A group's windows in reading order (a sorted copy). */
export function readingOrder<W extends LayoutWindow>(windows: readonly W[]): W[] {
  return [...windows].sort((a, b) => {
    if (a.floating !== b.floating) return a.floating ? 1 : -1
    if (Math.abs(a.rx - b.rx) > 4) return a.rx - b.rx
    return a.ry - b.ry
  })
}

interface Group<W extends LayoutWindow> {
  id: number
  label: string
  windows: W[]
  box: Rect
  naturalH: number
}

/** The whole layout: bands, cards and headers. */
export function layoutBands<W extends LayoutWindow>(
  windows: readonly W[],
  current: number,
  geometry: Geometry,
): Layout<W> {
  const byWs = new Map<number, { label: string; windows: W[] }>()
  for (const w of windows) {
    const group = byWs.get(w.wsId)
    if (group) group.windows.push(w)
    else byWs.set(w.wsId, { label: w.wsName || String(w.wsId), windows: [w] })
  }
  const { left, right } = assignBands([...byWs.keys()], current)
  const groupsOf = (ids: number[]) =>
    ids.map((id) => {
      const g = byWs.get(id)!
      return { id, label: g.label, windows: readingOrder(g.windows) }
    })

  const cards: Record<string, Card<W>> = {}
  const headers: Header[] = []
  placeSide(groupsOf(left), geometry.bandMargin, geometry, cards, headers)
  placeSide(
    groupsOf(right),
    geometry.monW - geometry.sideW + geometry.bandMargin,
    geometry,
    cards,
    headers,
  )
  return { cards, headers, left, right }
}

// Expose-style placement that keeps windows near their real relative
// positions. Each group gets a slice of the band; window centres are mapped
// from the group's bounding box into that slice (stretched vertically up to
// maxStretch to use the tall band), then cards at a shared scale are nudged
// apart until none overlap. The scale is the largest at which every group of
// this side resolves.
function placeSide<W extends LayoutWindow>(
  input: { id: number; label: string; windows: W[] }[],
  bandX: number,
  geo: Geometry,
  cards: Record<string, Card<W>>,
  headers: Header[],
): void {
  if (input.length === 0) return
  const bandW = geo.sideW - geo.bandMargin * 2
  const availH =
    geo.monH -
    geo.bandMargin * 2 -
    input.length * geo.headerHeight -
    (input.length - 1) * geo.groupGap

  // Group bounding boxes and their height when mapped at band width.
  const groups: Group<W>[] = input.map((g) => {
    let x0 = Infinity
    let y0 = Infinity
    let x1 = -Infinity
    let y1 = -Infinity
    for (const w of g.windows) {
      x0 = Math.min(x0, w.rx)
      y0 = Math.min(y0, w.ry)
      x1 = Math.max(x1, w.rx + w.rw)
      y1 = Math.max(y1, w.ry + w.rh)
    }
    const box = { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) }
    return { ...g, box, naturalH: (bandW * box.h) / box.w }
  })
  const natural = groups.reduce((sum, g) => sum + g.naturalH, 0)
  const stretch = Math.min(geo.maxStretch, availH / natural)
  const bodies = groups.map((g) => g.naturalH * stretch)
  const used =
    bodies.reduce((a, b) => a + b, 0) +
    groups.length * geo.headerHeight +
    (groups.length - 1) * geo.groupGap

  const regions: Rect[] = []
  let y = (geo.monH - used) / 2
  for (const body of bodies) {
    regions.push({ x: bandX, y: y + geo.headerHeight, w: bandW, h: body })
    y += geo.headerHeight + body + geo.groupGap
  }

  let lo = 0.02
  let hi = 1
  groups.forEach((g, k) => {
    for (const w of g.windows) hi = Math.min(hi, bandW / w.rw, bodies[k]! / w.rh)
  })
  let best: Card<W>[][] | null = null
  for (let iter = 0; iter < 16; iter++) {
    const mid = (lo + hi) / 2
    const trial: Card<W>[][] = []
    let ok = true
    for (let t = 0; t < groups.length && ok; t++) {
      const placed = resolve(groups[t]!, regions[t]!, mid, geo.cardGap, false)
      if (placed) trial.push(placed)
      else ok = false
    }
    if (ok) {
      lo = mid
      best = trial
    } else hi = mid
  }
  best ??= groups.map((g, f) => resolve(g, regions[f]!, lo, geo.cardGap, true)!)

  groups.forEach((g, h) => {
    const placed = best[h]!
    // The label sits just above the group's topmost card.
    const minY = Math.min(...placed.map((c) => c.y))
    const maxY = Math.max(...placed.map((c) => c.y + c.h))
    headers.push({
      id: g.id,
      label: g.label,
      x: bandX,
      y: minY - geo.headerHeight,
      w: bandW,
      h: maxY - minY + geo.headerHeight,
    })
    for (const c of placed) cards[c.address] = c
  })
}

// Places one group's cards at `scale` inside `region`, starting from their
// mapped positions and pushing overlapping pairs apart along the shallower
// axis (or the other one when both cards sit against that axis's walls).
// Returns the cards, or null when they can't be separated.
function resolve<W extends LayoutWindow>(
  group: Group<W>,
  region: Rect,
  scale: number,
  gap: number,
  force: boolean,
): Card<W>[] | null {
  const box = group.box
  const placed = group.windows.map((w) => {
    const cw = w.rw * scale
    const ch = w.rh * scale
    return {
      window: w,
      w: cw,
      h: ch,
      cx: region.x + ((w.rx + w.rw / 2 - box.x) / box.w) * region.w,
      cy: region.y + ((w.ry + w.rh / 2 - box.y) / box.h) * region.h,
    }
  })
  type Placed = (typeof placed)[number]
  const clamp = (c: Placed) => {
    c.cx = Math.max(region.x + c.w / 2, Math.min(region.x + region.w - c.w / 2, c.cx))
    c.cy = Math.max(region.y + c.h / 2, Math.min(region.y + region.h - c.h / 2, c.cy))
  }
  placed.forEach(clamp)

  let clear = false
  for (let pass = 0; pass < 120 && !clear; pass++) {
    clear = true
    for (let i = 0; i < placed.length; i++) {
      for (let j = i + 1; j < placed.length; j++) {
        const a = placed[i]!
        const b = placed[j]!
        const dx = b.cx - a.cx
        const dy = b.cy - a.cy
        const ox = (a.w + b.w) / 2 + gap - Math.abs(dx)
        const oy = (a.h + b.h) / 2 + gap - Math.abs(dy)
        if (ox <= 0.5 || oy <= 0.5) continue
        clear = false
        // Ties keep reading order: the earlier window goes left/up.
        const sx = dx >= 0 ? 1 : -1
        const sy = dy >= 0 ? 1 : -1
        const xRoom =
          sx > 0
            ? a.cx - a.w / 2 - region.x + (region.x + region.w - b.cx - b.w / 2)
            : region.x + region.w - a.cx - a.w / 2 + (b.cx - b.w / 2 - region.x)
        const yRoom =
          sy > 0
            ? a.cy - a.h / 2 - region.y + (region.y + region.h - b.cy - b.h / 2)
            : region.y + region.h - a.cy - a.h / 2 + (b.cy - b.h / 2 - region.y)
        // Prefer the shallower axis if there's room to separate along it,
        // else whichever axis has room, else the one with more of it.
        const canX = xRoom >= ox - 0.5
        const canY = yRoom >= oy - 0.5
        const useX = canX && canY ? ox <= oy : canX || canY ? canX : xRoom / ox >= yRoom / oy
        if (useX) {
          a.cx -= (sx * ox) / 2
          b.cx += (sx * ox) / 2
        } else {
          a.cy -= (sy * oy) / 2
          b.cy += (sy * oy) / 2
        }
        clamp(a)
        clamp(b)
      }
    }
  }
  if (!clear && !force) return null
  return placed.map((c) => {
    const { rx: _rx, ry: _ry, rw: _rw, rh: _rh, ...rest } = c.window
    return { ...rest, x: c.cx - c.w / 2, y: c.cy - c.h / 2, w: c.w, h: c.h } as Card<W>
  })
}
