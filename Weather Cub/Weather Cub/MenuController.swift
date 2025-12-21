//
//  MenuController.swift
//  Weather Cub
//
//  Created by Nick Schneble on 8/13/25.
//

import AppKit
import Combine

@MainActor
final class MenuController: NSObject {
    private var statusItem: NSStatusItem!
    private var timer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()

    private let location = LocationManager()
    private lazy var service = WeatherService(client: OpenAIClient(apiKey: MenuController.readAPIKey()))

    private var latest: WeatherPayload?
    private var statusLineItem: NSMenuItem?
    private var lastUpdated: Date?
    private var lastError: String?
    private var lastErrorAt: Date?

    // MARK: Setup
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐻 —"
        statusItem.menu = buildMenu()

        // Observe location on main runloop
        location.publisher
            .receive(on: RunLoop.main)
            .sink { [weak self] coord in self?.refresh(lat: coord.latitude, lon: coord.longitude) }
            .store(in: &cancellables)

        location.request()
        scheduleTimer()

        // Refresh on wake
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func systemDidWake() { scheduleTimer(force: true) }

    // MARK: Timer
    private func scheduleTimer(force: Bool = false) {
        timer?.cancel()
        timer = Timer.publish(every: Double(AppSettings.shared.refreshMinutes * 60), on: .main, in: .common)
            .autoconnect()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.location.request() }
        if force { location.request() }
    }

    // MARK: Menu
    private func buildMenu() -> NSMenu {
        let m = NSMenu()

        let status = NSMenuItem(title: "Refreshing…", action: nil, keyEquivalent: "")
        self.statusLineItem = status
        m.addItem(status)
        self.updateStatusLine()

        // Refresh Now
        let refreshNow = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshNow.target = self
        m.addItem(refreshNow)

        m.addItem(.separator())

        // Units submenu
        let unitsItem = NSMenuItem(title: "Units", action: nil, keyEquivalent: "")
        let unitsSub = NSMenu()
        Units.allCases.forEach { u in
            let it = NSMenuItem(title: u == .fahrenheit ? "Fahrenheit (°F)" : "Celsius (°C)", action: #selector(toggleUnits(_:)), keyEquivalent: "")
            it.state = (AppSettings.shared.units == u) ? .on : .off
            it.representedObject = u.rawValue
            it.target = self
            unitsSub.addItem(it)
        }
        unitsItem.submenu = unitsSub
        m.addItem(unitsItem)

        // Feels like
        let feels = NSMenuItem(title: "Include ‘feels like’", action: #selector(toggleFeels(_:)), keyEquivalent: "")
        feels.state = AppSettings.shared.includeFeelsLike ? .on : .off
        feels.target = self
        m.addItem(feels)

        // Refresh interval
        let refresh = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        let refreshSub = NSMenu()
        [5,10,15,30,60].forEach { minutes in
            let it = NSMenuItem(title: "\(minutes) minutes", action: #selector(changeRefresh(_:)), keyEquivalent: "")
            it.state = (AppSettings.shared.refreshMinutes == minutes) ? .on : .off
            it.representedObject = minutes
            it.target = self
            refreshSub.addItem(it)
        }
        refresh.submenu = refreshSub
        m.addItem(refresh)

        m.addItem(.separator())
        m.addItem(withTitle: "Quit MenuBear", action: #selector(quit), keyEquivalent: "q")
        return m
    }

    // MARK: Actions
    @objc private func toggleUnits(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let u = Units(rawValue: raw) else { return }
        AppSettings.shared.units = u
        rebuildMenu()
        updateTitle()
    }

    @objc private func toggleFeels(_ sender: NSMenuItem) {
        AppSettings.shared.includeFeelsLike.toggle()
        sender.state = AppSettings.shared.includeFeelsLike ? .on : .off
        updateTitle()
    }

    @objc private func changeRefresh(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        AppSettings.shared.refreshMinutes = minutes
        rebuildMenu()
        scheduleTimer(force: true)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func refreshNow() {
        lastError = nil
        lastErrorAt = nil
        updateStatusLine()
        location.request()
    }

    private func rebuildMenu() { statusItem.menu = buildMenu() }

    // MARK: Data & UI
    private func refresh(lat: Double, lon: Double) {
        Task { [weak self] in
            do {
                let payload = try await self?.service.load(lat: lat, lon: lon)
                if let p = payload {
                    await MainActor.run {
                        self?.latest = p
                        self?.lastUpdated = Date()
                        self?.lastError = nil
                        self?.lastErrorAt = nil
                        self?.updateTitle()
                        self?.updateStatusLine()
                    }
                }
            } catch {
                await MainActor.run {
                    self?.lastError = error.localizedDescription
                    self?.lastErrorAt = Date()
                    self?.statusItem.button?.title = "🐻⚠️"
                    self?.statusItem.button?.toolTip = "Error: \(error.localizedDescription)"
                    self?.updateStatusLine()
                }
            }
        }
    }

    private func updateTitle() {
        guard let p = latest else { return }
        let units = AppSettings.shared.units
        let showFeels = AppSettings.shared.includeFeelsLike

        let (emoji, primary, feels) = display(for: p, units: units)
        var title = "\(emoji) \(primary)"
        if showFeels, let f = feels { title += " / \(f)" }

        statusItem.button?.title = title
        statusItem.button?.toolTip = tooltip(for: p)
        lastUpdated = Date()
        lastError = nil
        lastErrorAt = nil
        updateStatusLine()
    }

    private func updateStatusLine() {
        guard let item = statusLineItem else { return }
        if let _ = lastError {
            let df = DateFormatter(); df.timeStyle = .short; df.dateStyle = .none
            let t = lastErrorAt.map { df.string(from: $0) } ?? "now"
            item.title = "Error at \(t) — see tooltip"
        } else if let date = lastUpdated {
            let df = DateFormatter(); df.timeStyle = .short; df.dateStyle = .none
            item.title = "Last updated \(df.string(from: date))"
        } else {
            item.title = "Refreshing…"
        }
    }

    private func display(for p: WeatherPayload, units: Units) -> (String, String, String?) {
        let emoji: String
        switch p.condition {
        case .sunny: emoji = "☀️"
        case .cloudy: emoji = "☁️"
        case .windy: emoji = "💨"
        case .rainy: emoji = "🌧️"
        case .snowy: emoji = "🌨️"
        }
        switch units {
        case .fahrenheit:
            let a = Int(p.fahrenheit.actual.rounded())
            let f = Int(p.fahrenheit.feels.rounded())
            return (emoji, "\(a)°", "\(f)°")
        case .celsius:
            let a = Int(p.celsius.actual.rounded())
            let f = Int(p.celsius.feels.rounded())
            return (emoji, "\(a)°", "\(f)°")
        }
    }

    private func tooltip(for p: WeatherPayload) -> String {
        let tempF = p.fahrenheit.actual
        if tempF <= 32 { return "It’s bear-y cold out" }
        if tempF >= 80 && p.condition == .sunny { return "It’s bear-y beautiful out" }
        switch p.condition {
        case .rainy: return "Bear with an umbrella?"
        case .snowy: return "Snow problem for a polar bear"
        case .windy: return "Bear-icane levels? Hold onto your hat"
        case .cloudy: return "Bear-ly any sun today"
        case .sunny: return "It’s bear-y bright out"
        }
    }

    // MARK: API Key
    static func readAPIKey() -> String {
        let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        return env.isEmpty ? "YOUR_API_KEY_HERE" : env
    }
}
