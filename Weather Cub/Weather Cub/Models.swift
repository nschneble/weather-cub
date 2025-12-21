//
//  Models.swift
//  Weather Cub
//
//  Created by Nick Schneble on 8/13/25.
//

import Foundation

struct WeatherPayload: Codable {
    enum Condition: String, Codable { case sunny, cloudy, windy, rainy, snowy }
    let condition: Condition
    let fahrenheit: Temps
    let celsius: Temps

    struct Temps: Codable { let actual: Double; let feels: Double }
}
