import type { ExtMessage, ExtResponse, ProviderStatus } from "../shared/types.js";

const PROVIDER_META: Record<string, { icon: string; name: string }> = {
  anthropic: { icon: "✦", name: "Claude (Anthropic)" },
  openai:    { icon: "⬡", name: "ChatGPT (OpenAI)" },
};

async function getStatuses(): Promise<ProviderStatus[]> {
  return new Promise((resolve) => {
    const msg: ExtMessage = { type: "GET_AUTH_STATUS" };
    chrome.runtime.sendMessage(msg, (res: ExtResponse) => {
      resolve(res.type === "AUTH_STATUS" ? res.statuses : []);
    });
  });
}

async function render(): Promise<void> {
  const statuses = await getStatuses();
  const list = document.getElementById("providerList")!;
  list.innerHTML = "";

  const anyConnected = statuses.some((s) => s.connected);

  for (const status of statuses) {
    const meta = PROVIDER_META[status.provider];
    if (!meta) continue;

    const row = document.createElement("div");
    row.className = "provider-row";
    row.innerHTML = `
      <span class="provider-icon">${meta.icon}</span>
      <span class="provider-name">${meta.name}</span>
      <span class="${status.connected ? "badge-connected" : "badge-disconnected"}">
        ${status.connected ? "Connected ✓" : "No key"}
      </span>
    `;
    list.appendChild(row);
  }

  // Show prompt to open settings if nothing connected
  const hint = document.getElementById("hint")!;
  hint.style.display = anyConnected ? "none" : "block";
}

function openSettings() { chrome.runtime.openOptionsPage(); window.close(); }
document.getElementById("settingsLink")?.addEventListener("click", openSettings);
document.getElementById("settingsLink2")?.addEventListener("click", openSettings);

render();
