#if canImport(AppKit)
import AppKit

/// Opening the app straight from Downloads (with the "downloaded from the internet" flag
/// still set) makes macOS run it from a random, read-only location ("App Translocation").
/// Each launch then looks like a different app: copies pile up, each with its own floating
/// button, and Services are routed to any of them. Offer to move it to Applications.
enum AppMover {
    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    /// Asks, then copies the app to Applications, clears the download flag, opens the copy
    /// and quits. Returns false if the user chose to keep running from here.
    @discardableResult
    static func offerToMove() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Move Highlight Code to Applications?"
        alert.informativeText = """
        It is running from a temporary location because it was opened straight from \\
        Downloads. Services and the floating button only work reliably from Applications.
        """
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let manager = FileManager.default
        let applications = manager.isWritableFile(atPath: "/Applications")
            ? URL(fileURLWithPath: "/Applications")
            : manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        let destination = applications.appendingPathComponent("Highlight Code.app")
        do {
            try manager.createDirectory(at: applications, withIntermediateDirectories: true)
            if manager.fileExists(atPath: destination.path) {
                try manager.trashItem(at: destination, resultingItemURL: nil)
            }
            try manager.copyItem(at: Bundle.main.bundleURL, to: destination)
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", destination.path]
            try xattr.run()
            xattr.waitUntilExit()
        } catch {
            DebugLog.write("move to Applications failed: \(error)")
            let failure = NSAlert(error: error)
            failure.runModal()
            return false
        }
        DebugLog.write("moved to \(destination.path); relaunching")
        NSWorkspace.shared.openApplication(at: destination, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
        return true
    }
}
#endif
