import type { ExtMessage, ExtResponse, Provider, ModelInfo } from "../shared/types.js";

const PROVIDERS: Provider[] = ["anthropic", "openai"];

// ── Helpers ────────────────────────────────────────────────────────────────

function el<T extends HTMLElement>(id: string): T {
  return document.getElementById(id) as T;
}

function setBadge(provider: Provider, connected: boolean): void {
  const badge = el(`badge-${provider}`);
  badge.textContent = connected ? "Connected ✓" : "Not connected";
  badge.className = connected ? "badge-connected" : "badge-disconnected";
}

function setError(provider: Provider, msg: string | null): void {
  const errEl = el(`err-${provider}`);
  errEl.textContent = msg ?? "";
  errEl.classList.toggle("visible", !!msg);
}

function showRemoveButton(provider: Provider, show: boolean): void {
  el(`save-${provider}`).style.display = show ? "none" : "";
  el(`remove-${provider}`).style.display = show ? "" : "none";
  const input = el<HTMLInputElement>(`key-${provider}`);
  if (show) {
    input.value = "";
    input.placeholder = "••••••••••••••••••••";
    input.disabled = true;
  } else {
    input.placeholder = provider === "anthropic" ? "sk-ant-api03-…" : "sk-proj-…";
    input.disabled = false;
  }
}

// ── Load current status ────────────────────────────────────────────────────

async function loadStatus(): Promise<void> {
  const msg: ExtMessage = { type: "GET_AUTH_STATUS" };
  chrome.runtime.sendMessage(msg, (res: ExtResponse) => {
    if (res.type !== "AUTH_STATUS") return;
    for (const s of res.statuses) {
      setBadge(s.provider, s.connected);
      showRemoveButton(s.provider, s.connected);
      if (s.connected) loadModelsForProvider(s.provider);
    }
  });
}

// ── Save key ───────────────────────────────────────────────────────────────

async function saveKey(provider: Provider): Promise<void> {
  const btn = el<HTMLButtonElement>(`save-${provider}`);
  const input = el<HTMLInputElement>(`key-${provider}`);
  const apiKey = input.value.trim();

  if (!apiKey) {
    setError(provider, "Please enter an API key.");
    return;
  }

  setError(provider, null);
  btn.disabled = true;
  btn.innerHTML = `<span class="spinner"></span>Validating…`;

  const msg: ExtMessage = { type: "SAVE_API_KEY", provider, apiKey };
  chrome.runtime.sendMessage(msg, (res: ExtResponse) => {
    btn.disabled = false;
    btn.textContent = "Save";

    if (res.type === "SAVE_API_KEY_ERR") {
      setError(provider, res.error);
    } else if (res.type === "SAVE_API_KEY_OK") {
      setBadge(provider, true);
      showRemoveButton(provider, true);
      loadModelsForProvider(provider);  // populate dropdown with real model IDs
    }
  });
}

// ── Remove key ─────────────────────────────────────────────────────────────

function removeKey(provider: Provider): void {
  if (!confirm(`Remove your ${provider === "anthropic" ? "Anthropic" : "OpenAI"} API key?`)) return;
  const msg: ExtMessage = { type: "DISCONNECT", provider };
  chrome.runtime.sendMessage(msg, () => {
    setBadge(provider, false);
    showRemoveButton(provider, false);
    setError(provider, null);
  });
}

// ── Model loading ──────────────────────────────────────────────────────────

const MODEL_SELECT_IDS: Record<Provider, string> = {
  anthropic: "anthropicModel",
  openai: "openaiModel",
};

async function loadModelsForProvider(provider: Provider): Promise<void> {
  const selectEl = el<HTMLSelectElement>(MODEL_SELECT_IDS[provider]);
  selectEl.disabled = true;

  const savedValue = selectEl.value;
  const msg: ExtMessage = { type: "GET_MODELS", provider };

  chrome.runtime.sendMessage(msg, (res: ExtResponse) => {
    selectEl.disabled = false;
    if (res.type !== "MODELS_OK" || res.models.length === 0) return;

    // Rebuild options with real model IDs from the API
    selectEl.innerHTML = "";
    res.models.forEach((m: ModelInfo) => {
      const opt = document.createElement("option");
      opt.value = m.id;
      opt.textContent = m.displayName;
      selectEl.appendChild(opt);
    });

    // Restore previously saved selection if it still exists
    if (savedValue && Array.from(selectEl.options).some((o) => o.value === savedValue)) {
      selectEl.value = savedValue;
    }
  });
}

// ── Model settings ─────────────────────────────────────────────────────────

async function loadModels(): Promise<void> {
  const { settings } = await chrome.storage.local.get("settings");
  if (!settings) return;
  const am = el<HTMLSelectElement>("anthropicModel");
  const om = el<HTMLSelectElement>("openaiModel");
  if (settings.anthropicModel) am.value = settings.anthropicModel;
  if (settings.openaiModel) om.value = settings.openaiModel;
}

el("saveModels").addEventListener("click", async () => {
  const { settings = {} } = await chrome.storage.local.get("settings");
  await chrome.storage.local.set({
    settings: {
      ...settings,
      anthropicModel: el<HTMLSelectElement>("anthropicModel").value,
      openaiModel: el<HTMLSelectElement>("openaiModel").value,
    },
  });
  const ok = el("saveMsgModels");
  ok.classList.add("visible");
  setTimeout(() => ok.classList.remove("visible"), 2000);
});

// ── Wire up buttons ────────────────────────────────────────────────────────

for (const p of PROVIDERS) {
  el(`save-${p}`).addEventListener("click", () => saveKey(p));
  el(`remove-${p}`).addEventListener("click", () => removeKey(p));
  el<HTMLInputElement>(`key-${p}`).addEventListener("keydown", (e) => {
    if (e.key === "Enter") saveKey(p);
  });
}

// ── Init ──────────────────────────────────────────────────────────────────

loadStatus();
loadModels();
