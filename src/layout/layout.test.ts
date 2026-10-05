import { describe, expect, it } from "vite-plus/test"
import { assignBands, layoutBands, readingOrder } from "./layout.ts"
import type { Card, Geometry, LayoutWindow } from "./layout.ts"

// DP-3: 2560×1440, ratio 1.25 → focus area 1800, bands 380.
const geometry: Geometry = {
  monW: 2560,
  monH: 1440,
  sideW: 380,
  bandMargin: 16,
  cardGap: 10,
  groupGap: 20,
  headerHeight: 30,
  maxStretch: 6,
}
const bandW = geometry.sideW - 2 * geometry.bandMargin
const leftX = geometry.bandMargin
const rightX = geometry.monW - geometry.sideW + geometry.bandMargin

let next = 0
function win(
  wsId: number,
  rx: number,
  ry: number,
  rw: number,
  rh: number,
  extra: Partial<LayoutWindow> = {},
) {
  next += 1
  return {
    address: `0x${next}`,
    title: `window ${next}`,
    appClass: "foot",
    floating: false,
    wsId,
    wsName: String(wsId),
    rx,
    ry,
    rw,
    rh,
    ...extra,
  }
}

// Two windows tiled side by side on a full-width workspace (smart gaps off).
function tiledPair(wsId: number) {
  return [win(wsId, 385, 31, 892, 1404), win(wsId, 1283, 31, 892, 1404)]
}

function band(cards: Card[], x: number) {
  return cards.filter((c) => c.x >= x && c.x < x + bandW)
}

function separated(a: Card, b: Card, gap: number) {
  const dx = Math.abs(a.x + a.w / 2 - (b.x + b.w / 2)) - (a.w + b.w) / 2
  const dy = Math.abs(a.y + a.h / 2 - (b.y + b.h / 2)) - (a.h + b.h) / 2
  return dx >= gap - 0.5 || dy >= gap - 0.5
}

describe("assignBands", () => {
  it.each([
    { current: 1, ids: [2, 3, 4], left: [4], right: [2, 3] },
    { current: 2, ids: [1, 3, 4], left: [1], right: [3, 4] },
    { current: 4, ids: [1, 2, 3], left: [2, 3], right: [1] },
    { current: 1, ids: [2], left: [], right: [2] },
    { current: 3, ids: [1, 2], left: [2], right: [1] },
    { current: 3, ids: [1], left: [1], right: [] },
  ])(
    "current $current, occupied $ids → left $left, right $right",
    ({ current, ids, left, right }) => {
      expect(assignBands(ids, current)).toEqual({ left, right })
    },
  )

  it("orders each band by id whatever the input order", () => {
    expect(assignBands([5, 2, 4], 3)).toEqual({ left: [2], right: [4, 5] })
  })
})

describe("readingOrder", () => {
  it("puts tiled windows left to right, then top to bottom, floating last", () => {
    const right = win(1, 900, 0, 100, 100)
    const lower = win(1, 0, 500, 100, 100)
    const upper = win(1, 3, 0, 100, 100)
    const floating = win(1, 0, 0, 100, 100, { floating: true })
    expect(readingOrder([floating, right, lower, upper])).toEqual([upper, lower, right, floating])
  })

  it("returns a copy", () => {
    const windows = [win(1, 500, 0, 10, 10), win(1, 0, 0, 10, 10)]
    const first = windows[0]
    readingOrder(windows)
    expect(windows[0]).toBe(first)
  })
})

