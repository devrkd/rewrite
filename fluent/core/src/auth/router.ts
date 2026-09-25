import { Router, type Request, type Response } from "express";
import { z } from "zod";
import { ProviderSchema } from "../types.js";
import { startFlow, handleCallback } from "./flow.js";
import { getToken, deleteToken, getAllStatus } from "./store.js";

export const authRouter = Router();

// GET /auth/status
// Returns connection status for every provider.
authRouter.get("/status", (_req: Request, res: Response) => {
  const statuses = getAllStatus();
  const detailed = Object.entries(statuses).map(([provider, connected]) => {
    const token = connected ? getToken(provider as any) : null;
    return {
      provider,
      connected,
      accountEmail: token?.accountEmail ?? null,
      accountName: token?.accountName ?? null,
      connectedAt: token?.connectedAt ?? null,
    };
  });
  res.json({ providers: detailed });
});

// GET /auth/start/:provider
// Returns the authorization URL for the user to open in their browser.
authRouter.get("/start/:provider", (req: Request, res: Response) => {
  const parsed = ProviderSchema.safeParse(req.params.provider);
  if (!parsed.success) {
    res.status(400).json({ error: `Unknown provider: ${req.params.provider}`, code: "UNKNOWN_PROVIDER" });
    return;
  }

  try {
    const result = startFlow(parsed.data);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message, code: "FLOW_START_ERROR" });
  }
});

// GET /auth/:provider/callback
// Receives the redirect from the provider after the user authorizes.
// The browser lands here; we exchange the code and show a success page.
authRouter.get("/:provider/callback", async (req: Request, res: Response) => {
  const { code, state, error, error_description } = req.query as Record<string, string>;

  if (error) {
    res.status(400).send(renderPage("Connection failed", `
      <p class="error">The provider returned an error:</p>
      <pre>${escapeHtml(error_description ?? error)}</pre>
      <p>You can close this tab and try again.</p>
    `));
    return;
  }

  if (!code || !state) {
    res.status(400).send(renderPage("Bad request", `<p class="error">Missing code or state parameter.</p>`));
    return;
  }

  try {
    const result = await handleCallback(code, state);
    const name = result.accountName ?? result.accountEmail ?? result.provider;
    res.send(renderPage("Connected!", `
      <div class="check">✓</div>
      <h2>Connected as ${escapeHtml(name)}</h2>
      <p>Fluent is now authorized to use your <strong>${escapeHtml(result.provider)}</strong> account.</p>
      <p class="muted">You can close this tab and return to Fluent.</p>
    `));
  } catch (err) {
    res.status(400).send(renderPage("Connection failed", `
      <p class="error">${escapeHtml((err as Error).message)}</p>
      <p>You can close this tab and try again from the Fluent settings.</p>
    `));
  }
});

// DELETE /auth/:provider
// Disconnects a provider (deletes its stored token).
authRouter.delete("/:provider", (req: Request, res: Response) => {
  const parsed = ProviderSchema.safeParse(req.params.provider);
  if (!parsed.success) {
    res.status(400).json({ error: `Unknown provider`, code: "UNKNOWN_PROVIDER" });
    return;
  }
  deleteToken(parsed.data);
  res.json({ ok: true });
});

// MARK: - Helpers

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function renderPage(title: string, body: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Fluent — ${escapeHtml(title)}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #0f0f10;
      color: #e8e8ea;
      display: flex; align-items: center; justify-content: center;
      min-height: 100vh; padding: 2rem;
    }
    .card {
      background: #1a1a1f;
      border: 1px solid #2a2a30;
      border-radius: 16px;
      padding: 2.5rem 3rem;
      max-width: 480px;
      width: 100%;
      text-align: center;
    }
    .logo { font-size: 2rem; margin-bottom: 1rem; }
    h1 { font-size: 1.5rem; margin-bottom: 1.5rem; color: #f5f5f7; }
    h2 { font-size: 1.2rem; margin-bottom: 0.75rem; color: #f5f5f7; }
    p { color: #9999a8; line-height: 1.6; margin-bottom: 0.75rem; }
    .check {
      font-size: 3rem; color: #34c759;
      margin-bottom: 1rem;
    }
    .error { color: #ff453a; }
    .muted { font-size: 0.85rem; color: #55555f; }
    pre {
      background: #111115; border-radius: 8px;
      padding: 0.75rem 1rem; text-align: left;
      font-size: 0.8rem; color: #ff453a;
      margin: 0.75rem 0; overflow-x: auto;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">𝕄</div>
    <h1>${escapeHtml(title)}</h1>
    ${body}
  </div>
</body>
</html>`;
}
