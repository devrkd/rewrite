/**
 * Floating suggestion overlay rendered in a Shadow DOM — fully isolated
 * from the host page's styles.
 */
import type { DiffSegment } from "../shared/types.js";

const CSS = `
  :host {
    all: initial;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    font-size: 14px;
    color: #e8e8ea;
  }
  .panel {
    position: fixed;
    z-index: 2147483647;
    max-height: 420px;
    background: #1a1a1f;
    border: 1px solid #2e2e36;
    border-radius: 14px;
    box-shadow: 0 24px 64px rgba(0,0,0,0.6);
    display: flex;
    flex-direction: column;
    overflow: hidden;
    animation: slide-in 0.16s ease-out;
  }
  @keyframes slide-in {
    from { opacity: 0; transform: translateY(12px); }
    to   { opacity: 1; transform: translateY(0); }
  }
  .header {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 14px 16px 10px;
    border-bottom: 1px solid #2e2e36;
    flex-shrink: 0;
  }
  .logo { font-size: 1.1em; font-weight: 700; color: #f5f5f7; letter-spacing: -0.3px; }
  .mode-badge {
    font-size: 11px;
    font-weight: 600;
    padding: 2px 8px;
    border-radius: 20px;
    background: #2e2e3e;
    color: #a0a0bf;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }
  .spinner {
    display: inline-block;
    width: 14px; height: 14px;
    border: 2px solid #3a3a4a;
    border-top-color: #6e6ef0;
    border-radius: 50%;
    animation: spin 0.7s linear infinite;
    margin-left: auto;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
  .body {
    overflow-y: auto;
    padding: 14px 16px;
    line-height: 1.6;
    flex: 1;
    min-height: 0;
  }
  .diff-view { white-space: pre-wrap; word-break: break-word; }
  .ins {
    color: #4ade80;
    background: rgba(74,222,128,0.12);
    border-radius: 3px;
    text-decoration: underline;
    text-decoration-color: rgba(74,222,128,0.5);
  }
  .del {
    color: #f87171;
    background: rgba(248,113,113,0.1);
    border-radius: 3px;
    text-decoration: line-through;
    text-decoration-color: rgba(248,113,113,0.6);
  }
  .error-msg { color: #f87171; padding: 12px 0; }
  .not-connected-msg { color: #facc15; padding: 12px 0; }
  .footer {
    display: flex;
    gap: 8px;
    padding: 10px 16px 14px;
    border-top: 1px solid #2e2e36;
    flex-shrink: 0;
    justify-content: flex-end;
  }
  button {
    cursor: pointer;
    border: none;
    border-radius: 8px;
    font-size: 13px;
    font-weight: 500;
    padding: 7px 16px;
    transition: opacity 0.1s;
  }
  button:hover { opacity: 0.85; }
  .btn-reject {
    background: #2e2e36;
    color: #a0a0bf;
  }
  .btn-accept {
    background: #6e6ef0;
    color: #fff;
  }
  .btn-settings {
    background: #2e2e36;
    color: #facc15;
  }
`;

export type OverlayState =
  | { phase: "loading"; mode: string }
  | { phase: "suggestion"; mode: string; diff: DiffSegment[] }
  | { phase: "error"; message: string; notConnected?: boolean }

export class SuggestionOverlay {
  private host: HTMLElement;
  private shadow: ShadowRoot;
  private onAccept: () => void;
  private onReject: () => void;
  private onOpenSettings: () => void;
  private anchorEl: Element;

  constructor(opts: {
    anchorEl: Element;
    onAccept: () => void;
    onReject: () => void;
    onOpenSettings: () => void;
  }) {
    this.onAccept = opts.onAccept;
    this.onReject = opts.onReject;
    this.onOpenSettings = opts.onOpenSettings;
    this.anchorEl = opts.anchorEl;

    this.host = document.createElement("div");
    this.host.id = "fluent-overlay-host";
    this.shadow = this.host.attachShadow({ mode: "closed" });

    const style = document.createElement("style");
    style.textContent = CSS;
    this.shadow.appendChild(style);

    document.documentElement.appendChild(this.host);
  }

