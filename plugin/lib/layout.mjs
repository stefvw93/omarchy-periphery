//#region \0@oxc-project+runtime@0.151.0/helpers/esm/typeof.js
function _typeof(o) {
	"@babel/helpers - typeof";
	return _typeof = "function" == typeof Symbol && "symbol" == typeof Symbol.iterator ? function(o) {
		return typeof o;
	} : function(o) {
		return o && "function" == typeof Symbol && o.constructor === Symbol && o !== Symbol.prototype ? "symbol" : typeof o;
	}, _typeof(o);
}
//#endregion
//#region \0@oxc-project+runtime@0.151.0/helpers/esm/toPrimitive.js
function toPrimitive(t, r) {
	if ("object" != _typeof(t) || !t) return t;
	var e = t[Symbol.toPrimitive];
	if (void 0 !== e) {
		var i = e.call(t, r || "default");
		if ("object" != _typeof(i)) return i;
		throw new TypeError("@@toPrimitive must return a primitive value.");
	}
	return ("string" === r ? String : Number)(t);
}
//#endregion
//#region \0@oxc-project+runtime@0.151.0/helpers/esm/toPropertyKey.js
function toPropertyKey(t) {
	var i = toPrimitive(t, "string");
	return "symbol" == _typeof(i) ? i : i + "";
}
//#endregion
//#region \0@oxc-project+runtime@0.151.0/helpers/esm/defineProperty.js
function _defineProperty(e, r, t) {
	return (r = toPropertyKey(r)) in e ? Object.defineProperty(e, r, {
		value: t,
		enumerable: !0,
		configurable: !0,
		writable: !0
	}) : e[r] = t, e;
}
//#endregion
//#region \0@oxc-project+runtime@0.151.0/helpers/esm/objectSpread2.js
function ownKeys(e, r) {
	var t = Object.keys(e);
	if (Object.getOwnPropertySymbols) {
		var o = Object.getOwnPropertySymbols(e);
		r && (o = o.filter(function(r) {
			return Object.getOwnPropertyDescriptor(e, r).enumerable;
		})), t.push.apply(t, o);
	}
	return t;
}
function _objectSpread2(e) {
	for (var r = 1; r < arguments.length; r++) {
		var t = null != arguments[r] ? arguments[r] : {};
		r % 2 ? ownKeys(Object(t), !0).forEach(function(r) {
			_defineProperty(e, r, t[r]);
		}) : Object.getOwnPropertyDescriptors ? Object.defineProperties(e, Object.getOwnPropertyDescriptors(t)) : ownKeys(Object(t)).forEach(function(r) {
			Object.defineProperty(e, r, Object.getOwnPropertyDescriptor(t, r));
		});
	}
	return e;
}
//#endregion
//#region \0@oxc-project+runtime@0.151.0/helpers/esm/objectWithoutPropertiesLoose.js
function _objectWithoutPropertiesLoose(r, e) {
	if (null == r) return {};
	var t = {};
	for (var n in r) if ({}.hasOwnProperty.call(r, n)) {
		if (e.includes(n)) continue;
		t[n] = r[n];
	}
	return t;
}
//#endregion
//#region \0@oxc-project+runtime@0.151.0/helpers/esm/objectWithoutProperties.js
function _objectWithoutProperties(e, t) {
	if (null == e) return {};
	var o, r, i = _objectWithoutPropertiesLoose(e, t);
	if (Object.getOwnPropertySymbols) {
		var s = Object.getOwnPropertySymbols(e);
		for (r = 0; r < s.length; r++) o = s[r], t.includes(o) || {}.propertyIsEnumerable.call(e, o) && (i[o] = e[o]);
	}
	return i;
}
//#endregion
//#region src/layout/layout.ts
const _excluded = [
	"rx",
	"ry",
	"rw",
	"rh"
];
/** Sorts workspace ids into the bands, with the wrap rule. */
function assignBands(ids, current) {
	const sorted = [...ids].sort((a, b) => a - b);
	const left = sorted.filter((id) => id < current);
	const right = sorted.filter((id) => id > current);
	if (left.length === 0 && right.length >= 2) left.push(right.pop());
	else if (right.length === 0 && left.length >= 2) right.push(left.shift());
	return {
		left,
		right
	};
}
/** A group's windows in reading order (a sorted copy). */
function readingOrder(windows) {
	return [...windows].sort((a, b) => {
		if (a.floating !== b.floating) return a.floating ? 1 : -1;
		if (Math.abs(a.rx - b.rx) > 4) return a.rx - b.rx;
		return a.ry - b.ry;
	});
}
/** The whole layout: bands, cards and headers. */
function layoutBands(windows, current, geometry) {
	const byWs = /* @__PURE__ */ new Map();
	for (const w of windows) {
		const group = byWs.get(w.wsId);
		if (group) group.windows.push(w);
		else byWs.set(w.wsId, {
			label: w.wsName || String(w.wsId),
			windows: [w]
		});
	}
	const { left, right } = assignBands([...byWs.keys()], current);
	const groupsOf = (ids) => ids.map((id) => {
		const g = byWs.get(id);
		return {
			id,
			label: g.label,
			windows: readingOrder(g.windows)
		};
	});
	const cards = {};
	const headers = [];
	placeSide(groupsOf(left), geometry.bandMargin, geometry, cards, headers);
	placeSide(groupsOf(right), geometry.monW - geometry.sideW + geometry.bandMargin, geometry, cards, headers);
	return {
		cards,
		headers,
		left,
		right
	};
}
function placeSide(input, bandX, geo, cards, headers) {
	var _best;
	if (input.length === 0) return;
	const bandW = geo.sideW - geo.bandMargin * 2;
	const availH = geo.monH - geo.bandMargin * 2 - input.length * geo.headerHeight - (input.length - 1) * geo.groupGap;
	const groups = input.map((g) => {
		let x0 = Infinity;
		let y0 = Infinity;
		let x1 = -Infinity;
		let y1 = -Infinity;
		for (const w of g.windows) {
			x0 = Math.min(x0, w.rx);
			y0 = Math.min(y0, w.ry);
			x1 = Math.max(x1, w.rx + w.rw);
			y1 = Math.max(y1, w.ry + w.rh);
		}
		const box = {
			x: x0,
			y: y0,
			w: Math.max(1, x1 - x0),
			h: Math.max(1, y1 - y0)
		};
		return _objectSpread2(_objectSpread2({}, g), {}, {
			box,
			naturalH: bandW * box.h / box.w
		});
	});
	const natural = groups.reduce((sum, g) => sum + g.naturalH, 0);
	const stretch = Math.min(geo.maxStretch, availH / natural);
	const bodies = groups.map((g) => g.naturalH * stretch);
	const used = bodies.reduce((a, b) => a + b, 0) + groups.length * geo.headerHeight + (groups.length - 1) * geo.groupGap;
	const regions = [];
	let y = (geo.monH - used) / 2;
	for (const body of bodies) {
		regions.push({
			x: bandX,
			y: y + geo.headerHeight,
			w: bandW,
			h: body
		});
		y += geo.headerHeight + body + geo.groupGap;
	}
	let lo = .02;
	let hi = 1;
	groups.forEach((g, k) => {
		for (const w of g.windows) hi = Math.min(hi, bandW / w.rw, bodies[k] / w.rh);
	});
	let best = null;
	for (let iter = 0; iter < 16; iter++) {
		const mid = (lo + hi) / 2;
		const trial = [];
		let ok = true;
		for (let t = 0; t < groups.length && ok; t++) {
			const placed = resolve(groups[t], regions[t], mid, geo.cardGap, false);
			if (placed) trial.push(placed);
			else ok = false;
		}
		if (ok) {
			lo = mid;
			best = trial;
		} else hi = mid;
	}
	(_best = best) !== null && _best !== void 0 || (best = groups.map((g, f) => resolve(g, regions[f], lo, geo.cardGap, true)));
	groups.forEach((g, h) => {
		const placed = best[h];
		const minY = Math.min(...placed.map((c) => c.y));
		const maxY = Math.max(...placed.map((c) => c.y + c.h));
		headers.push({
			id: g.id,
			label: g.label,
			x: bandX,
			y: minY - geo.headerHeight,
			w: bandW,
			h: maxY - minY + geo.headerHeight
		});
		for (const c of placed) cards[c.address] = c;
	});
}
function resolve(group, region, scale, gap, force) {
	const box = group.box;
	const placed = group.windows.map((w) => {
		return {
			window: w,
			w: w.rw * scale,
			h: w.rh * scale,
			cx: region.x + (w.rx + w.rw / 2 - box.x) / box.w * region.w,
			cy: region.y + (w.ry + w.rh / 2 - box.y) / box.h * region.h
		};
	});
	const clamp = (c) => {
		c.cx = Math.max(region.x + c.w / 2, Math.min(region.x + region.w - c.w / 2, c.cx));
		c.cy = Math.max(region.y + c.h / 2, Math.min(region.y + region.h - c.h / 2, c.cy));
	};
	placed.forEach(clamp);
	let clear = false;
	for (let pass = 0; pass < 120 && !clear; pass++) {
		clear = true;
		for (let i = 0; i < placed.length; i++) for (let j = i + 1; j < placed.length; j++) {
			const a = placed[i];
			const b = placed[j];
			const dx = b.cx - a.cx;
			const dy = b.cy - a.cy;
			const ox = (a.w + b.w) / 2 + gap - Math.abs(dx);
			const oy = (a.h + b.h) / 2 + gap - Math.abs(dy);
			if (ox <= .5 || oy <= .5) continue;
			clear = false;
			const sx = dx >= 0 ? 1 : -1;
			const sy = dy >= 0 ? 1 : -1;
			const xRoom = sx > 0 ? a.cx - a.w / 2 - region.x + (region.x + region.w - b.cx - b.w / 2) : region.x + region.w - a.cx - a.w / 2 + (b.cx - b.w / 2 - region.x);
			const yRoom = sy > 0 ? a.cy - a.h / 2 - region.y + (region.y + region.h - b.cy - b.h / 2) : region.y + region.h - a.cy - a.h / 2 + (b.cy - b.h / 2 - region.y);
			const canX = xRoom >= ox - .5;
			const canY = yRoom >= oy - .5;
			if (canX && canY ? ox <= oy : canX || canY ? canX : xRoom / ox >= yRoom / oy) {
				a.cx -= sx * ox / 2;
				b.cx += sx * ox / 2;
			} else {
				a.cy -= sy * oy / 2;
				b.cy += sy * oy / 2;
			}
			clamp(a);
			clamp(b);
		}
	}
	if (!clear && !force) return null;
	return placed.map((c) => {
		const _c$window = c.window, { rx: _rx, ry: _ry, rw: _rw, rh: _rh } = _c$window;
		return _objectSpread2(_objectSpread2({}, _objectWithoutProperties(_c$window, _excluded)), {}, {
			x: c.cx - c.w / 2,
			y: c.cy - c.h / 2,
			w: c.w,
			h: c.h
		});
	});
}
//#endregion
export { assignBands, layoutBands, readingOrder };
