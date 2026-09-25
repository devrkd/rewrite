/**
 * Injects text back into an input / textarea / contenteditable element,
 * placing the cursor at the end.
 */
export function injectText(el: Element, text: string): void {
  if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
    const nativeInput = Object.getOwnPropertyDescriptor(
      el instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype,
      "value"
    );
    nativeInput?.set?.call(el, text);
    el.dispatchEvent(new Event("input", { bubbles: true }));
    el.dispatchEvent(new Event("change", { bubbles: true }));
    // Move cursor to end
    el.setSelectionRange(text.length, text.length);
  } else if ((el as HTMLElement).isContentEditable) {
    (el as HTMLElement).textContent = text;
    el.dispatchEvent(new Event("input", { bubbles: true }));
    // Move cursor to end
    const range = document.createRange();
    const sel = window.getSelection();
    if (el.lastChild) {
      range.setStartAfter(el.lastChild);
      range.collapse(true);
      sel?.removeAllRanges();
      sel?.addRange(range);
    }
  }
}

/** Clears the field (used while the API call is in-flight). */
export function clearField(el: Element): void {
  injectText(el, "");
}
