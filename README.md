# Fluent

An AI writing assistant that fixes spelling/grammar and rewrites text **on
explicit command**, not ambiently like Grammarly. You type your text, add a
trigger command as a suffix, and the trigger + the text before it are sent to
an LLM; the suggestion appears next to the field and only replaces your text
once you accept it.

```
Let's schedule the meeting for tomorow /fixit
                                        └──┬───┘
                                   trigger, stripped before sending
```

## Trigger commands

Detected as a suffix, case-insensitively, on the text in the focused field:

| Command | Behaviour |
|---|---|
| `/fixit` | Spelling + grammar fix only — no rewording |
| `/rewrite` | Fuller rewrite for clarity and flow |
| `/formal` | Rewrite in a formal, polished tone |
| `/casual` | Rewrite in a warmer, conversational tone |

## Repository layout

```
fluent/
├── macos/       Native macOS menu-bar app (Swift/AppKit)
├── extension/   Browser extension for Chrome/Firefox (MV3)
└── core/        Standalone Node/TypeScript HTTP service
```

These are **three separate implementations of the same idea**, built for
different surfaces, at different points in the project's iteration — not
three parts of one running system. Each one detects the trigger, calls an
LLM, and diffs the result independently; there's a shared *design* (same
trigger commands, same four modes, same accept/reject-with-diff UX) but
not yet a shared *runtime*, which is the direction described in
[`AGENTS.md`](AGENTS.md).

### `macos/` — native app

A menu-bar-only app with no visible window until you trigger it or open
Settings.

- **Detection:** a `CGEventTap` watches every keystroke system-wide. On each
  keypress it reads the focused element via the Accessibility (`AXUIElement`)
  API and checks whether its text ends with one of the trigger suffixes.
- **Calling the model:** talks to the **Anthropic API directly** — no local
  server involved. The API key is entered once in the Settings window,
  validated against `/v1/models`, and stored in the macOS **Keychain**.
- **Diffing:** a word-level LCS diff is computed in Swift (`CoreClient.swift`)
  to highlight what changed in the suggestion popup.
- **Injecting the result:** on Accept/Reject, `TextInjector` first tries
  setting the AX value directly and reads it back to confirm it stuck (works
  for native Cocoa fields). Many Electron/web apps report success without
  actually applying the change, so if the read-back doesn't match, it falls
  back to staging the text on the clipboard and simulating ⌘A + ⌘V — the same
  path a human keystroke would take.
- **State machine:** trigger detection is gated by a single `isPopupActive`
  flag, cleared from exactly one place (the suggestion popup's dismissal
  callback, covering accept/reject/settings/escape), so the app can't get
  stuck ignoring triggers after an edge case.

Run it:
```bash
cd fluent/macos
swift build && swift run
# grant Accessibility permission when prompted (System Settings → Privacy & Security → Accessibility)
# then open the menu-bar icon → Settings to add your Anthropic API key
```

### `extension/` — browser extension

- **Detection:** a content script (`content/index.ts`) attaches `input`/
  `keyup` listeners to every `<input>`, `<textarea>`, and
  `contenteditable` element on the page (including ones added later, via a
  `MutationObserver`, for SPAs), and runs the same trigger regex as the other
  two implementations.
- **Calling the model:** the content script sends a `CORRECT` message to the
  background **service worker**, which does the actual `fetch()` to
  Anthropic or OpenAI — kept out of the content script to avoid CORS.
  Despite the OAuth-flavored naming (`auth.ts`, "connect"), there is
  **no OAuth here**: it's an API key pasted into the extension's options
  page and kept in `chrome.storage.local`.
- **UI:** an in-page overlay (`content/overlay.ts`) anchored to the field,
  not a native popup — it shows a loading state, then the diffed suggestion
  with Accept/Reject, matching the macOS UX in the browser.

Run it:
```bash
cd fluent/extension
npm install
npm run build          # outputs to dist/
# Chrome: chrome://extensions → Developer mode → Load unpacked → select dist/
```

### `core/` — standalone service

A Node/Express HTTP service (`localhost:7432`) with the most complete auth
story of the three: a real **OAuth 2.0 + PKCE** flow (`auth/flow.ts`,
`auth/pkce.ts`) for connecting Anthropic, OpenAI, or Gemini accounts, with
tokens persisted server-side and a `/auth/:provider/callback` route that
renders a plain HTML "Connected!" page for the browser redirect to land on.
`POST /correct` runs the same detect → call LLM → diff pipeline as the other
two, provider-agnostically, via `providers/index.ts`.

**Nothing currently calls this service** — it's not wired up to the macOS
app or the extension, which each call providers directly. Useful as a
sketch of what a real shared backend would look like, or a starting point
for actually centralizing the two clients onto one auth/provider layer.

Run it:
```bash
cd fluent/core
cp .env.example .env    # add OAuth client IDs for the providers you want
npm install
npm run dev             # http://127.0.0.1:7432
```

## Shared pieces (by convention, not by code)

All three implementations independently agree on:
- the four trigger commands and their system prompts (see `prompts.ts` /
  `Prompts.swift` — same wording, three copies),
- diff format: a list of `{ type: "equal" | "insert" | "delete", value }`
  segments, computed with `diff-match-patch` in TS and a hand-rolled
  word-level LCS in Swift,
- the interaction model: never touch the field until the user explicitly
  accepts or rejects the suggestion.

## Supported providers

Anthropic Claude and OpenAI GPT are wired up in all three implementations;
Gemini is wired up in `core/` only. Anthropic's is the most exercised path
in the macOS app (it's the only provider macOS currently supports).
