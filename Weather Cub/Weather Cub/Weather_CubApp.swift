//
//  Weather_CubApp.swift
//  Weather Cub
//
//  Created by Nick Schneble on 8/13/25.
//

import SwiftUI

@main
struct MenuBearApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() } // we use only the status bar menu
    }
}
