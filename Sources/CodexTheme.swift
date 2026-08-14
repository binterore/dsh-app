import Foundation

/// A restrained Codex-inspired skin for the DSH web client.
///
/// The DSH client uses CSS modules, so the generated class prefix changes
/// between releases. Selectors intentionally match the stable semantic suffix
/// instead of a concrete build hash.
let codexThemeCSS = #"""
:root {
  --codex-canvas: #ffffff;
  --codex-surface: #ffffff;
  --codex-sidebar: #fbfafa;
  --codex-raised: #f7f7f7;
  --codex-hover: rgba(0, 0, 0, 0.04);
  --codex-active: rgba(0, 0, 0, 0.055);
  --codex-text: #242424;
  --codex-text-secondary: #686868;
  --codex-text-tertiary: #969696;
  --codex-border: rgba(0, 0, 0, 0.10);
  --codex-border-subtle: rgba(0, 0, 0, 0.065);
  --codex-control: #242424;
  --codex-control-hover: #111111;
  --codex-control-text: #ffffff;
  --codex-shadow: 0 1px 2px rgba(0, 0, 0, 0.04),
                  0 10px 30px rgba(0, 0, 0, 0.055);
  --codex-font: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  --codex-mono-font: ui-monospace, "SFMono-Regular", "SF Mono", Menlo,
                     Consolas, "Liberation Mono", monospace;
}

html,
body,
#root {
  background: var(--codex-canvas) !important;
}

