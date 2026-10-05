//#region src/selection/selection.ts
const centreX = (r) => r.x + r.w / 2;
const centreY = (r) => r.y + r.h / 2;
/** The card a focus key past the focus area's edge selects, or null. */
function enterBand(cards, dir, activeTile, monW, monH) {
	const refY = activeTile ? centreY(activeTile) : monH / 2;
	let best = null;
	let bestD = Infinity;
	for (const [address, c] of Object.entries(cards)) {
		if (dir === "l" !== c.x < monW / 2) continue;
		const d = Math.abs(centreY(c) - refY);
		if (d < bestD) {
			bestD = d;
			best = address;
		}
	}
	return best;
}
/** What a focus key does on the selected card. */
function stepSelection(cards, selected, dir, tiles, monW, sideW) {
	const cur = cards[selected];
	if (!cur) return { kind: "clear" };
	const left = cur.x < monW / 2;
	const cx = centreX(cur);
	const cy = centreY(cur);
	const horizontal = dir === "l" || dir === "r";
	const sign = dir === "l" || dir === "u" ? -1 : 1;
	let best = null;
	let bestScore = Infinity;
	for (const [address, c] of Object.entries(cards)) {
		if (address === selected || c.x < monW / 2 !== left) continue;
		const along = sign * (horizontal ? centreX(c) - cx : centreY(c) - cy);
		const across = Math.abs(horizontal ? centreY(c) - cy : centreX(c) - cx);
		if (along <= 1) continue;
		if (along + across * 2 < bestScore) {
			bestScore = along + across * 2;
			best = address;
		}
	}
	if (best) return {
		kind: "select",
		address: best
	};
	if (dir !== (left ? "r" : "l")) return { kind: "stay" };
	let target = null;
	let targetScore = Infinity;
	for (const [address, r] of Object.entries(tiles)) {
		const edge = left ? r.x - sideW : monW - sideW - (r.x + r.w);
		const off = cy < r.y ? r.y - cy : cy > r.y + r.h ? cy - r.y - r.h : 0;
		if (Math.abs(edge) + off < targetScore) {
			targetScore = Math.abs(edge) + off;
			target = address;
		}
	}
	return {
		kind: "focus",
		address: target
	};
}
/** The group whose drop area contains the point, or null. */
function groupAt(groups, x, y, bandMargin, groupGap) {
	for (const g of groups) if (x >= g.x - bandMargin && x <= g.x + g.w + bandMargin && y >= g.y - groupGap / 2 && y <= g.y + g.h + groupGap / 2) return g;
	return null;
}
/** The lowest workspace id with nothing on it, for drops on empty band. */
function freeWorkspaceId(occupied, current) {
	const used = /* @__PURE__ */ new Set([...occupied, current]);
	for (let id = 1; id < 100; id++) if (!used.has(id)) return id;
	return 100;
}
//#endregion
export { enterBand, freeWorkspaceId, groupAt, stepSelection };
