//
//  FallbackWeatherService.swift
//  Weather Cub
//
//  Created by Nick Schneble on 8/13/25.
//

import Foundation

final class FallbackWeatherService {
    private struct OMCurrent: Decodable { let temperature: Double; let windspeed: Double; let weathercode: Int }
    private struct OMResp: Decodable { let current_weather: OMCurrent? }

    func load(lat: Double, lon: Double) async throws -> WeatherPayload {
        // Request in Celsius, derive Fahrenheit
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "current_weather", value: "true")
        ]
        let url = comps.url!
        let (data, resp) = try await URLSession.shared.data(from: url)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 300 {
            throw NSError(domain: "MenuBear", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Open‑Meteo HTTP \(http.statusCode)"])
        }
        let decoded = try JSONDecoder().decode(OMResp.self, from: data)
        guard let cw = decoded.current_weather else {
            throw NSError(domain: "MenuBear", code: -10, userInfo: [NSLocalizedDescriptionKey: "Open‑Meteo: missing current_weather"])
        }
        let c = cw.temperature
        let f = c * 9/5 + 32
        let cond = mapCondition(code: cw.weathercode, wind: cw.windspeed)
        return WeatherPayload(
            condition: cond,
            fahrenheit: .init(actual: f, feels: f),
            celsius: .init(actual: c, feels: c)
        )
    }

    private func mapCondition(code: Int, wind: Double) -> WeatherPayload.Condition {
        switch code {
        case 0: return .sunny
        case 1,2,3,45,48: return .cloudy
        case 51,53,55,56,57,61,63,65,66,67,80,81,82,95,96,99: return .rainy
        case 71,73,75,77,85,86: return .snowy
        default:
            if wind >= 10 { return .windy } // ~22 mph
            return .cloudy
        }
    }
}
