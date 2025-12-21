//
//  LocationManager.swift
//  Weather Cub
//
//  Created by Nick Schneble on 8/13/25.
//

import Foundation
import CoreLocation
import Combine

final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let subject = PassthroughSubject<CLLocationCoordinate2D, Never>()

    var publisher: AnyPublisher<CLLocationCoordinate2D, Never> { subject.eraseToAnyPublisher() }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func request() { manager.requestWhenInUseAuthorization(); manager.requestLocation() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.first?.coordinate { subject.send(loc) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No-op: we allow fallback to last location string if provided
    }
}
