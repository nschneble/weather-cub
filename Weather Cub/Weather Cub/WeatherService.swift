//
//  WeatherService.swift
//  Weather Cub
//
//  Created by Nick Schneble on 8/13/25.
//

import Foundation
import Combine

final class WeatherService {
    private let client: OpenAIClient
    private let settings = AppSettings.shared
    private let fallback = FallbackWeatherService()

    init(client: OpenAIClient) { self.client = client }

    func load(lat: Double, lon: Double) async throws -> WeatherPayload {
        do {
            return try await client.fetchWeather(lat: lat, lon: lon)
        } catch let apiErr as OpenAIClient.APIError {
            switch apiErr {
            case .insufficientQuota:
                // Graceful fallback when OpenAI quota is exceeded
                return try await fallback.load(lat: lat, lon: lon)
            case .http:
                throw apiErr
            }
        } catch {
            throw error
        }
    }
}
