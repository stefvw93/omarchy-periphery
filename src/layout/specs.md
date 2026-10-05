# Layout (`src/layout`)

Places the windows of the other workspaces as cards in the bands. Pure: windows and geometry in, cards and group headers out. Terms as in [SPEC.md](../../SPEC.md#ubiquitous-language).

## Input

- **Windows:** every window on the monitor that is not on the current workspace, with its workspace id and name, title, class, floating state, and its real position and size (`rx`, `ry`, `rw`, `rh`, global pixels). Windows on special workspaces (id ≤ 0) are left out by the caller.
- **Current:** the id of the workspace in the focus area.
- **Geometry:** monitor width and height, `sideW`, `bandMargin`, `cardGap`, `groupGap`, `headerHeight`, `maxStretch`.

## Bands

1. Each occupied workspace is a group.
2. Groups with a lower id than the current workspace go in the left band, groups with a higher id in the right band.
3. Each band orders its groups by id, from top to bottom.
4. Wrap rule: if the left band is empty and the right band has 2 or more groups, the group with the highest id moves to the left band. If the right band is empty and the left band has 2 or more groups, the group with the lowest id moves to the right band.

| Current | Occupied (others) | Left   | Right  |
| ------- | ----------------- | ------ | ------ |
| 1       | 2, 3, 4           | 4      | 2, 3   |
| 2       | 1, 3, 4           | 1      | 3, 4   |
| 4       | 1, 2, 3           | 2, 3   | 1      |
| 1       | 2                 | (none) | 2      |
| 3       | 1, 2              | 2      | 1      |
| 3       | 1                 | 1      | (none) |

## Reading order

Within a group, windows are in reading order: tiled windows first, left to right (x differing by more than 4 px), then top to bottom; floating windows last.

## Cards

The band's inner width is `bandW = sideW − 2 × bandMargin`. The left band's cards start at x = `bandMargin`, the right band's at x = `monW − sideW + bandMargin`.

1. Each group gets a vertical slice of the band. The slice height is proportional to the group's bounding box height at band width (`bandW × box.h / box.w`), stretched by one factor for the whole band, up to `maxStretch`, to use the band's height. The slices are centred vertically, each below a header of `headerHeight`, with `groupGap` between groups.
2. The centre of each window maps from the group's bounding box into the slice (anisotropic when stretched).
3. All cards in a band use one scale. A card keeps its window's aspect ratio.
4. Overlapping cards (closer than `cardGap`) are pushed apart along the axis with the smaller overlap, if there is room on that axis; otherwise along the other axis. Cards stay inside their slice. Ties keep reading order: the earlier window goes left or up.
5. The scale is the largest (binary search, 16 steps, between 0.02 and the largest scale at which every window fits its slice) at which every group of the band resolves without overlap. If none does, the smallest scale is used and overlaps remain.

Consequence: two tiled windows side by side do not fit side by side in a narrow band. They stack vertically, with a small horizontal offset that shows which one was on the left.

## Headers

Each group has a header: its workspace label, `headerHeight` tall, directly above the group's topmost card. The header's rect spans the band's inner width and reaches down to the group's lowest card. It is also the drop target of the group.

## Output

- **Cards** keyed by window address: the window's fields (address, title, class, workspace id, and anything else the caller passed along) with the card rect `x`, `y`, `w`, `h` in monitor-local pixels.
- **Headers:** `{ id, label, x, y, w, h }` per group, left band first, each band top to bottom.
- **Left and right:** the workspace ids per band, in order.
