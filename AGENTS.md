# AGENTS.md

## Project Overview
An AI-powered writing assistant that fixes spelling and grammar mistakes, and rewrites text, **on explicit user command** (not ambient/real-time like Grammarly). The user types normally and triggers a correction by typing a command string (e.g. `/fixit`, `/rewrite`) at the end of their text.

## Goals
- Let the user type a command suffix after their text to trigger an AI edit.
- Detect the command, strip it, send the preceding text to an LLM, and replace it with the corrected/rewritten version.
- Support multiple LLM backends (Claude, ChatGPT, Gemini) behind a common interface.
- Start with OS-wide support (via accessibility APIs) so the trigger works across applications, not just the browser.
- Build the shared logic (AI calls, prompting, diffing, account linking) once, so the same capability can be extended to macOS, Windows, and a browser extension without duplicating core logic per platform.

## Architecture (Cross-Platform Strategy)
To support macOS first, then Windows, then a browser extension, the project should be split into two layers:

### Shared Core
A platform-independent service/library containing everything that doesn't depend on OS-specific APIs:
- LLM provider abstraction (`correctText(text, mode)`), prompt templates per trigger mode.
- Diffing logic for confirm-first suggestions.
- Account linking / API key management logic.
- Caching, max-length enforcement, error handling/retry logic.

This should be implemented once (e.g. as a small local service exposed over HTTP/IPC, or as a library compiled/bound into each client) so platform clients never re-implement AI/prompting/diffing logic themselves.

### Thin Native Clients (per platform)
Each platform gets only the platform-specific text-capture and UI-rendering layer, which calls into the Shared Core for everything else:
- **macOS client**: Swift/AppKit app using Accessibility APIs (`AXUIElement`) and `CGEventTap`/`NSEvent` global monitors to detect trigger commands and inject results; runs as a menu-bar (no-dock) app.
- **Windows client**: C#/.NET app using UI Automation (UIA) and a global keyboard hook (`SetWindowsHookEx`) for the same detect/inject flow; runs as a system-tray app.
- **Browser extension client**: JavaScript/TypeScript, Manifest V3, using DOM input/contenteditable listeners — no OS-level hooks needed since it only needs access to web page text fields.

### Cross-Platform Principles
- Trigger detection logic (regex matching, mode mapping) should be defined once (e.g. as a small shared config/spec — list of commands and their prompt mode) and referenced/ported identically across clients, not redefined ad hoc per platform.
- The confirm-first UI/UX flow (suggestion shown, accept/reject) should follow the same interaction pattern across platforms even though each is implemented in a different native UI toolkit.
- New platforms should only need to implement: (1) text capture/trigger detection, (2) calling the Shared Core, (3) rendering the suggestion and injecting the accepted result — nothing else.
- Avoid embedding AI/prompting/diffing/account logic directly inside any platform client; if a platform client needs to call the LLM directly (e.g. for an offline-first browser extension build), duplicate only the prompt templates/config, not the surrounding logic.



### 1. Trigger Detection
- Monitor text input fields (textarea / input / contenteditable) for value changes.
- Detect when the field's content ends with a recognized trigger command, e.g.:
  - `/fixit` — conservative spelling + grammar fix only, preserve voice and meaning.
  - `/rewrite` — fuller rephrasing for clarity/flow.
  - `/formal` — rewrite in a more formal tone.
  - `/casual` — rewrite in a more casual tone.
- Trigger matching should be case-insensitive and anchored to the end of input (e.g. regex `/\/(fixit|rewrite|formal|casual)$/i`).
- On trigger detected: strip the command string from the input, capture the remaining text as the payload to send to the AI.

### 2. AI Backend Integration
- Abstract LLM calls behind a common interface (e.g. `correctText(text, mode): Promise<string>`) so Claude, OpenAI, and Gemini can be swapped via config.
- Each trigger mode maps to a distinct system prompt:
  - `fixit`: "Fix only spelling and grammar errors. Do not change meaning, tone, or wording beyond what's necessary."
  - `rewrite`: "Rewrite for clarity and flow while preserving meaning."
  - `formal` / `casual`: tone-shift prompts.
