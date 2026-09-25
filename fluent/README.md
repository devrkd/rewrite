# Fluent

An AI-powered writing assistant that fixes spelling/grammar and rewrites text on explicit user command — triggered by typing a command suffix (e.g. `/fixit`, `/rewrite`) in any text field on macOS.

## Project Structure

```
fluent/
├── core/        # Shared TypeScript service (LLM calls, diffing, prompts)
└── macos/       # Swift/AppKit macOS menu-bar app (Accessibility + CGEventTap)
```

## Architecture

| Layer | Tech | Responsibility |
|-------|------|----------------|
| **Shared Core** | TypeScript / Node.js | LLM provider abstraction, prompt templates, diff computation, API key management. Runs as a local HTTP service on `localhost:7432`. |
| **macOS Client** | Swift + AppKit | Global keyboard monitoring via `CGEventTap`, text capture via `AXUIElement`, suggestion UI, injects accepted text back into the focused field. |

## Trigger Commands

| Command | Behaviour |
|---------|-----------|
| `/fixit` | Conservative spelling + grammar fix only |
| `/rewrite` | Fuller rephrasing for clarity/flow |
| `/formal` | Rewrite in a more formal tone |
| `/casual` | Rewrite in a more casual tone |

## Quick Start

### 1. Core service

```bash
cd core
cp .env.example .env        # add your API keys
npm install
npm run dev                 # starts on http://localhost:7432
```

### 2. macOS app

```bash
cd macos
open Package.swift          # opens in Xcode
# or: swift build && swift run
```

> The macOS app requires **Accessibility** permission granted in  
> System Settings → Privacy & Security → Accessibility.

## Supported LLM Providers

- **Anthropic** Claude (Haiku / Sonnet)
- **OpenAI** GPT-4o-mini / GPT-4o
- **Google** Gemini Flash / Pro

Configure the active provider in the app's Settings menu or via `FLUENT_PROVIDER` in `core/.env`.