body {
  --dsw-font-family: var(--codex-font);
  --ds-font-family-code: var(--codex-mono-font);
  --dsw-font-xl-24: 600 24px/32px var(--codex-font);
  --dsw-font-l-20: 500 20px/28px var(--codex-font);
  --dsw-font-m-18: 500 16px/24px var(--codex-font);
  --dsw-font-base-16: 14px/21px var(--codex-font);
  --dsw-font-base-16-font-size: 14px;
  --dsw-font-base-16-line-height: 21px;
  --dsw-font-base-strong-16: 500 14px/21px var(--codex-font);
  --dsw-font-base-strong-16-font-size: 14px;
  --dsw-font-base-strong-16-line-height: 21px;
  --dsw-font-s-14: 13px/20px var(--codex-font);
  --dsw-font-s-14-font-size: 13px;
  --dsw-font-s-14-line-height: 20px;
  --dsw-font-s-strong-14: 500 13px/20px var(--codex-font);
  --dsw-font-s-strong-14-font-size: 13px;
  --dsw-font-s-strong-14-line-height: 20px;
  --dsw-font-xs-13: 12px/18px var(--codex-font);
  --dsw-font-xs-13-font-size: 12px;
  --dsw-font-xs-13-line-height: 18px;
  --dsw-font-xs-strong-13: 500 12px/18px var(--codex-font);
  --dsw-font-xs-strong-13-font-size: 12px;
  --dsw-font-xs-strong-13-line-height: 18px;
  --dsw-font-xxs-12: 11px/16px var(--codex-font);
  --dsw-font-xxs-12-font-size: 11px;
  --dsw-font-xxs-12-line-height: 16px;
  --dsw-font-xxs-strong-12: 500 11px/16px var(--codex-font);
  --dsw-font-markdown-h1: 600 24px/32px var(--codex-font);
  --dsw-font-markdown-h2: 600 20px/28px var(--codex-font);
  --dsw-font-markdown-h3: 600 18px/26px var(--codex-font);
  --dsw-font-markdown-h4: 600 16px/24px var(--codex-font);
  --dsw-font-markdown-base: 14px/22px var(--codex-font);
  --dsw-font-markdown-base-font-size: 14px;
  --dsw-font-markdown-base-line-height: 22px;
  --dsw-font-markdown-base-strong: 600 14px/22px var(--codex-font);
  --dsw-font-markdown-base-strong-font-size: 14px;
  --dsw-font-markdown-base-strong-line-height: 22px;
  --dsw-font-markdown-base-italic: italic 14px/22px var(--codex-font);
  --dsw-font-markdown-base-strong-italic: italic 600 14px/22px var(--codex-font);
  --dsw-font-markdown-small: 13px/20px var(--codex-font);
  --dsw-font-markdown-small-font-size: 13px;
  --dsw-font-markdown-small-line-height: 20px;
  --dsw-font-markdown-small-strong: 600 13px/20px var(--codex-font);
  --dsw-font-markdown-small-italic: italic 13px/20px var(--codex-font);
  --dsw-font-markdown-small-strong-italic: italic 600 13px/20px var(--codex-font);
  --dsw-font-markdown-table: 13px/20px var(--codex-font);
  --dsw-font-markdown-table-head: 500 13px/20px var(--codex-font);
  --dsw-font-markdown-code: 12px/18px var(--codex-mono-font);
  --dsw-font-markdown-code-font-size: 12px;
  --dsw-font-markdown-code-line-height: 18px;
  --dsw-font-markdown-code-block: 12px/18px var(--codex-mono-font);
  --dsw-font-markdown-code-block-font-size: 12px;
  --dsw-font-markdown-code-block-line-height: 18px;
  --dsw-alias-bg-base: var(--codex-canvas);
  --dsw-alias-bg-layer-1: var(--codex-surface);
  --dsw-alias-bg-layer-2: var(--codex-raised);
  --dsw-alias-bg-layer-3: var(--codex-surface);
  --dsw-alias-border-inverted: var(--codex-border-subtle);
  --dsw-alias-border-inverted2: var(--codex-border-subtle);
  --dsw-alias-border-l1: var(--codex-border-subtle);
  --dsw-alias-border-l2: var(--codex-border);
  --dsw-alias-border-l2-darkmode-thin: var(--codex-border-subtle);
  --dsw-alias-border-l3: rgba(0, 0, 0, 0.16);
  --dsw-alias-brand-primary: var(--codex-control);
  --dsw-alias-brand-text: var(--codex-text);
  --dsw-alias-button-primary-fill: var(--codex-control);
  --dsw-alias-button-primary-hover: var(--codex-control-hover);
  --dsw-alias-button-primary-dimmed: #c8c8c2;
  --dsw-alias-button-elevated-fill: var(--codex-surface);
  --dsw-alias-button-floating-fill: var(--codex-surface);
  --dsw-alias-button-floating-hover: var(--codex-raised);
  --dsw-alias-button-ghost-active-border: var(--codex-border);
  --dsw-alias-button-ghost-active-fill: var(--codex-active);
  --dsw-alias-button-tool-bar-fill: var(--codex-raised);
  --dsw-alias-button-tool-bar-hover: var(--codex-active);
  --dsw-alias-interactive-bg-hover: var(--codex-hover);
  --dsw-alias-interactive-bg-active: var(--codex-active);
  --dsw-alias-interactive-bg-hover-solid: #eeeeee;
  --dsw-alias-label-primary: var(--codex-text);
  --dsw-alias-label-primary-bluish: var(--codex-text);
  --dsw-alias-label-primary-foreground: var(--codex-control-text);
  --dsw-alias-label-secondary: var(--codex-text-secondary);
  --dsw-alias-label-tertiary: var(--codex-text-tertiary);
  --dsw-alias-label-caption: var(--codex-text-tertiary);
  --dsw-alias-label-dimmed: #b4b4b4;
  --dsw-specific-input-major: var(--codex-surface);
  --dsw-specific-menu: var(--codex-surface);
  --dsw-specific-selector: var(--codex-raised);
  --dsw-specific-sidebar-fill: var(--codex-sidebar);
  --dsw-specific-sidebar-nav-item-active: var(--codex-active);
  --dsw-specific-sidebar-nav-item-active-accent: var(--codex-active);
  --dsw-specific-sidebar-nav-item-hover: var(--codex-hover);
  --dsw-specific-bubble: #f2f2f2;
  --dsw-shadow-lv1: 0 1px 2px rgba(0, 0, 0, 0.04);
  --dsw-shadow-lv2: var(--codex-shadow);
  --dsw-shadow-lv3: 0 14px 42px rgba(0, 0, 0, 0.14),
                    0 1px 2px rgba(0, 0, 0, 0.08);
  color: var(--codex-text);
  font-family: var(--codex-font) !important;
  font-size: 14px;
  letter-spacing: normal;
}