- API keys should be stored securely (env vars / extension storage, never hardcoded or exposed client-side in production).
- Support configurable model selection per provider (e.g. Claude Haiku/Sonnet, GPT-4o-mini, Gemini Flash) to balance cost/latency/quality.

### 3. Replacement / UI Behavior
- While the API call is in-flight, show a lightweight loading indicator inline (e.g. dim text or spinner) — do not block other input.
- On response, replace the original text in the field with the corrected/rewritten version.
- **Confirm-first only**: always show a suggestion (diff or popup) that the user must explicitly accept before it replaces the field content. Auto-replace (silently overwriting text without confirmation) is not permitted.
- Handle errors gracefully (API failure, timeout, rate limit) — restore original text and show a non-blocking error message; never silently lose user input.

### 4. Diffing (required, since confirm-first is mandatory)
- Compute a diff between original and corrected text.
- Highlight inserted/removed/changed spans (e.g. via a diff library like `diff` or `diff-match-patch`).

### 5. User Account Linking
- Allow users to connect their own Claude (Anthropic) or ChatGPT (OpenAI) account/API key, so usage is billed to them rather than (or in addition to) a shared app-level key.
- Provide a settings/options screen where the user can enter and securely store their own API key, or authenticate via OAuth where the provider supports it.
- Let the user select which linked account/provider to use as the active backend for corrections.
- Validate the key/connection (e.g. a lightweight test call) and show clear status (connected / invalid / expired).
- Store credentials securely (e.g. OS keychain or extension's secure storage), never in plain text or synced logs.
- Support unlinking/removing a connected account.

## Non-Functional Requirements
- **Latency**: API round-trip should ideally complete within 1–3 seconds; show loading state to manage perceived wait.
- **Cost control**: Since triggers are explicit (not per-keystroke), cost is naturally bounded — but still cap max input length sent per request, and consider caching identical inputs.
- **Privacy**: Text typed by the user is sent to a third-party LLM API — document this clearly to the user; avoid sending sensitive fields (e.g. password inputs) by excluding `type="password"` fields from monitoring.
- **Reliability**: Never delete or lose the user's original text on failure.
- **Extensibility**: New trigger commands, new LLM providers, and new platform clients (Windows, browser extension) should be addable without rearchitecting the Shared Core.

## Out of Scope (v1)
- Real-time/ambient correction without explicit trigger.
- On-device/local model inference.
- Multi-user accounts, billing, or team features.

## Tech Stack
- **Shared Core**: TypeScript, running on Node.js — chosen for first-class LLM provider SDKs (Anthropic/OpenAI/Google), shared code/types with the browser extension client, and faster iteration speed. Exposed via HTTP/IPC, handling AI calls, prompting, diffing, and account linking — reused unchanged by all platform clients. (Go considered as a fallback if daemon resource footprint or distribution friction becomes a problem later.)
- **macOS client**: Swift + AppKit, Accessibility framework (`AXUIElement`), `CGEventTap`/`NSEvent` global monitors, menu-bar app.
- **Windows client**: C#/.NET, UI Automation (UIA), `SetWindowsHookEx` global keyboard hook, system-tray app.
- **Browser extension client**: JavaScript/TypeScript, Manifest V3, DOM-based input/contenteditable monitoring.
- **AI calls** (within Shared Core): Provider SDKs or direct REST calls to Claude/OpenAI/Gemini `/messages` or `/chat/completions` endpoints.
- **Diffing** (within Shared Core): `diff` or `diff-match-patch` npm package.

## Open Questions
- Which LLM provider is the primary/default backend?
- Should trigger commands be user-customizable (settings page)?
- Target platform priority: macOS first confirmed — when should Windows and the browser extension work begin?
- Should the Shared Core run as a persistent local background service (daemon) from day one, or start as logic embedded directly in the macOS client and get extracted into a separate service once Windows support begins?
