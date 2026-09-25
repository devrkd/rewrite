import OpenAI from "openai";
import { getToken, isConnected } from "../auth/store.js";
import { getSystemPrompt } from "../prompts.js";
import type { TriggerMode } from "../types.js";
import type { LLMProvider } from "./index.js";

export class OpenAIProvider implements LLMProvider {
  private model: string;

  constructor() {
    this.model = process.env.OPENAI_MODEL ?? "gpt-4o-mini";
  }

  async correct(text: string, mode: TriggerMode): Promise<string> {
    if (!isConnected("openai")) {
      throw new Error("ChatGPT is not connected. Open Fluent settings to sign in with your OpenAI account.");
    }

    const token = getToken("openai")!;
    const client = new OpenAI({ apiKey: token.accessToken });

    const response = await client.chat.completions.create({
      model: this.model,
      messages: [
        { role: "system", content: getSystemPrompt(mode) },
        { role: "user", content: text },
      ],
    });

    const content = response.choices[0]?.message.content;
    if (!content) throw new Error("Empty response from OpenAI");
    return content.trim();
  }
}
