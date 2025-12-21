//
//  OpenAIClient.swift
//  Weather Cub
//
//  Created by Nick Schneble on 8/13/25.
//

import Foundation

final class OpenAIClient {
    enum APIError: Error { case insufficientQuota(String); case http(Int, String) }

    struct Response: Codable { let choices: [Choice] }
    struct Choice: Codable { let message: Message }
    struct Message: Codable { let content: String }
    struct ErrorEnvelope: Codable { struct Inner: Codable { let message: String; let type: String?; let code: String? }; let error: Inner }

    private let apiKey: String
    private let session = URLSession(configuration: .ephemeral)
    private let orgId = ProcessInfo.processInfo.environment["OPENAI_ORG_ID"]
    private let projectId = ProcessInfo.processInfo.environment["OPENAI_PROJECT_ID"]

    init(apiKey: String) { self.apiKey = apiKey }

    func fetchWeather(lat: Double, lon: Double) async throws -> WeatherPayload {
        let sys = "You are Weather Bear, a precise weather normalizer. Reply with strict JSON that matches the schema."
        let schema = "{" +
        "\"condition\": \"sunny|cloudy|windy|rainy|snowy\", " +
        "\"fahrenheit\": { \"actual\": 72, \"feels\": 68 }, " +
        "\"celsius\": { \"actual\": 22, \"feels\": 20 }" +
        "}"
        let user = "Location: {\"lat\": \(lat), \"lon\": \(lon)}. " +
                  "Always include BOTH fahrenheit and celsius with numeric actual and feels. Return JSON ONLY with keys: condition, fahrenheit{actual,feels}, celsius{actual,feels}."

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": sys],
                ["role": "user", "content": "Schema: \(schema)\(user)"]
            ]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let orgId { request.addValue(orgId, forHTTPHeaderField: "OpenAI-Organization") }
        if let projectId { request.addValue(projectId, forHTTPHeaderField: "OpenAI-Project") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse {
            print("MenuBear: OpenAI HTTP \(http.statusCode)")
            if let bodyStr = String(data: data, encoding: .utf8) { print("MenuBear: raw body=\(bodyStr)") }
            if http.statusCode >= 300 {
                if let env = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
                   env.error.code == "insufficient_quota" {
                    throw APIError.insufficientQuota(env.error.message)
                }
                let msg = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error.message) ?? "HTTP \(http.statusCode)"
                throw APIError.http(http.statusCode, msg)
            }
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let content = decoded.choices.first?.message.content ?? ""
        let jsonText = extractJSON(from: content)
        let jsonData = Data(jsonText.utf8)

        do {
            return try JSONDecoder().decode(WeatherPayload.self, from: jsonData)
        } catch {
            print("MenuBear: strict decode failed: \(error)")
            return try coercePayload(from: jsonData)
        }
    }

    private func extractJSON(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") { return trimmed }
        if let start = content.range(of: "```"),
           let end = content.range(of: "```", range: start.upperBound..<content.endIndex) {
            let inner = String(content[start.upperBound..<end.lowerBound])
            if let brace = inner.firstIndex(of: "{") { return String(inner[brace...]) }
            return inner
        }
        return content
    }

    private func coercePayload(from data: Data) throws -> WeatherPayload {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "MenuBear", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }
        let rawCond = (obj["condition"] as? String ?? "").lowercased()
        let condition: WeatherPayload.Condition = {
            if rawCond.contains("sun") { return .sunny }
            if rawCond.contains("rain") { return .rainy }
            if rawCond.contains("snow") { return .snowy }
            if rawCond.contains("wind") { return .windy }
            return .cloudy
        }()

        func readTemps(_ key: String) -> (Double, Double)? {
            guard let dict = obj[key] as? [String: Any] else { return nil }
            func num(_ v: Any?) -> Double? {
                if let d = v as? Double { return d }
                if let i = v as? Int { return Double(i) }
                if let n = v as? NSNumber { return n.doubleValue }
                if let s = v as? String, let d = Double(s) { return d }
                return nil
            }
            if let a = num(dict["actual"]), let f = num(dict["feels"]) { return (a, f) }
            return nil
        }

        var fTemps = readTemps("fahrenheit")
        var cTemps = readTemps("celsius")
        if fTemps == nil, let c = cTemps { fTemps = (c.0 * 9/5 + 32, c.1 * 9/5 + 32) }
        if cTemps == nil, let f = fTemps { cTemps = ((f.0 - 32) * 5/9, (f.1 - 32) * 5/9) }
        guard let ft = fTemps, let ct = cTemps else {
            throw NSError(domain: "MenuBear", code: -3, userInfo: [NSLocalizedDescriptionKey: "Missing temps"])
        }

        return WeatherPayload(
            condition: condition,
            fahrenheit: .init(actual: ft.0, feels: ft.1),
            celsius: .init(actual: ct.0, feels: ct.1)
        )
    }
}
