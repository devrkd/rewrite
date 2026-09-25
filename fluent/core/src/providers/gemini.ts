import { GoogleGenerativeAI } from "@google/generative-ai";
import { getToken, isConnected } from "../auth/store.js";
import { getSystemPrompt } from "../prompts.js";
import type { TriggerMode } from "../types.js";
import type { LLMProvider } from "./index.js";

export class GeminiProvider implements LLMProvider {
  private modelName: string;

  constructor() {
    this.modelName = process.env.GEMINI_MODEL ?? "gemini-2.0-flash";
  }

  async correct(text: string, mode: TriggerMode): Promise<string> {
    if (!isConnected("gemini")) {
      throw new Error("Gemini is not connected. Open Fluent settings to sign in with your Google account.");
    }

    const token = getToken("gemini")!;
    const genAI = new GoogleGenerativeAI(token.accessToken);

    const model = genAI.getGenerativeModel({
      model: this.modelName,
      systemInstruction: getSystemPrompt(mode),
    });

    const result = await model.generateContent(text);
    const response = result.response.text();
    if (!response) throw new Error("Empty response from Gemini");
    return response.trim();
  }
}
