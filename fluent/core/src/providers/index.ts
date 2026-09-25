import type { TriggerMode, Provider } from "../types.js";
import { getSystemPrompt } from "../prompts.js";

export interface LLMProvider {
  correct(text: string, mode: TriggerMode): Promise<string>;
}

export async function createProvider(name: Provider): Promise<LLMProvider> {
  switch (name) {
    case "anthropic": {
      const { AnthropicProvider } = await import("./anthropic.js");
      return new AnthropicProvider();
    }
    case "openai": {
      const { OpenAIProvider } = await import("./openai.js");
      return new OpenAIProvider();
    }
    case "gemini": {
      const { GeminiProvider } = await import("./gemini.js");
      return new GeminiProvider();
    }
  }
}

export { getSystemPrompt };
