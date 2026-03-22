import SwiftUI
import os

private let logger = Logger(subsystem: "com.ifcar.viewer", category: "App")

@main
struct IFCViewerApp: App {
    init() {
        // Catch uncaught exceptions
        NSSetUncaughtExceptionHandler { exception in
            logger.fault("UNCAUGHT EXCEPTION: \(exception.name.rawValue): \(exception.reason ?? "nil")")
            logger.fault("Stack: \(exception.callStackSymbols.joined(separator: "\n"))")
        }

        // Log signals
        for sig: Int32 in [SIGTRAP, SIGABRT, SIGBUS, SIGSEGV, SIGILL] {
            signal(sig) { s in
                let msg = "FATAL SIGNAL \(s) received"
                // Write to stderr since logger may not flush
                fputs("\(msg)\n", stderr)
            }
        }

        logger.info("IFCViewerApp initialized")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
