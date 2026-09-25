import Foundation

// MARK: - Public types

struct DiffSegment: Codable {
    let type: String   // "equal" | "insert" | "delete"
    let value: String
}

struct CorrectResponse {
    let original: String
    let corrected: String
    let diff: [DiffSegment]
}

struct ModelInfo {
    let id: String
    let displayName: String
}

// MARK: - Errors

enum AnthropicError: LocalizedError {
    case notConnected
    case invalidKey
    case noData
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No API key found. Open Fluent Settings to add your Anthropic key."
        case .invalidKey:
            return "Invalid API key. Please check your key in Fluent Settings."
        case .noData:
            return "No response received from Anthropic."
        case .apiError(let code, let body):
            return "Anthropic error \(code): \(body.prefix(200))"
        }
    }

    var isAuthError: Bool {
        switch self {
        case .notConnected, .invalidKey: return true
        default: return false
        }
    }
}

// MARK: - AnthropicClient

/// Calls the Anthropic API directly — no local core server required.
final class AnthropicClient {

    static let shared = AnthropicClient()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    // MARK: - Correct text

    func correct(
        text: String,
        mode: String,
        completion: @escaping (Result<CorrectResponse, Error>) -> Void
    ) {
        guard let apiKey = KeychainStore.load(account: "anthropic"), !apiKey.isEmpty else {
            completion(.failure(AnthropicError.notConnected))
            return
        }

        let model = UserDefaults.standard.string(forKey: "anthropicModel") ?? "claude-3-5-sonnet-latest"
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": Prompts.system(for: mode),
            "messages": [["role": "user", "content": text]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }

            if let error {
                completion(.failure(error))
                return
            }

            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data else { completion(.failure(AnthropicError.noData)); return }

            if status == 401 { completion(.failure(AnthropicError.invalidKey)); return }

            if status != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(AnthropicError.apiError(status, body)))
                return
            }

            struct Msg: Decodable {
                struct Block: Decodable { let type: String; let text: String }
                let content: [Block]
            }
            guard let msg = try? JSONDecoder().decode(Msg.self, from: data),
                  let block = msg.content.first(where: { $0.type == "text" })
            else {
                completion(.failure(AnthropicError.noData))
                return
            }

            let corrected = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let diff = self.wordDiff(from: text, to: corrected)
            completion(.success(CorrectResponse(original: text, corrected: corrected, diff: diff)))
        }.resume()
    }

    // MARK: - Validate key + fetch models

    func validateAndFetchModels(
        key: String,
        completion: @escaping (Result<[ModelInfo], Error>) -> Void
    ) {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        session.dataTask(with: request) { data, response, error in
            if let error { completion(.failure(error)); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 { completion(.failure(AnthropicError.invalidKey)); return }
            guard let data, status == 200 else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                completion(.failure(AnthropicError.apiError(status, body)))
                return
            }
            struct Resp: Decodable {
                struct Entry: Decodable {
                    let id: String
                    let displayName: String?
                    enum CodingKeys: String, CodingKey {
                        case id; case displayName = "display_name"
                    }
                }
                let data: [Entry]
            }
            guard let resp = try? JSONDecoder().decode(Resp.self, from: data) else {
                completion(.failure(AnthropicError.noData)); return
            }
            let models = resp.data
                .filter { $0.id.hasPrefix("claude") }
                .map { ModelInfo(id: $0.id, displayName: $0.displayName ?? $0.id) }
            completion(.success(models))
        }.resume()
    }

    // MARK: - Word-level diff (LCS)

    private func wordDiff(from original: String, to corrected: String) -> [DiffSegment] {
        let origTokens = tokenize(original)
        let corrTokens = tokenize(corrected)
        let m = origTokens.count, n = corrTokens.count

        // Build LCS table
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...max(m, 1) where i <= m {
            for j in 1...max(n, 1) where j <= n {
                dp[i][j] = origTokens[i - 1] == corrTokens[j - 1]
                    ? dp[i - 1][j - 1] + 1
                    : max(dp[i - 1][j], dp[i][j - 1])
            }
        }

        // Backtrack
        var segments: [DiffSegment] = []
        var i = m, j = n
        while i > 0 || j > 0 {
            if i > 0 && j > 0 && origTokens[i - 1] == corrTokens[j - 1] {
                segments.append(DiffSegment(type: "equal", value: origTokens[i - 1]))
                i -= 1; j -= 1
            } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
                segments.append(DiffSegment(type: "insert", value: corrTokens[j - 1]))
                j -= 1
            } else {
                segments.append(DiffSegment(type: "delete", value: origTokens[i - 1]))
                i -= 1
            }
        }

        return segments.reversed()
    }

    /// Splits text into word + whitespace tokens so diffs stay readable.
    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for char in text {
            if char.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
