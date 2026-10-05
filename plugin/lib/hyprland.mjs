//#region src/hyprland/hyprland.ts
/** Turns Hyprland's workspace animation off (a flight's switch). */
const workspacesOffLua = "hl.animation({ leaf = \"workspaces\", enabled = false })";
/** The `workspaces` animation from `hyprctl animations -j` as an `hl.animation` call. */
function workspaceAnimationLua(animationsJson, style) {
	var _a$bezier;
	const lists = JSON.parse(animationsJson);
	const a = (Array.isArray(lists[0]) ? lists[0] : lists).find((x) => x.name === "workspaces");
	if (!a) return "";
	if (!a.enabled && !style) return workspacesOffLua;
	const parts = [
		"leaf = \"workspaces\"",
		"enabled = true",
		`speed = ${a.speed}`
	];
	const curve = String((_a$bezier = a.bezier) !== null && _a$bezier !== void 0 ? _a$bezier : "");
	if (curve.startsWith("spring:")) parts.push(`spring = "${curve.slice(7)}"`);
	else if (curve) parts.push(`bezier = "${curve}"`);
	const finalStyle = style || a.style;
	if (finalStyle) parts.push(`style = "${finalStyle}"`);
	return `hl.animation({ ${parts.join(", ")} })`;
}
/** How far cards travel with a workspace switch in this animation style. */
function cardTravel(style, monW, monH) {
	const vertical = /vert/.test(style);
	if (!/slide/.test(style)) return {
		distance: 0,
		vertical
	};
	const extent = vertical ? monH : monW;
	const percent = /(\d+(?:\.\d+)?)%/.exec(style);
	return {
		distance: percent ? extent * parseFloat(percent[1]) / 100 : extent,
		vertical
	};
}
/** The `hyprctl eval` string that hands the plugin's state to hypr.lua. */
function hookStateLua(state) {
	if (!state.opened) return "if periphery_close then periphery_close() end";
	const bounds = [
		state.monX + state.sideW,
		state.monX + state.monW - state.sideW,
		state.monY,
		state.monY + state.monH
	].map(Math.round);
	const selected = /^0x[0-9a-fA-F]+$/.test(state.selected) ? `"${state.selected}"` : "nil";
	return `if periphery_open then periphery_open(${[
		state.cardsLeft,
		state.cardsRight,
		...bounds
	].join(", ")}); periphery_select(${selected}) end`;
}
/** Border width and rounding from two `hyprctl -j getoption` outputs. */
function parseDecoration(text) {
	const read = (option) => {
		const m = new RegExp(`"${option}",\\s*"int":\\s*(\\d+)`).exec(text);
		return m ? parseInt(m[1], 10) : void 0;
	};
	const result = {};
	const borderSize = read("general:border_size");
	const rounding = read("decoration:rounding");
	if (borderSize !== void 0) result.borderSize = borderSize;
	if (rounding !== void 0) result.rounding = rounding;
	return result;
}
//#endregion
export { cardTravel, hookStateLua, parseDecoration, workspaceAnimationLua, workspacesOffLua };
