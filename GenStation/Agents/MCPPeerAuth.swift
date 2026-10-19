// MCPPeerAuth.swift
// Code-signature authentication of MCP socket peers (WS-7.1 Phase A). macOS only.
//
// A 0600 socket file does not stop another same-user process from connecting.
// On accept, authenticate the stdio process as this exact signed app executable.
// The small genstation-mcp launcher execs the app in MCP mode, which enters the
// app's own sandbox before reading any protocol messages.

#if os(macOS)
import Foundation
import Security

enum MCPPeerAuth {
    /// The signing team and bundle identifier are read from this running app, so
    /// any developer's own signed build trusts only helpers signed by that same
    /// team. Apple re-signs Mac App Store downloads with its store certificate;
    /// its leaf OU is not the development team. Both channels still require the
    /// app's code identifier, verified team metadata and exact executable path.
    private static func requirementString(team: String) -> String {
        let identifier = AppStorageContext.current.bundleID
        return "anchor apple generic and identifier \"\(identifier)\" and (certificate leaf[subject.OU] = \(team) or certificate leaf[field.1.2.840.113635.100.6.1.9] exists)"
    }

    /// Team identifier from this app's own code signature; nil when unsigned or
    /// ad-hoc signed. Restricted to alphanumerics before use in a requirement.
    private static let ownTeamIdentifier: String? = {
        var selfRef: SecCode?
        var staticRef: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &selfRef) == errSecSuccess, let selfCode = selfRef,
              SecCodeCopyStaticCode(selfCode, [], &staticRef) == errSecSuccess,
              let staticCode = staticRef,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return team
    }()

    static func isTrustedPeer(fd: Int32) -> Bool {
        // Bind every candidate to its own executable before considering
        // signature trust. This also prevents a demo helper reaching production.
        guard let pid = peerPID(fd: fd) else { return false }
        var codeRef: SecCode?
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &codeRef) == errSecSuccess,
              let code = codeRef else { return false }
        var information: CFDictionary?
        var staticRef: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticRef) == errSecSuccess,
              let staticCode = staticRef,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any],
              let peerURL = info[kSecCodeInfoMainExecutable as String] as? URL else { return false }
        guard let expected = Bundle.main.executableURL else { return false }
        guard peerURL.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath() else { return false }
        #if DEBUG
        // Local dev builds are unsigned/adhoc — skip so testing still works.
        return true
        #else
        guard let team = ownTeamIdentifier,
              info[kSecCodeInfoTeamIdentifier as String] as? String == team else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementString(team: team) as CFString, [], &requirement) == errSecSuccess,
              let req = requirement else { return false }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
        #endif
    }

    /// Effective pid of the socket peer via SO_PEERCRED-equivalent LOCAL_PEERCRED.
    private static func peerPID(fd: Int32) -> pid_t? {
        var cred = xucred()
        var len = socklen_t(MemoryLayout<xucred>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &cred, &len) == 0,
              cred.cr_version == XUCRED_VERSION else { return nil }
        // xucred carries the peer's credentials; pair with LOCAL_PEEREPID for pid.
        var pid: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEEREPID, &pid, &pidLen) == 0 else { return nil }
        return pid
    }
}
#endif
