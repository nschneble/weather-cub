//
//  AppDelegate.swift
//  Weather Cub
//
//  Created by Nick Schneble on 8/13/25.
//

import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: MenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuController = MenuController()
        menuController.setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) { }
}
