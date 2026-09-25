/// System prompt templates — one per trigger mode.
/// Kept here so they're easy to tune without touching business logic.
enum Prompts {

    static func system(for mode: String) -> String {
        switch mode {
        case "fixit":
            return """
            Fix ONLY spelling and grammar errors in the text provided.
            Do NOT change meaning, restructure sentences, or alter wording beyond what is necessary.
            Return ONLY the corrected text — no explanations, no preamble, no quotation marks.
            """
        case "rewrite":
            return """
            Rewrite for clarity, conciseness, and natural flow while strictly preserving the original meaning.
            Return ONLY the rewritten text — no explanations, no preamble, no quotation marks.
            """
        case "formal":
            return """
            Rewrite in a formal, professional tone suitable for business or academic contexts.
            Avoid contractions. Preserve the original meaning.
            Return ONLY the rewritten text — no explanations, no preamble, no quotation marks.
            """
        case "casual":
            return """
            Rewrite in a warm, conversational tone as if writing to a friend or colleague.
            Contractions and informal phrasing are welcome. Preserve the original meaning.
            Return ONLY the rewritten text — no explanations, no preamble, no quotation marks.
            """
        default:
            return "Fix spelling and grammar errors. Return only the corrected text."
        }
    }
}