describe("layoutBands", () => {
  it("puts lower workspaces left, higher right, with the wrap rule", () => {
    const layout = layoutBands([...tiledPair(1), ...tiledPair(3), ...tiledPair(4)], 2, geometry)
    expect(layout.left).toEqual([1])
    expect(layout.right).toEqual([3, 4])
    const wrapped = layoutBands([...tiledPair(2), ...tiledPair(3)], 1, geometry)
    expect(wrapped.left).toEqual([3])
    expect(wrapped.right).toEqual([2])
  })

  it("keeps every card inside its band", () => {
    const layout = layoutBands([...tiledPair(1), ...tiledPair(3), ...tiledPair(4)], 2, geometry)
    for (const card of Object.values(layout.cards)) {
      const x = card.wsId === 1 ? leftX : rightX
      expect(card.x).toBeGreaterThanOrEqual(x - 0.01)
      expect(card.x + card.w).toBeLessThanOrEqual(x + bandW + 0.01)
      expect(card.y).toBeGreaterThanOrEqual(geometry.bandMargin - 0.01)
      expect(card.y + card.h).toBeLessThanOrEqual(geometry.monH - geometry.bandMargin + 0.01)
    }
  })

  // A group on workspace 1 keeps the left band occupied, so the wrap rule
  // leaves workspaces 3 and up in the right band.
  it("keeps each window's aspect ratio, with one scale per band", () => {
    const windows = [
      ...tiledPair(3),
      win(4, 385, 31, 1790, 1404),
      win(4, 400, 200, 600, 400, { floating: true }),
    ]
    const layout = layoutBands([...tiledPair(1), ...windows], 2, geometry)
    const scales = windows.map((w) => {
      const card = layout.cards[w.address]!
      expect(card.w / card.h).toBeCloseTo(w.rw / w.rh, 6)
      return card.w / w.rw
    })
    for (const scale of scales) expect(scale).toBeCloseTo(scales[0]!, 6)
  })

  it("leaves no two cards in a band closer than the card gap", () => {
    const layout = layoutBands(
      [...tiledPair(1), ...tiledPair(3), ...tiledPair(4), win(5, 385, 31, 1790, 1404)],
      2,
      geometry,
    )
    const cards = band(Object.values(layout.cards), rightX)
    expect(cards).toHaveLength(5)
    for (let i = 0; i < cards.length; i++)
      for (let j = i + 1; j < cards.length; j++)
        expect(separated(cards[i]!, cards[j]!, geometry.cardGap)).toBe(true)
  })

  it("stacks two side-by-side windows, offset to show which was left", () => {
    const [left, right] = tiledPair(3)
    const layout = layoutBands([left!, right!], 2, geometry)
    const a = layout.cards[left!.address]!
    const b = layout.cards[right!.address]!
    expect(b.y).toBeGreaterThanOrEqual(a.y + a.h + geometry.cardGap - 0.5)
    expect(a.x).toBeLessThan(b.x)
  })

  it("scales a lone window up to the band width", () => {
    const only = win(3, 385, 31, 1600, 900)
    const card = layoutBands([only], 2, geometry).cards[only.address]!
    expect(card.w).toBeCloseTo(bandW, 1)
  })

  it("puts each header just above its group's top card, groups top to bottom by id", () => {
    const layout = layoutBands([...tiledPair(1), ...tiledPair(3), ...tiledPair(4)], 2, geometry)
    const right = layout.headers.filter((h) => h.x === rightX)
    expect(right.map((h) => h.id)).toEqual([3, 4])
    const [three, four] = right
    expect(three!.y + three!.h).toBeLessThanOrEqual(four!.y)
    for (const header of right) {
      const cards = Object.values(layout.cards).filter((c) => c.wsId === header.id)
      const top = Math.min(...cards.map((c) => c.y))
      const bottom = Math.max(...cards.map((c) => c.y + c.h))
      expect(header).toMatchObject({ label: String(header.id), x: rightX, w: bandW })
      expect(header.y).toBeCloseTo(top - geometry.headerHeight, 6)
      expect(header.y + header.h).toBeCloseTo(bottom, 6)
    }
  })

  it("lists the left band's headers first", () => {
    const layout = layoutBands([...tiledPair(1), ...tiledPair(3)], 2, geometry)
    expect(layout.headers.map((h) => h.id)).toEqual([1, 3])
    expect(layout.headers[0]!.x).toBe(leftX)
  })

  it("passes the caller's own fields through to the card", () => {
    const toplevel = { marker: true }
    const w = { ...win(3, 385, 31, 892, 1404), toplevel }
    const card = layoutBands([w], 2, geometry).cards[w.address]!
    expect(card).toMatchObject({
      address: w.address,
      title: w.title,
      appClass: "foot",
      wsId: 3,
      toplevel,
    })
  })

  it("returns nothing for no windows", () => {
    expect(layoutBands([], 1, geometry)).toEqual({ cards: {}, headers: [], left: [], right: [] })
  })
})
