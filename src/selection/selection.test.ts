import { describe, expect, it } from "vite-plus/test"
import { enterBand, freeWorkspaceId, groupAt, stepSelection } from "./selection.ts"

// DP-3: 2560×1440, bands 380 wide; the focus area runs from 380 to 2180.
const monW = 2560
const monH = 1440
const sideW = 380

const cards = {
  L1: { x: 16, y: 100, w: 300, h: 200 }, // centre (166, 200)
  L2: { x: 40, y: 500, w: 300, h: 200 }, // centre (190, 600)
  L3: { x: 16, y: 900, w: 150, h: 100 }, // centre (91, 950)
  L4: { x: 200, y: 900, w: 150, h: 100 }, // centre (275, 950)
  R1: { x: 2196, y: 300, w: 340, h: 200 }, // centre (2366, 400)
  R2: { x: 2196, y: 800, w: 340, h: 200 }, // centre (2366, 900)
}

// Three tiles: two stacked on the left, one tall one on the right.
const tiles = {
  A: { x: 380, y: 31, w: 892, h: 700 },
  B: { x: 380, y: 740, w: 892, h: 690 },
  C: { x: 1283, y: 31, w: 897, h: 1404 },
}

describe("enterBand", () => {
  const tile = { x: 380, y: 450, w: 892, h: 300 } // centre height 600

  it("selects the card nearest the active tile's height in the left band", () => {
    expect(enterBand(cards, "l", tile, monW, monH)).toBe("L2")
  })

  it("selects the card nearest the active tile's height in the right band", () => {
    expect(enterBand(cards, "r", tile, monW, monH)).toBe("R1")
  })

  it("uses the monitor's middle height without an active tile", () => {
    expect(enterBand(cards, "l", null, monW, monH)).toBe("L2")
    expect(enterBand(cards, "r", null, monW, monH)).toBe("R2")
  })

  it("selects nothing in a band without cards", () => {
    expect(enterBand({ L1: cards.L1 }, "r", tile, monW, monH)).toBeNull()
  })
})

describe("stepSelection", () => {
  const step = (
    selected: string,
    dir: "l" | "r" | "u" | "d",
    t: Record<string, typeof tiles.A> = tiles,
  ) => stepSelection(cards, selected, dir, t, monW, sideW)

  it("moves to the next card that way, scoring along + 2 × across", () => {
    expect(step("L1", "d")).toEqual({ kind: "select", address: "L2" })
    expect(step("L2", "d")).toEqual({ kind: "select", address: "L4" })
    expect(step("L3", "r")).toEqual({ kind: "select", address: "L4" })
    expect(step("L2", "u")).toEqual({ kind: "select", address: "L1" })
    expect(step("R1", "d")).toEqual({ kind: "select", address: "R2" })
  })

  // L2's centre is 24 px right of L1's, but 400 px lower: not beside it.
  it("moves left or right only to a card beside the selected one", () => {
    expect(step("L1", "r")).toEqual({ kind: "focus", address: "A" })
    expect(step("L1", "l")).toEqual({ kind: "stay" })
    expect(step("L4", "l")).toEqual({ kind: "select", address: "L3" })
  })

  it("counts a partial vertical overlap as beside", () => {
    const shifted = { ...cards, L5: { x: 200, y: 250, w: 150, h: 100 } } // y 250–350 overlaps L1's 100–300
    expect(stepSelection(shifted, "L1", "r", tiles, monW, sideW)).toEqual({
      kind: "select",
      address: "L5",
    })
  })

  it("stays within the band", () => {
    expect(step("L4", "r")).not.toEqual({ kind: "select", address: "R2" })
  })

  it("goes back to the focus area window on that edge, nearest the card's height", () => {
    expect(step("L4", "r")).toEqual({ kind: "focus", address: "B" })
    expect(step("R1", "l")).toEqual({ kind: "focus", address: "C" })
    expect(stepSelection({ L1: cards.L1 }, "L1", "r", tiles, monW, sideW)).toEqual({
      kind: "focus",
      address: "A",
    })
  })

  it("clears the selection with nothing to focus", () => {
    expect(step("L4", "r", {})).toEqual({ kind: "focus", address: null })
  })

  it("stays when nothing lies that way and it points away from the focus area", () => {
    expect(step("L3", "l")).toEqual({ kind: "stay" })
    expect(step("L1", "u")).toEqual({ kind: "stay" })
    expect(step("R2", "r")).toEqual({ kind: "stay" })
    expect(step("R2", "d")).toEqual({ kind: "stay" })
  })

  it("clears a selection that is not a card", () => {
    expect(step("gone", "d")).toEqual({ kind: "clear" })
  })
})

describe("groupAt", () => {
  const groups = [
    { id: 2, x: 16, y: 100, w: 348, h: 300 },
    { id: 3, x: 16, y: 450, w: 348, h: 300 },
  ]

  it("finds the group whose drop area holds the point, margins included", () => {
    expect(groupAt(groups, 200, 200, 16, 20)?.id).toBe(2)
    expect(groupAt(groups, 0, 90, 16, 20)?.id).toBe(2)
    expect(groupAt(groups, 100, 445, 16, 20)?.id).toBe(3)
  })

  it("finds nothing between groups or outside them", () => {
    expect(groupAt(groups, 100, 425, 16, 20)).toBeNull()
    expect(groupAt(groups, 381, 200, 16, 20)).toBeNull()
  })
})

describe("freeWorkspaceId", () => {
  it("returns the lowest id that is neither occupied nor current", () => {
    expect(freeWorkspaceId([1, 2, 4], 3)).toBe(5)
    expect(freeWorkspaceId([2], 3)).toBe(1)
    expect(freeWorkspaceId([], 1)).toBe(2)
  })

  it("returns 100 when 1 to 99 are taken", () => {
    const all = Array.from({ length: 99 }, (_, i) => i + 1)
    expect(freeWorkspaceId(all, 1)).toBe(100)
  })
})
