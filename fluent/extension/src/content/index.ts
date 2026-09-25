/**
 * Fluent content script.
 * Attaches to every text field on the page and detects trigger commands.
 */
import { detectTrigger } from "../shared/triggers.js";
import type { ExtMessage, ExtResponse, CorrectResult } from "../shared/types.js";
import { SuggestionOverlay } from "./overlay.js";
import { injectText, clearField } from "./injector.js";

console.log("[fluent] content script loaded on", location.hostname);

// ── Field detection ────────────────────────────────────────────────────────

function isPasswordField(el: Element): boolean {
  return el instanceof HTMLInputElement && el.type === "password";
}

function getFieldText(el: Element): string {
  if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
    return el.value;
  }
  if ((el as HTMLElement).isContentEditable) {
    return (el as HTMLElement).innerText ?? "";
  }
  return "";
}

// ── Attach listeners ───────────────────────────────────────────────────────

const ATTR = "data-fluent";

function attachListener(el: Element): void {
  if (isPasswordField(el)) return;
  if (el.hasAttribute(ATTR)) return;
  el.setAttribute(ATTR, "1");

  // `input` fires on every keystroke in native fields
  el.addEventListener("input", () => handleInput(el));

  // Fallback: also check on keyup so React/Vue controlled inputs are caught
  el.addEventListener("keyup", () => handleInput(el));

  console.log("[fluent] attached to", el.tagName, (el as HTMLElement).id || (el as HTMLElement).className?.slice?.(0, 30) || "");
}

function scanAndAttach(root: Document | Element = document): void {
  root.querySelectorAll<Element>("input:not([type=password]):not([type=email]):not([type=number]), textarea, [contenteditable='true'], [contenteditable='']").forEach(attachListener);
}

scanAndAttach();

// Watch for dynamically added elements (SPAs)
new MutationObserver((mutations) => {
  for (const m of mutations) {
    m.addedNodes.forEach((node) => {
      if (node instanceof Element) {
        if (node.matches("input, textarea, [contenteditable]")) attachListener(node);
        else scanAndAttach(node);
      }
    });
  }
}).observe(document.body ?? document.documentElement, { childList: true, subtree: true });

// Also scan after a short delay in case the page renders async
setTimeout(() => scanAndAttach(), 1000);

// ── Trigger handling ───────────────────────────────────────────────────────

let activeField: Element | null = null;
let originalText = "";
let activeOverlay: SuggestionOverlay | null = null;
let pendingCorrected: string | null = null;
let lastChecked = "";

function handleInput(el: Element): void {
  const text = getFieldText(el);

  // Debounce: skip if value hasn't changed
  if (text === lastChecked) return;
  lastChecked = text;

  const result = detectTrigger(text);
  if (!result.matched) return;
  if (activeOverlay) return; // already processing

  console.log("[fluent] trigger detected:", result.mode, "| text:", result.text.slice(0, 60));

  originalText = result.text;
  activeField = el;
  pendingCorrected = null;

  // Leave the field untouched while waiting — only replace on explicit Accept/Reject
  const overlay = new SuggestionOverlay({
    anchorEl: el,
    onAccept: () => {
      if (activeField) injectText(activeField, pendingCorrected ?? originalText);
      reset();
    },
    onReject: () => {
      // Strip the trigger command but keep the original text
      if (activeField) injectText(activeField, originalText);
      reset();
    },
    onOpenSettings: () => {
      chrome.runtime.sendMessage({ type: "GET_AUTH_STATUS" }); // wake SW
      chrome.runtime.openOptionsPage();
    },
  });

  overlay.render({ phase: "loading", mode: result.mode });
  activeOverlay = overlay;

  const msg: ExtMessage = { type: "CORRECT", text: result.text, mode: result.mode };
  chrome.runtime.sendMessage(msg, (response: ExtResponse) => {
    if (chrome.runtime.lastError) {
      console.error("[fluent] runtime error:", chrome.runtime.lastError.message);
      activeOverlay?.render({ phase: "error", message: "Extension error — try reloading the page.", notConnected: false });
      // Field is still intact — no restore needed
      return;
    }
    if (!activeOverlay) return;

    if (response.type === "CORRECT_OK") {
      pendingCorrected = response.result.corrected;
      activeOverlay.render({ phase: "suggestion", mode: result.mode, diff: response.result.diff });
    } else if (response.type === "CORRECT_ERR") {
      console.warn("[fluent] correction error:", response.error);
      activeOverlay.render({ phase: "error", message: response.error, notConnected: response.notConnected });
      // Field is still intact — no restore needed
    }
  });
}

function reset(): void {
  activeField = null;
  originalText = "";
  activeOverlay = null;
  pendingCorrected = null;
  lastChecked = "";
}
