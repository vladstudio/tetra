import Foundation

enum PromptCommand {
    private struct Metadata {
        var llm: String?
        var temperature: Double?
    }

    static func run(path: URL, input: String, args: [String: String]) async throws -> String {
        let raw = try String(contentsOf: path, encoding: .utf8)
        let parsed = parse(raw)

        guard let llmName = parsed.metadata.llm, !llmName.isEmpty else {
            throw TetraError.invalidPrompt("\(path.lastPathComponent) is missing 'llm' frontmatter")
        }
        guard let llm = ConfigManager.shared.config.llms[llmName] else {
            throw TetraError.unknownLLM(llmName)
        }
        guard !llm.model.isEmpty else {
            throw TetraError.invalidPrompt("LLM '\(llmName)' is missing a model")
        }

        var values = args
        values["text"] = input
        let prompt = render(parsed.body, values: values)
        do {
            return try await complete(llm: llm, prompt: prompt, temperature: parsed.metadata.temperature)
        } catch TetraError.llmFailed(let message) where message.contains("empty content") {
            // Flash-class models (Gemini lite especially) intermittently return
            // an empty completion with finish_reason=stop. One quiet retry.
            try? await Task.sleep(nanoseconds: 400_000_000)
            return try await complete(llm: llm, prompt: prompt, temperature: parsed.metadata.temperature)
        }
    }

    private static func parse(_ raw: String) -> (metadata: Metadata, body: String) {
        guard raw.hasPrefix("---\n"),
              let end = raw.range(of: "\n---\n", range: raw.index(raw.startIndex, offsetBy: 4)..<raw.endIndex) else {
            return (Metadata(), raw)
        }

        let header = String(raw[raw.index(raw.startIndex, offsetBy: 4)..<end.lowerBound])
        let body = String(raw[end.upperBound...])
        var metadata = Metadata()

        for line in header.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

            switch key {
            case "llm":
                metadata.llm = value
            case "temperature":
                metadata.temperature = Double(value)
            default:
                break
            }
        }

        return (metadata, body)
    }

    private static func render(_ template: String, values: [String: String]) -> String {
        var output = template
        let blockPattern = #"\{\{#([A-Za-z0-9_-]+)\}\}([\s\S]*?)\{\{/\1\}\}"#

        while let regex = try? NSRegularExpression(pattern: blockPattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
            guard let whole = Range(match.range(at: 0), in: output),
                  let keyRange = Range(match.range(at: 1), in: output),
                  let contentRange = Range(match.range(at: 2), in: output) else { break }
            let key = String(output[keyRange])
            let replacement = values[key]?.isEmpty == false ? String(output[contentRange]) : ""
            output.replaceSubrange(whole, with: replacement)
        }

        guard let regex = try? NSRegularExpression(pattern: #"\{\{\s*([A-Za-z0-9_-]+)\s*\}\}"#) else {
            return output
        }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        var result = ""
        var cursor = output.startIndex
        for match in matches {
            guard let whole = Range(match.range(at: 0), in: output),
                  let keyRange = Range(match.range(at: 1), in: output) else { continue }
            result += output[cursor..<whole.lowerBound]
            result += values[String(output[keyRange])] ?? ""
            cursor = whole.upperBound
        }
        result += output[cursor...]
        return result
    }

    private static func complete(llm: LLMConfig, prompt: String, temperature: Double?) async throws -> String {
        let base = llm.baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw TetraError.llmFailed("invalid base URL")
        }

        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = llm.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let payload: [String: Any] = [
            "model": llm.model,
            "messages": [
                ["role": "user", "content": prompt],
            ],
            "temperature": temperature ?? 0.3,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TetraError.llmFailed("missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw TetraError.llmFailed("HTTP \(http.statusCode): \(message)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw TetraError.llmFailed("response had no choices[0].message: \(body.prefix(800))")
        }
        // content is usually a string, but some OpenAI-compatible endpoints
        // return an array of parts, and thinking models may only fill
        // reasoning_content. Surface everything else (finish_reason, model,
        // prompt size, response snippet) so failures are diagnosable.
        if let text = contentText(message) {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let finishReason = choices.first?["finish_reason"] as? String ?? "unknown"
        let body = String(data: data, encoding: .utf8) ?? "<binary>"
        let preview = prompt.prefix(200).replacingOccurrences(of: "\n", with: " ")
        throw TetraError.llmFailed(
            "\(llm.model) returned empty content (finish_reason=\(finishReason)); " +
            "prompt \(prompt.count) chars, starts with: \"\(preview)\"; " +
            "response: \(body.prefix(600))")
    }

    /// Extracts the reply text from an OpenAI-format message: `content` as a
    /// string, `content` as an array of parts (`[{"type":"text","text":…}]`),
    /// or `reasoning_content` from thinking models.
    private static func contentText(_ message: [String: Any]) -> String? {
        if let s = message["content"] as? String, !s.isEmpty { return s }
        if let parts = message["content"] as? [[String: Any]] {
            let joined = parts.compactMap { $0["text"] as? String }.joined(separator: "")
            if !joined.isEmpty { return joined }
        }
        if let reasoning = message["reasoning_content"] as? String, !reasoning.isEmpty {
            return reasoning
        }
        return nil
    }
}