body[data-ds-dark-theme] {
  --codex-canvas: #111110;
  --codex-surface: #191918;
  --codex-sidebar: #171716;
  --codex-raised: #222220;
  --codex-hover: rgba(255, 255, 248, 0.075);
  --codex-active: rgba(255, 255, 248, 0.115);
  --codex-text: #efefe9;
  --codex-text-secondary: #aaa9a1;
  --codex-text-tertiary: #797972;
  --codex-border: rgba(255, 255, 248, 0.12);
  --codex-border-subtle: rgba(255, 255, 248, 0.075);
  --codex-control: #efefe9;
  --codex-control-hover: #ffffff;
  --codex-control-text: #181816;
  --codex-shadow: 0 1px 2px rgba(0, 0, 0, 0.25),
                  0 16px 36px rgba(0, 0, 0, 0.22);
  --dsw-alias-button-primary-dimmed: #51514d;
  --dsw-alias-interactive-bg-hover-solid: #2a2a28;
  --dsw-alias-label-dimmed: #565650;
  --dsw-specific-bubble: #252523;
}

/* Native-titlebar breathing room and the compact, quiet Codex sidebar. */
[class*="_sidebarCol"] {
  background: var(--codex-sidebar) !important;
  border-right: 1px solid var(--codex-border-subtle);
}

[class*="_handle"][data-side="sidebar"] {
  z-index: 5 !important;
  cursor: col-resize !important;
}

[class*="_handle"][data-side="sidebar"]::after {
  content: "";
  position: absolute;
  inset: 0 auto 0 3px;
  width: 2px;
  background: var(--codex-border);
  opacity: 0;
  pointer-events: none;
  transition: opacity 120ms ease;
}

[class*="_handle"][data-side="sidebar"]:hover::after,
[class*="_handle"][data-side="sidebar"][data-dragging="true"]::after {
  opacity: 1;
}

/* Codex's short marks are a turn minimap, not the sidebar resize grip. Each
   mark represents one user message and lives just inside the transcript. */
#dsh-codex-turn-map {
  position: fixed;
  top: 50%;
  z-index: 4;
  width: 12px;
  transform: translateY(-50%);
  pointer-events: none;
}

#dsh-codex-turn-map[hidden] {
  display: none !important;
}

#dsh-codex-turn-map button {
  position: relative;
  display: block;
  width: 12px;
  height: 10px;
  margin: 0;
  padding: 0;
  border: 0;
  outline: 0;
  background: transparent;
  cursor: pointer;
  pointer-events: auto;
}

#dsh-codex-turn-map button::after {
  content: "";
  position: absolute;
  top: 4px;
  left: 3px;
  width: 6px;
  height: 2px;
  border-radius: 1px;
  background: rgba(36, 36, 36, 0.18);
  transition: width 100ms ease, left 100ms ease, background-color 100ms ease;
}

#dsh-codex-turn-map button:hover::after,
#dsh-codex-turn-map button:focus-visible::after {
  left: 1px;
  width: 10px;
  background: rgba(36, 36, 36, 0.34);
}

#dsh-codex-turn-map button[aria-current="true"]::after {
  background: rgba(36, 36, 36, 0.62);
}

body[data-ds-dark-theme] #dsh-codex-turn-map button::after {
  background: rgba(239, 239, 233, 0.20);
}

body[data-ds-dark-theme]
  #dsh-codex-turn-map button[aria-current="true"]::after {
  background: rgba(239, 239, 233, 0.68);
}

[class*="_logoRow"] {
  box-sizing: content-box;
  padding-top: 28px !important;
}

[class*="_brand"] {
  transform: scale(0.92);
  transform-origin: left center;
}

/* Codex uses the panel glyph as the first rail control. DSH normally swaps it
   for the fish mark until hover, which makes the collapsed state look branded
   instead of actionable. */
[class*="_frame"][data-sidebar-collapsed] [class*="_railFish"] {
  display: none !important;
}

[class*="_frame"][data-sidebar-collapsed]
  [class*="_toggle"] [class*="_panelIcon"] {
  display: inline-flex !important;
}

[class*="_frame"][data-sidebar-collapsed]
  button[class*="_newSession"]::after {
  display: none !important;
}

button[class*="_newSession"] {
  justify-content: flex-start !important;
  align-self: stretch !important;
  gap: 10px !important;
  width: 100% !important;
  max-width: 100% !important;
  min-height: 36px !important;
  height: 36px !important;
  margin: 0 0 8px !important;
  padding: 0 8px !important;
  border: 0 !important;
  border-radius: 8px !important;
  background: transparent !important;
  box-shadow: none !important;
  position: relative;
  font-size: 13px !important;
  font-weight: 500;
  transition: background 120ms ease, box-shadow 120ms ease,
              transform 120ms ease;
}

