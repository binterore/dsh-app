/* dsh-confetti-click — DSH client bundle (web).
 *
 * A Cordis plugin: the loader applies `apply` when the fiber starts and calls
 * the returned disposer on unload. While active it installs:
 *   - a document-level click listener (capture phase, so no UI element can
 *     swallow it) that scatters a burst of confetti at the pointer when the
 *     effect is enabled;
 *   - a floating 🎉 toggle button (bottom-right, subtle) and the keyboard
 *     shortcut Alt+Shift+X that flip the effect on/off instantly — no server
 *     restart, no profile edits. The state persists in localStorage.
 *
 * Self-contained on purpose: zero requires, no build step, no React — the
 * bundle is the package's client half and runs as a plain classic script.
 * Unloading the plugin also removes the listener, button, animation, overlay,
 * and style.
 */
window.__ModuleLoader__.load({
	id: "dsh-confetti-click",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;

		exports.apply = apply;
		return module.exports;
	}
});

var COLORS = [
	"#ff6b6b", "#ff9f43", "#feca57", "#feca57",
	"#48dbfb", "#0abde3", "#1dd1a1", "#10ac84",
	"#ff9ff3", "#f368e0", "#5f27cd", "#a29bfe", "#fab1a0"
];

var MAX_PARTICLES = 320;

var STORAGE_KEY = "dsh-confetti-click.enabled";
var enabled = true;
try {
	enabled = window.localStorage.getItem(STORAGE_KEY) !== "0";
} catch (_storageUnavailable) {}

var layer = null;
var particles = [];
var rafId = null;
var lastTs = null;
var toggleBtn = null;

function apply() {
	install();
	return uninstall;
}

function install() {
	if (typeof document === "undefined") return;
	// Styles — the module loader inventories <style> tags for HMR cleanup,
	// so plain injection is the supported pattern.
	var styleId = "dsh-confetti-click-style";
	if (!document.getElementById(styleId)) {
		var style = document.createElement("style");
		style.id = styleId;
		style.textContent = [
			"#dsh-confetti-layer{position:fixed;inset:0;overflow:hidden;pointer-events:none;z-index:2147483647}",
			"#dsh-confetti-layer>div{position:absolute;left:0;top:0;will-change:transform,opacity}",
			"#dsh-confetti-toggle{position:fixed;right:28px;bottom:104px;z-index:950;width:28px;height:28px;border-radius:50%;border:1px solid var(--dsw-alias-border-l2,rgba(128,128,128,.35));background:var(--dsw-alias-bg-layer-3,rgba(30,30,40,.72));color:var(--dsw-alias-label-primary,#fff);cursor:pointer;display:flex;align-items:center;justify-content:center;font-size:14px;line-height:1;padding:0;opacity:.45;transition:opacity .15s,filter .15s;box-shadow:0 2px 8px rgba(0,0,0,.18)}",
			"#dsh-confetti-toggle:hover{opacity:1}",
			"#dsh-confetti-toggle.off{filter:grayscale(1);opacity:.35}"
		].join("\n");
		(document.head || document.documentElement).appendChild(style);
	}
	createToggleButton();
	document.addEventListener("click", onPointerClick, true);
	document.addEventListener("keydown", onKeyDown, true);
}

function uninstall() {
	if (typeof document === "undefined") return;
	document.removeEventListener("click", onPointerClick, true);
	document.removeEventListener("keydown", onKeyDown, true);
	if (rafId !== null) cancelAnimationFrame(rafId);
	rafId = null;
	lastTs = null;
	for (var i = particles.length - 1; i >= 0; i--) {
		var el = particles[i].el;
		if (el.parentNode) el.parentNode.removeChild(el);
	}
	particles = [];
	if (layer !== null && layer.isConnected) layer.remove();
	layer = null;
	if (toggleBtn !== null) {
		if (toggleBtn.parentNode) toggleBtn.parentNode.removeChild(toggleBtn);
		toggleBtn = null;
	}
	var style = document.getElementById("dsh-confetti-click-style");
	if (style !== null) style.remove();
}

