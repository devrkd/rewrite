// Firefox exposes the API as `browser`; Chrome uses `chrome`. Normalise to `chrome`.
declare const browser: typeof chrome | undefined;
if (typeof chrome === "undefined" && typeof browser !== "undefined") {
  (globalThis as any).chrome = browser;
}

import type { ExtMessage, ExtResponse, Provider } from "../shared/types.js";
import { correctText, NotConnectedError } from "./providers.js";
import { computeDiff } from "../shared/diff.js";
import { saveApiKey, validateApiKey, deleteToken, getAllStatuses, fetchModels } from "./auth.js";

// ── Message handler ────────────────────────────────────────────────────────

chrome.runtime.onMessage.addListener(
  (message: ExtMessage, _sender, sendResponse: (r: ExtResponse) => void) => {
    handleMessage(message).then(sendResponse).catch((err) => {
      console.error("[fluent-sw]", err);
      sendResponse({ type: "CORRECT_ERR", error: String(err) });
    });
    return true;
  }
);

async function handleMessage(msg: ExtMessage): Promise<ExtResponse> {
  switch (msg.type) {
    case "CORRECT": {
      try {
        const corrected = await correctText(msg.text, msg.mode);
        return {
          type: "CORRECT_OK",
          result: {
            original: msg.text,
            corrected,
            diff: computeDiff(msg.text, corrected),
          },
        };
      } catch (err) {
        return {
          type: "CORRECT_ERR",
          error: (err as Error).message,
          notConnected: err instanceof NotConnectedError,
        };
      }
    }

    case "GET_AUTH_STATUS": {
      const statuses = await getAllStatuses();
      return { type: "AUTH_STATUS", statuses };
    }

    case "SAVE_API_KEY": {
      const validationError = await validateApiKey(msg.provider as Provider, msg.apiKey);
      if (validationError) {
        return { type: "SAVE_API_KEY_ERR", provider: msg.provider as Provider, error: validationError };
      }
      await saveApiKey(msg.provider as Provider, msg.apiKey);
      return { type: "SAVE_API_KEY_OK", provider: msg.provider as Provider };
    }

    case "GET_MODELS": {
      try {
        const models = await fetchModels(msg.provider as Provider);
        return { type: "MODELS_OK", provider: msg.provider as Provider, models };
      } catch (err) {
        return { type: "MODELS_ERR", provider: msg.provider as Provider, error: (err as Error).message };
      }
    }

    case "DISCONNECT": {
      await deleteToken(msg.provider as Provider);
      return { type: "DISCONNECT_OK", provider: msg.provider as Provider };
    }
  }
}

// ── Install lifecycle ──────────────────────────────────────────────────────

chrome.runtime.onInstalled.addListener(({ reason }) => {
  if (reason === "install") {
    chrome.tabs.create({ url: chrome.runtime.getURL("options/index.html") });
  }
});

console.log("[fluent-sw] Service worker started.");