button[class*="_newSession"]:hover {
  background: var(--codex-hover) !important;
  box-shadow: none !important;
}

button[class*="_newSession"]:active {
  transform: scale(0.992);
}

button[class*="_newSession"] svg {
  display: none !important;
}

button[class*="_newSession"]::before,
button[class*="_newSession"]::after {
  content: "";
  width: 18px;
  height: 18px;
  flex: none;
  background: currentColor;
  -webkit-mask-repeat: no-repeat;
  -webkit-mask-position: center;
  -webkit-mask-size: contain;
}

button[class*="_newSession"]::before {
  -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath d='M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/%3E%3Cpath d='M18.4 2.6a2.1 2.1 0 0 1 3 3L12 15l-4 1 1-4Z' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
}

button[class*="_newSession"]::after {
  position: absolute;
  top: 10px;
  right: 12px;
  width: 16px;
  height: 16px;
  margin-left: 0;
  opacity: 0.62;
  -webkit-mask-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Ccircle cx='12' cy='12' r='9' fill='none' stroke='black' stroke-width='2'/%3E%3Cpath d='M12 8v8M8 12h8' fill='none' stroke='black' stroke-width='2' stroke-linecap='round'/%3E%3C/svg%3E");
}

body[data-ds-dark-theme] button[class*="_newSession"] {
  background: transparent !important;
}

[class*="_sectionLabel"],
[class*="_newSessionLabel"],
[class*="_projectRow"],
[class*="_sessionRow"],
[role="treeitem"] {
  font-size: 13px !important;
}

[role="treeitem"] {
  border-radius: 8px !important;
  transition: background 100ms ease;
}

[role="treeitem"][aria-selected="true"] {
  background: var(--codex-active) !important;
}

[class*="_iconButton"],
[class*="_settingsArea"] button,
[aria-label="收起侧边栏"],
[aria-label="展开侧边栏"] {
  border-radius: 8px !important;
}

/* Main surface: header, transcript and composer are one continuous plane. */
[class*="_root"][data-phase] {
  --dsh-chat-content-width: 736px !important;
  --dsh-composer-card-max-width: 736px !important;
}

[class*="_centerCol"],
[class*="_root"]:has(> div > header[class*="_header"]),
header[class*="_header"],
[class*="_scrollBody"],
[class*="_composerSeat"] {
  background: var(--codex-surface) !important;
}

header[class*="_header"] {
  box-sizing: border-box !important;
  display: flex !important;
  align-items: center !important;
  height: 46px !important;
  min-height: 46px !important;
  padding: 0 16px 0 20px !important;
  border-bottom-color: transparent !important;
  box-shadow: none !important;
}

header[class*="_header"]::after {
  bottom: 0 !important;
  background: transparent !important;
}

[class*="_root"][data-phase="active"]
  header[class*="_header"]::after {
  background: var(--codex-border-subtle) !important;
}

header[class*="_header"] [role="tablist"] {
  order: 1;
  align-self: stretch;
  align-items: center;
  gap: 24px !important;
  margin: 0 0 0 24px !important;
  padding: 0 !important;
  border: 0 !important;
}

header[class*="_header"] [role="tab"] {
  display: inline-flex;
  align-items: center;
  height: 46px;
  padding: 0 !important;
  color: var(--codex-text-tertiary) !important;
  font-size: 13px !important;
}

header[class*="_header"] [class*="_titleRow"] {
  display: contents !important;
}

header[class*="_header"] [class*="_titleCluster"] {
  order: 0;
  flex: 0 1 auto !important;
}

header[class*="_header"] [class*="_headerActions"] {
  order: 2;
  margin-left: auto;
}

header[class*="_header"] [class*="_headerUtilities"] {
  order: 3;
  margin-left: 8px !important;
}

header[class*="_header"] [role="tab"][aria-selected="true"] {
  color: var(--codex-text) !important;
}

header[class*="_header"] [role="tab"][aria-selected="true"]::after {
  height: 2px !important;
  border-radius: 999px 999px 0 0;
  background: var(--codex-text) !important;
}

header[class*="_header"] [class*="_sessionLogButton"] {
  position: absolute;
  top: 9px;
  right: 16px;
  height: 28px !important;
  border-color: var(--codex-border-subtle) !important;
  border-radius: 8px !important;
  background: var(--codex-raised) !important;
  color: var(--codex-text-secondary) !important;
  font-size: 12.5px !important;
}

