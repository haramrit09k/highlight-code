#if canImport(AppKit)
import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

/// Automatic updates through Sparkle, reading the feed attached to the latest GitHub
/// release (`SUFeedURL` in Info.plist). Release builds carry the public half of the
/// update-signing key (`SUPublicEDKey`); builds without it, such as local ones, have
/// updates switched off, because Sparkle refuses to install anything it can't verify.
final class Updater: NSObject, ObservableObject {
    @Published var automaticallyChecks = false {
        didSet {
            #if canImport(Sparkle)
            if controller?.updater.automaticallyChecksForUpdates != automaticallyChecks {
                controller?.updater.automaticallyChecksForUpdates = automaticallyChecks
            }
            #endif
        }
    }

    #if canImport(Sparkle)
    private var controller: SPUStandardUpdaterController?
    #endif

    /// Whether this build can update itself.
    var isAvailable: Bool {
        #if canImport(Sparkle)
        return controller != nil
        #else
        return false
        #endif
    }

    /// - Parameter start: false for snapshot and command-line modes, which must not
    ///   check for updates.
    init(start: Bool) {
        super.init()
        #if canImport(Sparkle)
        guard start, Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        #endif
    }

    func checkForUpdates() {
        #if canImport(Sparkle)
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
        #endif
    }
}

#if canImport(Sparkle)
extension Updater: SPUStandardUserDriverDelegate {
    /// This app has no Dock icon or menu bar, so Sparkle's own reminders would be easy to
    /// miss; bring its update window to the front instead.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
#endif
