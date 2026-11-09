//
//  SoftwareUpdater.swift
//
//  Graupel
//  https://github.com/ryanromanov/graupel
//
//  Created by ryanromanov on 2026-11-09.
//
//  ---------------------------------------------------------------------------
//
//  © 2026 Ryan Romanosky
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import Combine
import Sparkle

/// Graupel's in-app updates, handled by Sparkle.
///
/// The feed URL (`SUFeedURL`) and the public signing key (`SUPublicEDKey`) are in Info.plist.
/// Each GitHub release carries a signed `appcast.xml`, which `Scripts/release.sh` makes.
@MainActor final class SoftwareUpdater: ObservableObject {

    static let shared = SoftwareUpdater()

    /// Whether Sparkle checks for updates on its own schedule.
    @Published var checksAutomatically: Bool {
        didSet { self.updater.automaticallyChecksForUpdates = self.checksAutomatically }
    }

    /// Whether Sparkle downloads and installs an update without asking first.
    @Published var installsAutomatically: Bool {
        didSet { self.updater.automaticallyDownloadsUpdates = self.installsAutomatically }
    }

    private let controller: SPUStandardUpdaterController
    private var updater: SPUUpdater { self.controller.updater }


    private init() {

        self.controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.checksAutomatically = self.controller.updater.automaticallyChecksForUpdates
        self.installsAutomatically = self.controller.updater.automaticallyDownloadsUpdates
    }


    /// Whether a check can start now (false while one is already running).
    var canCheckForUpdates: Bool {

        self.updater.canCheckForUpdates
    }


    /// Checks for an update and shows the result.
    func checkForUpdates() {

        self.updater.checkForUpdates()
    }
}


extension AppDelegate: NSMenuItemValidation {

    /// Checks for a newer version of Graupel.
    @IBAction func checkForUpdates(_ sender: Any?) {

        SoftwareUpdater.shared.checkForUpdates()
    }


    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {

        switch menuItem.action {
            case #selector(checkForUpdates):
                SoftwareUpdater.shared.canCheckForUpdates
            default:
                true
        }
    }
}