header[class*="_header"] [class*="_sessionLogButton"]:hover {
  background: var(--codex-hover) !important;
  color: var(--codex-text) !important;
}

[class*="_heroGlow"] {
  display: none !important;
}

[class*="_composerStack"] {
  animation: codex-theme-arrive 320ms cubic-bezier(.2, .75, .25, 1) both;
}

[class*="_headline"] {
  margin-bottom: 4px;
}

[class*="_fishHitbox"] {
  display: none !important;
}

[class*="_headlineText"] {
  font-size: 28px !important;
  line-height: 35px !important;
  font-weight: 600 !important;
  letter-spacing: -0.025em;
}

[class*="_previewBadge"] {
  height: 20px !important;
  padding: 0 7px !important;
  border: 1px solid var(--codex-border-subtle);
  border-radius: 999px !important;
  background: var(--codex-raised) !important;
  color: var(--codex-text-tertiary) !important;
  font-size: 10px !important;
  font-weight: 500;
}

[class*="_workspace"],
[class*="_seat"] {
  border-radius: 8px !important;
  color: var(--codex-text-secondary) !important;
  font-size: 12.5px !important;
}

/* Composer: crisp border, low shadow, smaller radii and monochrome actions. */
[class*="_card"]:has(textarea) {
  border: 1px solid var(--codex-border) !important;
  border-radius: 17px !important;
  background: var(--codex-surface) !important;
  box-shadow: var(--codex-shadow) !important;
  transition: border-color 140ms ease, box-shadow 140ms ease,
              transform 140ms ease;
}

[class*="_card"]:has(textarea:focus) {
  border-color: rgba(28, 28, 26, 0.18) !important;
  box-shadow: 0 1px 2px rgba(20, 20, 18, 0.04),
              0 14px 38px rgba(20, 20, 18, 0.075) !important;
}

body[data-ds-dark-theme] [class*="_card"]:has(textarea:focus) {
  border-color: rgba(255, 255, 248, 0.2) !important;
}

[class*="_input"]::placeholder {
  color: var(--codex-text-tertiary) !important;
  opacity: 0.82;
}

/*
 * The composer renders three perfectly-overlaid text layers: the textarea
 * owns the caret, the backdrop paints visible content, and the mirror
 * determines the wrapped height. Keep their text metrics identical or the
 * caret drifts away from the painted text after longer lines wrap.
 */
textarea[class*="_input"],
[data-input-backdrop],
[data-input-mirror] {
  box-sizing: border-box !important;
  font-family: "DshChipCell", var(--codex-font) !important;
  font-size: 14px !important;
  line-height: 21px !important;
  letter-spacing: normal !important;
  white-space: pre-wrap !important;
  word-break: break-word !important;
  overflow-wrap: anywhere !important;
  padding: 4px 12px 0 16px !important;
}

[class*="_add"] {
  border-radius: 9px !important;
  background: var(--codex-raised) !important;
}

[class*="_trigger"] {
  border-radius: 8px !important;
}

[class*="_primary"] {
  border-radius: 10px !important;
  background: var(--codex-control) !important;
  color: var(--codex-control-text) !important;
  box-shadow: none !important;
}

[class*="_primary"]:hover:not(:disabled) {
  background: var(--codex-control-hover) !important;
}

[class*="_primary"]:disabled {
  background: var(--dsw-alias-button-primary-dimmed) !important;
  opacity: 0.65;
}

/* Details and menus use the same thin separators as the Codex desktop app. */
[class*="_detailsCol"] {
  background: var(--codex-surface) !important;
  border-left-color: var(--codex-border-subtle) !important;
}

[class*="_detailsCol"] [class*="_header"] {
  border-bottom-color: var(--codex-border-subtle) !important;
}

[class*="_list_"][role="menu"],
[class*="_portal"] [role="menu"] {
  border-radius: 11px !important;
  border-color: var(--codex-border-subtle) !important;
}

::-webkit-scrollbar {
  width: 7px !important;
  height: 7px !important;
}

::-webkit-scrollbar-thumb {
  background: rgba(110, 110, 104, 0.28) !important;
  border-radius: 999px !important;
}

