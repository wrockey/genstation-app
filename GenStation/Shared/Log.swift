//
//  Log.swift
//  GenStation
//
//  Created by William Rockey on 12/13/25.
//


import os
import Foundation
import GenStationCore

// Global shared logger
private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "GenStation",  // fallback only
    category: "general"
)

// Convenience functions to replace your prints.
//
// **Every message is marked `privacy: .public`, deliberately.** `os.Logger` redacts interpolated
// strings by default, so without this every line reaches `log show` / `log stream` as the literal
// text `<private>` — which is what shipped, and which made a live failure impossible to investigate
// after the alert was dismissed. A 2026-07-28 live test hit exactly that: a reproducible API
// validation error, a full log capture, and not one readable line in it.
//
// What that costs: this app logs model ids, endpoints, parameter names and error bodies. None of
// that is user content — prompts and images are never passed to `Log` — but it is visible to anyone
// who can read this Mac's unified log. That is the trade being made on purpose, not by omission.
// **Do not pass a prompt, an API key or image data to these functions.** If you ever need to, log it
// with explicit `\(value, privacy: .private)` at the call site instead of widening this default.
enum Log {
    static func debug(_ message: String, file: String = #fileID, function: String = #function, line: Int = #line) {
        logger.debug("\(file, privacy: .public):\(line, privacy: .public) \(function, privacy: .public) – \(ProviderFailure.redact(message), privacy: .public)")
    }

    static func info(_ message: String) {
        logger.info("\(ProviderFailure.redact(message), privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(ProviderFailure.redact(message), privacy: .public)")
    }

    static func fault(_ message: String) {
        logger.fault("\(ProviderFailure.redact(message), privacy: .public)")
    }
}
