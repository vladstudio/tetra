import Foundation

enum TetraError: LocalizedError {
    case unknownFunction(String)
    case unknownFunctionType(String)
    case unknownProvider(String)
    case missingModel
    case missingPrompt
    case llmError(String)

    var errorDescription: String? {
        switch self {
        case .unknownFunction(let n): return "Unknown function: \(n)"
        case .unknownFunctionType(let t): return "Unknown function type: \(t)"
        case .unknownProvider(let n): return "Unknown provider: \(n)"
        case .missingModel: return "Model not specified"
        case .missingPrompt: return "Prompt not specified"
        case .llmError(let msg): return msg
        }
    }
}

class TransformEngine {
    static let shared = TransformEngine()

    func transform(text: String, function: String) async throws -> String {
        guard let fn = ConfigManager.shared.config.functions[function] else {
            throw TetraError.unknownFunction(function)
        }
        switch fn.type {
        case "builtin":
            return applyBuiltin(text: text, transform: fn.transform ?? "")
        case "llm":
            return try await callLLM(text: text, config: fn)
        default:
            throw TetraError.unknownFunctionType(fn.type)
        }
    }

    // MARK: - Builtin

    private func applyBuiltin(text: String, transform: String) -> String {
        switch transform {
        case "uppercase": return text.uppercased()
        case "lowercase": return text.lowercased()
        case "capitalize": return text.capitalized
        case "trim": return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "slug":
            return text.lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        case "camelCase": return toCamelCase(text)
        case "snakeCase": return toSnakeCase(text)
        case "base64Encode": return Data(text.utf8).base64EncodedString()
        case "base64Decode":
            if let d = Data(base64Encoded: text), let s = String(data: d, encoding: .utf8) { return s }
            return text
        case "urlEncode": return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        case "urlDecode": return text.removingPercentEncoding ?? text
        case "jsonFormat":
            if let d = text.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
               let s = String(data: pretty, encoding: .utf8) { return s }
            return text
        case "stripHtml":
            return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        case "count":
            let chars = text.count
            let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            let lines = text.components(separatedBy: .newlines).count
            return "chars: \(chars), words: \(words), lines: \(lines)"
        case "reverse": return String(text.reversed())
        default: return text
        }
    }

    private func toCamelCase(_ text: String) -> String {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard let first = words.first else { return text }
        return first.lowercased() + words.dropFirst().map { $0.capitalized }.joined()
    }

    private func toSnakeCase(_ text: String) -> String {
        var result = ""
        for (i, char) in text.enumerated() {
            if char.isUppercase && i > 0 { result += "_" }
            result += String(char).lowercased()
        }
        return result
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    // MARK: - LLM

    private func callLLM(text: String, config: FunctionConfig) async throws -> String {
        guard let providerName = config.provider,
              let provider = ConfigManager.shared.config.providers[providerName] else {
            throw TetraError.unknownProvider(config.provider ?? "nil")
        }
        guard let model = config.model else { throw TetraError.missingModel }
        guard let promptTemplate = config.prompt else { throw TetraError.missingPrompt }

        let prompt = promptTemplate.replacingOccurrences(of: "{{text}}", with: text)
        let baseUrl = provider.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: baseUrl + "/chat/completions") else {
            throw TetraError.llmError("Invalid URL: \(baseUrl)/chat/completions")
        }

        var messages: [[String: String]] = []
        if let system = config.system {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": prompt])

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": config.temperature ?? 0.3,
        ]
        if let maxTokens = config.maxTokens {
            body["max_tokens"] = maxTokens
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = provider.resolvedApiKey {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw TetraError.llmError("HTTP \(code): \(msg)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TetraError.llmError("Failed to parse LLM response")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
