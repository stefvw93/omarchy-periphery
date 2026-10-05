# Selection (`src/selection`)

Where the focus keys move the periphery selection, and which group or workspace a drop lands on. Pure: card and tile rects in, an address or a workspace out. Terms as in [SPEC.md](../../SPEC.md#periphery-selection).

All rects are monitor-local pixels `{ x, y, w, h }`. A card is in the left band when its x is left of the monitor's middle, otherwise in the right band.

## Entering a band

A focus key past the left or right edge of the focus area (`l` or `r`) selects a card in that band: the one whose vertical centre is nearest the vertical centre of the active window's tile. Without an active tile (an empty workspace, or a window not in the focus area), the reference is the monitor's middle height. A band without cards selects nothing.

## Stepping

A focus key (`l`, `r`, `u`, `d`) on a selected card:

1. **Next card.** Among the other cards in the same band whose centre lies more than 1 px that way from the selected card's centre, pick the one with the lowest score: distance along the direction + 2 × distance across it (centre to centre). The selection moves there.
   - For `l` and `r`, only cards beside the selected card count: their vertical extent overlaps its own. A card further up or down is reached with `u` and `d`, never with `l` or `r`.
   - For `u` and `d`, any card that way counts.
2. **Back to the focus area.** With no card that way, and the direction pointing at the focus area (`r` in the left band, `l` in the right band): the focus area window on that edge nearest the card's height gets the focus, and the selection clears. Score per tile: distance from the tile's edge to the band edge + the vertical distance from the card's centre to the tile (0 when the centre is within the tile's height). No tiles: the selection clears and nothing gets the focus.
3. **Otherwise** the selection stays.

A selected address that is not a card (any more) clears the selection.

## Drop targets

- **Group at a point:** the first group whose header rect, grown by `bandMargin` left and right and by half the `groupGap` above and below, contains the point. None: no group.
- **Free workspace:** the lowest workspace id from 1 that has no windows and is not the current workspace. 100 when 1 to 99 are all taken.