function setEnabled(on) {
	enabled = !!on;
	try {
		window.localStorage.setItem(STORAGE_KEY, enabled ? "1" : "0");
	} catch (_storageUnavailable) {}
	updateToggleButton();
}

function toggle() {
	setEnabled(!enabled);
}

function createToggleButton() {
	if (toggleBtn !== null) return;
	toggleBtn = document.createElement("button");
	toggleBtn.type = "button";
	toggleBtn.id = "dsh-confetti-toggle";
	toggleBtn.title = "撒花开关 — Alt+Shift+X";
	toggleBtn.setAttribute("aria-label", "撒花开关");
	toggleBtn.addEventListener("click", function (event) {
		event.stopPropagation();
		toggle();
	});
	document.documentElement.appendChild(toggleBtn);
	updateToggleButton();
}

function updateToggleButton() {
	if (toggleBtn === null) return;
	toggleBtn.textContent = enabled ? "🎉" : "🚫";
	toggleBtn.setAttribute("aria-pressed", enabled ? "true" : "false");
	if (enabled) toggleBtn.classList.remove("off");
	else toggleBtn.classList.add("off");
}

function onKeyDown(event) {
	if (event.altKey && event.shiftKey && (event.key === "X" || event.key === "x")) {
		event.preventDefault();
		toggle();
	}
}

function onPointerClick(event) {
	if (!enabled) return;
	if (event.target === toggleBtn) return;
	spawn(event.clientX, event.clientY);
	start();
}

function ensureLayer() {
	if (layer !== null && layer.isConnected) return layer;
	layer = document.createElement("div");
	layer.id = "dsh-confetti-layer";
	document.documentElement.appendChild(layer);
	return layer;
}

function spawn(x, y) {
	var count = 70 + Math.floor(Math.random() * 30);
	var root = ensureLayer();
	for (var i = 0; i < count; i++) {
		if (particles.length >= MAX_PARTICLES) break;
		var el = document.createElement("div");
		var w = 6 + Math.random() * 6;
		el.style.width = w.toFixed(1) + "px";
		el.style.height = (w * (0.5 + Math.random() * 0.7)).toFixed(1) + "px";
		el.style.background = COLORS[(Math.random() * COLORS.length) | 0];
		el.style.borderRadius = Math.random() < 0.35 ? "50%" : "2px";
		root.appendChild(el);
		var angle = Math.random() * Math.PI * 2;
		var speed = 3.5 + Math.random() * 8.5;
		particles.push({
			el: el,
			x: x,
			y: y,
			vx: Math.cos(angle) * speed,
			vy: Math.sin(angle) * speed - 5.5, // upward bias: a fountain, not a puddle
			rot: Math.random() * Math.PI * 2,
			vrot: (Math.random() - 0.5) * 0.4,
			life: 0,
			ttl: 800 + Math.random() * 1100
		});
	}
}

function start() {
	if (rafId !== null) return;
	lastTs = null;
	rafId = requestAnimationFrame(tick);
}

function tick(now) {
	rafId = null;
	var dt = lastTs === null ? 16.7 : Math.min(40, now - lastTs);
	lastTs = now;
	var k = dt / 16.7;
	var alive = 0;
	for (var i = particles.length - 1; i >= 0; i--) {
		var p = particles[i];
		p.life += dt;
		if (p.life >= p.ttl) {
			if (p.el.parentNode) p.el.parentNode.removeChild(p.el);
			particles.splice(i, 1);
			continue;
		}
		p.vy += 0.32 * k; // gravity
		p.x += p.vx * k;
		p.y += p.vy * k;
		p.rot += p.vrot * k;
		var fade = 1 - Math.max(0, (p.life - p.ttl * 0.55) / (p.ttl * 0.45));
		p.el.style.opacity = fade.toFixed(3);
		p.el.style.transform = "translate(" + p.x.toFixed(1) + "px," + p.y.toFixed(1) + "px) rotate(" + p.rot.toFixed(2) + "rad)";
		alive++;
	}
	if (alive > 0) {
		rafId = requestAnimationFrame(tick);
	} else {
		lastTs = null;
		if (layer !== null && layer.isConnected) layer.remove();
		layer = null;
	}
}
