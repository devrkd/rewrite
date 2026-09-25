import "dotenv/config";
import express, { type Request, type Response, type NextFunction } from "express";
import { CorrectRequestSchema } from "./types.js";
import { correctText } from "./correct.js";
import { TRIGGERS } from "./triggers.js";
import { authRouter } from "./auth/router.js";
import { getAllStatus } from "./auth/store.js";

const app = express();
app.use(express.json());

app.use("/auth", authRouter);

app.get("/health", (_req: Request, res: Response) => {
  res.json({
    status: "ok",
    connectedProviders: getAllStatus(),
    version: "0.1.0",
  });
});

app.get("/triggers", (_req: Request, res: Response) => {
  res.json({ triggers: TRIGGERS });
});

app.post("/correct", async (req: Request, res: Response, next: NextFunction) => {
  const parsed = CorrectRequestSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: parsed.error.message, code: "VALIDATION_ERROR" });
    return;
  }

  try {
    const result = await correctText(parsed.data);
    res.json(result);
  } catch (err) {
    next(err);
  }
});

app.use((err: Error, _req: Request, res: Response, _next: NextFunction) => {
  console.error("[fluent-core]", err.message);
  const isAuthError = err.message.includes("not connected") || err.message.includes("No AI provider");
  res.status(isAuthError ? 401 : 500).json({
    error: err.message,
    code: isAuthError ? "NOT_CONNECTED" : "INTERNAL_ERROR",
  });
});

const PORT = parseInt(process.env.PORT ?? "7432", 10);
app.listen(PORT, "127.0.0.1", () => {
  console.log(`[fluent-core] Running on http://127.0.0.1:${PORT}`);
  console.log(`[fluent-core] Provider: ${process.env.FLUENT_PROVIDER ?? "anthropic"}`);
});