@keyframes codex-theme-arrive {
  from { opacity: 0; transform: translateY(5px); }
  to   { opacity: 1; transform: translateY(0); }
}

@media (prefers-reduced-motion: reduce) {
  [class*="_composerStack"] { animation: none; }
  *, *::before, *::after { transition-duration: 0.01ms !important; }
}
"""#

func makeCodexThemeInjectionScript() -> String {
    let encoded = try! JSONSerialization.data(withJSONObject: [codexThemeCSS])
    let cssArray = String(data: encoded, encoding: .utf8)!

    return #"""
    (() => {
      if (document.getElementById('dsh-codex-theme')) return;
      const style = document.createElement('style');
      style.id = 'dsh-codex-theme';
      style.textContent = \#(cssArray)[0];
      document.documentElement.dataset.desktopShell = 'codex';

      let headObserver;
      const keepThemeLast = () => {
        const head = document.head;
        if (!head) {
          requestAnimationFrame(keepThemeLast);
          return;
        }
        if (style.parentNode !== head || style !== head.lastElementChild) {
          head.appendChild(style);
        }
        if (!headObserver) {
          headObserver = new MutationObserver(() => {
            if (style !== head.lastElementChild) head.appendChild(style);
          });
          headObserver.observe(head, { childList: true });
        }
      };

      let turnMap = null;
      let turnMapScrollport = null;
      let turnMapSignature = '';
      let turnMapFrame = 0;

      const userTurnAnchors = () => Array.from(document.querySelectorAll(
        '[data-chat-flow-kind="user"][data-chat-anchor-key]'
      )).filter((anchor) => anchor.getClientRects().length > 0);

      const updateTurnMapActiveState = () => {
        if (!turnMap || !turnMapScrollport) return;
        const anchors = userTurnAnchors();
        const marks = Array.from(turnMap.querySelectorAll('button'));
        if (anchors.length === 0 || marks.length !== anchors.length) return;

        const floor = Math.max(
          0,
          turnMapScrollport.scrollHeight - turnMapScrollport.clientHeight
        );
        let activeIndex = 0;
        if (floor - turnMapScrollport.scrollTop <= 25) {
          activeIndex = anchors.length - 1;
        } else {
          const viewport = turnMapScrollport.getBoundingClientRect();
          const readingLine = viewport.top + Math.min(120, viewport.height * 0.28);
          for (let index = 0; index < anchors.length; index += 1) {
            if (anchors[index].getBoundingClientRect().top <= readingLine) {
              activeIndex = index;
            } else {
              break;
            }
          }
        }

        marks.forEach((mark, index) => {
          if (index === activeIndex) {
            mark.setAttribute('aria-current', 'true');
          } else {
            mark.removeAttribute('aria-current');
          }
        });
      };

      const onTurnMapScroll = () => {
        if (turnMapFrame) return;
        turnMapFrame = requestAnimationFrame(() => {
          turnMapFrame = 0;
          updateTurnMapActiveState();
        });
      };

      const rebuildTurnMap = () => {
        const frame = document.querySelector('[class*="_frame"]');
        const scrollport = document.querySelector('[data-conversation-scroll]');
        if (!frame || !scrollport) {
          if (turnMap) turnMap.hidden = true;
          return;
        }

        if (!turnMap) {
          turnMap = document.createElement('nav');
          turnMap.id = 'dsh-codex-turn-map';
          turnMap.setAttribute('aria-label', '会话导航');
        }
        if (turnMap.parentElement !== frame) frame.appendChild(turnMap);

        if (turnMapScrollport !== scrollport) {
          turnMapScrollport?.removeEventListener('scroll', onTurnMapScroll);
          turnMapScrollport = scrollport;
          turnMapScrollport.addEventListener(
            'scroll',
            onTurnMapScroll,
            { passive: true }
          );
        }

        const anchors = userTurnAnchors();
        const signature = anchors.map(
          (anchor) => anchor.dataset.chatAnchorKey || ''
        ).join('|');
        turnMap.hidden = frame.hasAttribute('data-sidebar-collapsed') ||
          anchors.length === 0;

        if (signature !== turnMapSignature) {
          turnMapSignature = signature;
          turnMap.replaceChildren(...anchors.map((anchor, index) => {
            const mark = document.createElement('button');
            mark.type = 'button';
            mark.title = `第 ${index + 1} 条用户消息`;
            mark.setAttribute('aria-label', mark.title);
            mark.addEventListener('click', () => {
              const viewport = scrollport.getBoundingClientRect();
              const targetTop = anchor.getBoundingClientRect().top - viewport.top;
              scrollport.scrollTo({
                top: scrollport.scrollTop + targetTop - 24,
                behavior: 'smooth'
              });
            });
            return mark;
          }));
        }

        const sidebarWidth = Number.parseFloat(
          frame.dataset.codexSidebarWidth || ''
        );
        if (Number.isFinite(sidebarWidth)) {
          turnMap.style.left = `${
            frame.getBoundingClientRect().left + sidebarWidth + 10
          }px`;
        }
        updateTurnMapActiveState();
      };

      const scheduleTurnMap = () => {
        if (turnMapFrame) return;
        turnMapFrame = requestAnimationFrame(() => {
          turnMapFrame = 0;
          rebuildTurnMap();
        });
      };

      // DSH's native sidebar contract is 280px by default and 264...420px while
      // dragging. Display it 24px narrower so the default matches Codex (256px)
      // without disabling the native resize interaction. React rewrites all
      // three inline widths on each drag frame, so retain the native value in a
      // data attribute and keep the grid, root, and handle synchronized.
      const normalizeFrame = (frame) => {
        const sidebarCol = frame.querySelector(':scope > [class*="_sidebarCol"]');
        const centerCol = frame.querySelector(':scope > [class*="_centerCol"]');
        if (!sidebarCol || !centerCol) return;
        const collapsed = frame.hasAttribute('data-sidebar-collapsed');
        const columns = frame.style.gridTemplateColumns;
        const rawWidth = Number.parseFloat(columns);
        const previousDisplayWidth = Number.parseFloat(
          frame.dataset.codexSidebarWidth || ''
        );
        let nativeWidth = Number.parseFloat(
          frame.dataset.codexNativeSidebarWidth || ''
        );

        if (!collapsed && Number.isFinite(rawWidth) &&
            (!Number.isFinite(previousDisplayWidth) ||
             Math.abs(rawWidth - previousDisplayWidth) > 0.5)) {
          nativeWidth = rawWidth;
        }
        if (!Number.isFinite(nativeWidth)) nativeWidth = 280;

        const sidebarWidth = collapsed
          ? 56
          : Math.max(240, Math.min(396, nativeWidth - 24));
        frame.dataset.codexNativeSidebarWidth = `${nativeWidth}`;
        frame.dataset.codexSidebarWidth = `${sidebarWidth}`;

        const sidebarRoot = Array.from(
          sidebarCol.querySelectorAll('[class*="_root"]')
        ).find((candidate) =>
          candidate.querySelector('button[class*="_newSession"]')
        );
        if (sidebarRoot &&
            sidebarRoot.style.getPropertyValue('width') !== `${sidebarWidth}px`) {
          sidebarRoot.style.setProperty('width', `${sidebarWidth}px`, 'important');
        }

        const sidebarHandle = frame.querySelector(
          ':scope > [class*="_handle"][data-side="sidebar"]'
        );
        if (sidebarHandle &&
            sidebarHandle.style.getPropertyValue('left') !== `${sidebarWidth}px`) {
          sidebarHandle.style.setProperty('left', `${sidebarWidth}px`, 'important');
        }

        const detailsMatch = columns.match(/([0-9.]+)px\s*$/);
        if (detailsMatch) {
          frame.style.setProperty(
            '--codex-details-width',
            `${detailsMatch[1]}px`
          );
        } else if (!frame.style.getPropertyValue('--codex-details-width')) {
          frame.style.setProperty('--codex-details-width', '0px');
        }

        const targetColumns =
          `${sidebarWidth}px minmax(0, 1fr) var(--codex-details-width)`;
        if (columns !== targetColumns) {
          frame.style.setProperty(
            'grid-template-columns',
            targetColumns,
            'important'
          );
        }

        scheduleTurnMap();
      };

      const normalizeFrames = () => {
        document.querySelectorAll('[class*="_frame"]').forEach(normalizeFrame);
      };
      const layoutObserver = new MutationObserver(() => {
        normalizeFrames();
        scheduleTurnMap();
      });
      layoutObserver.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['style', 'data-sidebar-collapsed']
      });

      keepThemeLast();
      normalizeFrames();
      scheduleTurnMap();
    })();
    """#
}
