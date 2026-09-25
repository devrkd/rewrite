import { randomBytes, createHash } from "crypto";

/** Generates a cryptographically random code_verifier for PKCE. */
export function generateCodeVerifier(): string {
  return randomBytes(32).toString("base64url");
}

/** Derives the code_challenge (S256) from a code_verifier. */
export function deriveCodeChallenge(verifier: string): string {
  return createHash("sha256").update(verifier).digest("base64url");
}

/** Generates a random state token for CSRF protection. */
export function generateState(): string {
  return randomBytes(16).toString("hex");
}
