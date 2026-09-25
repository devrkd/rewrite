import Anthropic from "@anthropic-ai/sdk";
import { getToken, isConnected } from "../auth/store.js";
import { getSystemPrompt } from "../prompts.js";
import type { TriggerMode } from "../types.js";
import type { LLMProvider } from "./index.js";

export class AnthropicProvider implements LLMProvider {
  private model: string;

  constructor() {
    this.model = process.env.ANTHROPIC_MODEL ?? "claude-haiku-4-5";
  }

  async correct(text: string, mode: TriggerMode): Promise<string> {
    if (!isConnected("anthropic")) {
      throw new Error("Claude is not connected. Open Fluent settings to sign in with your Anthropic account.");
    }

    const token = getToken("anthropic")!;
    const client = new Anthropic({ apiKey: token.accessToken });

    const message = await client.messages.create({
      model: this.model,
      max_tokens: 4096,
      system: getSystemPrompt(mode),
      messages: [{ role: "user", content: text }],
    });

    const block = message.content[0];
    if (block.type !== "text") throw new Error("Unexpected response type from Anthropic");
    return block.text.trim();
  }
}