  render(state: OverlayState): void {
    // Remove old panel if present
    this.shadow.querySelector(".panel")?.remove();

    const panel = document.createElement("div");
    panel.className = "panel";

    // Header
    const header = document.createElement("div");
    header.className = "header";
    header.innerHTML = `<span class="logo">Fluent</span>`;

    if (state.phase !== "error") {
      const badge = document.createElement("span");
      badge.className = "mode-badge";
      badge.textContent = `/${state.mode}`;
      header.appendChild(badge);
    }

    if (state.phase === "loading") {
      const spinner = document.createElement("span");
      spinner.className = "spinner";
      header.appendChild(spinner);
    }

    // Body
    const body = document.createElement("div");
    body.className = "body";

    if (state.phase === "loading") {
      body.textContent = "Thinking…";

    } else if (state.phase === "suggestion") {
      const diffView = document.createElement("div");
      diffView.className = "diff-view";
      for (const seg of state.diff) {
        if (seg.type === "equal") {
          diffView.appendChild(document.createTextNode(seg.value));
        } else {
          const span = document.createElement("span");
          span.className = seg.type === "insert" ? "ins" : "del";
          span.textContent = seg.value;
          diffView.appendChild(span);
        }
      }
      body.appendChild(diffView);

    } else if (state.phase === "error") {
      const p = document.createElement("p");
      p.className = state.notConnected ? "not-connected-msg" : "error-msg";
      p.textContent = state.message;
      body.appendChild(p);
    }

    // Footer
    const footer = document.createElement("div");
    footer.className = "footer";

    if (state.phase === "suggestion") {
      const reject = document.createElement("button");
      reject.className = "btn-reject";
      reject.textContent = "Reject";
      reject.addEventListener("click", () => { this.dismiss(); this.onReject(); });

      const accept = document.createElement("button");
      accept.className = "btn-accept";
      accept.textContent = "Accept ↩";
      accept.addEventListener("click", () => { this.dismiss(); this.onAccept(); });

      footer.appendChild(reject);
      footer.appendChild(accept);

    } else if (state.phase === "error") {
      const dismiss = document.createElement("button");
      dismiss.className = "btn-reject";
      dismiss.textContent = "Dismiss";
      dismiss.addEventListener("click", () => this.dismiss());

      footer.appendChild(dismiss);

      if (state.notConnected) {
        const settings = document.createElement("button");
        settings.className = "btn-settings";
        settings.textContent = "Connect account →";
        settings.addEventListener("click", () => { this.dismiss(); this.onOpenSettings(); });
        footer.appendChild(settings);
      }
    }

    panel.appendChild(header);
    panel.appendChild(body);
    if (state.phase !== "loading") panel.appendChild(footer);

    // Dismiss on Escape
    const keyHandler = (e: KeyboardEvent) => {
      if (e.key === "Escape") { this.dismiss(); this.onReject(); }
    };
    document.addEventListener("keydown", keyHandler, { once: true });

    this.shadow.appendChild(panel);
    this.positionPanel(panel);
  }

  /** Position the panel near the anchor element, preferring below it. */
  private positionPanel(panel: HTMLDivElement): void {
    const rect = this.anchorEl.getBoundingClientRect();
    const vw  = window.innerWidth;
    const vh  = window.innerHeight;
    const gap = 10;
    const panelWidth  = Math.min(480, vw - 32);
    const panelHeight = 320; // estimated; panel may be shorter

    // Horizontal: align to anchor's left edge, clamp inside viewport
    let left = rect.left;
    if (left + panelWidth > vw - 16) left = vw - panelWidth - 16;
    left = Math.max(16, left);

    // Vertical: prefer below, fall back to above if there's more room
    const spaceBelow = vh - rect.bottom - gap;
    const spaceAbove = rect.top - gap;
    let top: number;

    if (spaceBelow >= Math.min(panelHeight, 160) || spaceBelow >= spaceAbove) {
      top = rect.bottom + gap;
    } else {
      // Position above — anchor to real panel height after render
      top = rect.top - gap;
      panel.style.bottom = `${vh - top}px`;
      panel.style.top    = "auto";
      panel.style.left   = `${left}px`;
      panel.style.width  = `${panelWidth}px`;
      return;
    }

    panel.style.top    = `${top}px`;
    panel.style.bottom = "auto";
    panel.style.left   = `${left}px`;
    panel.style.width  = `${panelWidth}px`;
  }

  dismiss(): void {
    this.host.remove();
  }
}
