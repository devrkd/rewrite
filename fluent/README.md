# Fluent

An AI writing assistant that fixes spelling/grammar and rewrites text on
explicit command (`/fixit`, `/rewrite`, `/formal`, `/casual`) typed as a
suffix in any text field.

This directory has three independent implementations of that idea — a
native macOS app, a browser extension, and a standalone Node service — each
detecting the trigger and calling an LLM on its own. See the
[root README](../README.md) for how each one works, how they differ (API
key vs. OAuth, which providers each supports), and which one to run for what
you're trying to do.

## Quick start

```bash
# macOS app — talks to Anthropic directly, key stored in Keychain
cd macos && swift build && swift run

# Browser extension — talks to Anthropic/OpenAI directly, key in chrome.storage
cd extension && npm install && npm run build   # then "Load unpacked" from dist/

# Standalone core service — full OAuth flow, not wired to either client above
cd core && cp .env.example .env && npm install && npm run dev
```
