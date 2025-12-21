//
//  Settings.swift
//  Weather Cub
//
//  Created by Nick Schneble on 8/13/25.
//

import Foundation

enum Units: String, CaseIterable { case fahrenheit, celsius }

struct AppSettings {
    static var shared = AppSettings()
    private let defaults = UserDefaults.standard

    private enum Key: String { case units, includeFeelsLike, refreshMinutes, lastLocationString }

    var units: Units {
        get { Units(rawValue: defaults.string(forKey: Key.units.rawValue) ?? Units.fahrenheit.rawValue) ?? .fahrenheit }
        set { defaults.set(newValue.rawValue, forKey: Key.units.rawValue) }
    }

    var includeFeelsLike: Bool {
        get { defaults.object(forKey: Key.includeFeelsLike.rawValue) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.includeFeelsLike.rawValue) }
    }

    var refreshMinutes: Int {
        get { defaults.object(forKey: Key.refreshMinutes.rawValue) as? Int ?? 10 }
        set { defaults.set(newValue, forKey: Key.refreshMinutes.rawValue) }
    }

    var lastLocationString: String? {
        get { defaults.string(forKey: Key.lastLocationString.rawValue) }
        set { defaults.set(newValue, forKey: Key.lastLocationString.rawValue) }
    }
}
