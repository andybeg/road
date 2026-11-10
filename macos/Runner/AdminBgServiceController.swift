import Darwin
import FlutterMacOS
import Foundation
import LocalAuthentication
import Security

// Builds without a Developer ID cannot use a Network Extension. Their VPN runs the full core in
// hiddify-core's tunnel service: the app's own executable, run as `Road --tunnel run` by launchd
// with administrator rights. This controller mirrors MacOSVPNController's method-channel contract
// (initialize/start/stop returning available, port, secret, status) so Dart can reuse the useTunnel path.
final class TunnelServiceController {
    private static let servicePort: UInt16 = 18020
    // Must match hiddify-core adminbgservice.controlDataDir() on darwin.
    private static let secretPath =
        "/Library/Application Support/Hiddify/AdminBgService/data/control.secret"
    private static let buildStampPath =
        "/Library/Application Support/Hiddify/AdminBgService/data/build.id"
    private let queue = DispatchQueue(label: "apple.andybeg.road.tunnel-service")
    private let processLock = NSLock()
    private var activeProcess: Process?
    private var connected = false
    /// True from the moment stop is requested until the disconnect child finishes.
    /// Keeps status from flipping back to "connected" if Flutter re-subscribes mid-stop.
    private var disconnecting = false
    private var lastMessage: String?
    private var pendingAuth: AuthorizationRef?
    /// Lets MacOSVPNController push EventChannel updates when our flags change.
    var onStateChanged: (() -> Void)?

    private var installScript: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("TunnelService/install-tunnel-service.sh")
    }

    var available: Bool {
        guard let script = installScript else { return false }
        return FileManager.default.fileExists(atPath: script.path)
    }

    func state() -> [String: Any] {
        let status: String
        if disconnecting {
            status = "disconnecting"
        } else if connected {
            status = "connected"
        } else {
            status = "disconnected"
        }
        var result: [String: Any] = [
            "available": available,
            "tunnelService": available,
            // True when the root service matches this app build (no password needed to connect).
            "serviceReady": serviceReady(),
            // The Flutter UI stays as the logged-in user. Root is only the launchd tunnel helper.
            "runningAsRoot": geteuid() == 0,
            "status": status,
            "activation": "idle",
            "port": Int(Self.servicePort),
        ]
        if let secret = try? Self.readSecret() { result["secret"] = secret }
        if let message = lastMessage { result["message"] = message }
        return result
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "installTunnelService":
            guard available else {
                result(Self.flutterError("The VPN service is missing from this build. Proxy modes are available."))
                return
            }
            ensureInstalled { error in
                if let error = error { result(Self.flutterError(error)) } else { result(nil) }
            }
        case "initialize", "status":
            result(state())
        case "start":
            guard available else {
                result(Self.flutterError("The VPN service is missing from this build. Proxy modes are available."))
                return
            }
            guard let arguments = call.arguments as? [String: Any] else {
                result(Self.flutterError("Missing VPN configuration."))
                return
            }
            queue.async {
                let error = self.start(arguments: arguments)
                DispatchQueue.main.async {
                    if let error = error {
                        self.connected = false
                        self.lastMessage = error
                        result(Self.flutterError(error))
                    } else {
                        self.connected = true
                        self.disconnecting = false
                        self.lastMessage = nil
                        self.onStateChanged?()
                        result(self.state())
                    }
                }
            }
        case "stop", "reset":
            // Mark disconnected before the slow child runs so a mid-stop EventChannel
            // re-subscribe (app switch) cannot report Connected again.
            connected = false
            disconnecting = true
            lastMessage = nil
            onStateChanged?()
            // Dart already stopped the engine over AdminBg gRPC — only clear flags
            // (spawning `Road --tunnel disconnect` again is what made stop take forever).
            let args = call.arguments as? [String: Any]
            let engineAlreadyStopped = args?["engineStopped"] as? Bool == true
            if engineAlreadyStopped && call.method == "stop" {
                NSLog("road tunnel-service: stop skipped child (engine already stopped via gRPC)")
                disconnecting = false
                onStateChanged?()
                result(state())
                return
            }
            // Interrupt a hung connect/disconnect child so this stop is not stuck behind it
            // on the serial queue.
            interruptActiveProcess()
            let stopStarted = Date()
            queue.async {
                let error = self.stopTunnel()
                let elapsed = Date().timeIntervalSince(stopStarted)
                NSLog("road tunnel-service: stop child finished in %.2fs error=%@", elapsed, error ?? "nil")
                DispatchQueue.main.async {
                    self.connected = false
                    self.disconnecting = false
                    self.lastMessage = error
                    self.onStateChanged?()
                    if call.method == "reset", let error = error {
                        result(Self.flutterError(error))
                    } else {
                        result(self.state())
                    }
                }
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func interruptActiveProcess() {
        processLock.lock()
        let process = activeProcess
        processLock.unlock()
        process?.terminate()
    }

    private func start(arguments: [String: Any]) -> String? {
        if let error = ensureInstalledSync() { return error }
        guard let configContent = arguments["configContent"] as? String, !configContent.isEmpty,
              let settingsJSON = arguments["settingsJSON"] as? String else {
            return "The VPN configuration is incomplete."
        }
        var resources: [String: String] = [:]
        for (name, value) in arguments["resources"] as? [String: FlutterStandardTypedData] ?? [:] {
            resources[name] = value.data.base64EncodedString()
        }
        let request: [String: Any] = [
            "configContent": configContent,
            "configName": arguments["configName"] as? String ?? "Road",
            "settingsJSON": settingsJSON,
            "resources": resources,
            "disableMemoryLimit": arguments["disableMemoryLimit"] as? Bool ?? false,
            "ownerPid": ProcessInfo.processInfo.processIdentifier,
        ]
        let requestURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("road-tunnel-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: requestURL) }
        do {
            let data = try JSONSerialization.data(withJSONObject: request)
            try data.write(to: requestURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
        } catch {
            return "Couldn't prepare the VPN configuration."
        }
        if let error = runTunnelCommand(["connect", requestURL.path]) { return error }
        return nil
    }

    private func stopTunnel() -> String? {
        runTunnelCommand(["disconnect"])
    }

    private func runTunnelCommand(_ arguments: [String]) -> String? {
        guard let executable = Bundle.main.executableURL?.path else {
            return "The app executable is missing."
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--tunnel"] + arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        processLock.lock()
        activeProcess = process
        processLock.unlock()
        defer {
            processLock.lock()
            if activeProcess === process { activeProcess = nil }
            processLock.unlock()
        }
        // Connect can hang on a wedged admin_bgservice; without a timeout the serial
        // queue blocks and further connect/stop taps never return (~1 min of "dead" UI).
        let command = arguments.first ?? "?"
        let timeoutSeconds: Double = command == "connect" ? 45 : 5
        let childStarted = Date()
        NSLog("road tunnel-service: spawning --tunnel %@", arguments.joined(separator: " "))
        let done = DispatchGroup()
        done.enter()
        process.terminationHandler = { _ in done.leave() }
        do {
            try process.run()
        } catch {
            return "Couldn't talk to the VPN service."
        }
        if done.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            NSLog("road tunnel-service: --tunnel %@ timed out after %.2fs", command, Date().timeIntervalSince(childStarted))
            process.terminate()
            _ = done.wait(timeout: .now() + 2)
            if command == "disconnect" { return nil }
            return "The VPN service timed out."
        }
        NSLog("road tunnel-service: --tunnel %@ finished in %.2fs status=%d",
              command, Date().timeIntervalSince(childStarted), process.terminationStatus)
        // Interrupted by stop/reset. Disconnect may be cancelled safely; a cancelled connect
        // must not report success (that left the UI as Connected then silently Disconnected).
        if process.terminationReason == .uncaughtSignal {
            if arguments.first == "disconnect" { return nil }
            return "The VPN connection was cancelled."
        }
        if process.terminationStatus == 0 { return nil }
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message?.isEmpty == false ? message : "The VPN service command failed."
    }

    private func ensureInstalled(_ completion: @escaping (String?) -> Void) {
        queue.async {
            let error = self.ensureInstalledSync()
            DispatchQueue.main.async { completion(error) }
        }
    }

    private func ensureInstalledSync() -> String? {
        // The build id lives only in hiddify-core (Go). Ask this app's core for it and compare
        // to the running service stamp — Dart never embeds the value.
        if serviceReady() { return nil }
        if let error = install() { return error }
        for _ in 0..<50 where !serviceReady() {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if !serviceReady() {
            if (try? Self.readSecret()) == nil {
                return "The VPN service secret is missing. Reinstall the VPN service."
            }
            if !Self.serviceListening() {
                return "The VPN service was installed but did not start."
            }
            return "The VPN service is still running a different Road core. Try connecting again."
        }
        return nil
    }

    private func serviceReady() -> Bool {
        guard (try? Self.readSecret()) != nil, Self.serviceListening(),
              let bundled = bundledCoreBuildId(),
              let stamped = try? Self.readBuildStamp() else { return false }
        return bundled == stamped
    }

    // Prints the build id embedded in this app's hiddify-core (via Road --tunnel build-id).
    private func bundledCoreBuildId() -> String? {
        guard let executable = Bundle.main.executableURL?.path else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--tunnel", "build-id"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let id = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty, id != "unset" else { return nil }
        return id
    }

    private static func readSecret() throws -> String {
        let secret = try String(contentsOfFile: secretPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard secret.count >= 32 else { throw CocoaError(.fileReadCorruptFile) }
        return secret
    }

    private static func readBuildStamp() throws -> String {
        try String(contentsOfFile: buildStampPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func serviceListening() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = servicePort.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    private func install() -> String? {
        #if ROAD_APP_STORE
        // the App Store build's tunnel is a sandboxed app extension: it never asks for root
        return "The VPN service is not part of the App Store build."
        #else
        guard let script = installScript?.path else { return "The VPN service is missing from this build." }
        let bundlePath = Bundle.main.bundlePath
        let owner = NSUserName()
        NSLog("road tunnel-service: install euid=%d script=%@", geteuid(), script)
        if geteuid() == 0 {
            return runInstallScript(script: script, bundlePath: bundlePath, owner: owner)
        }
        if let error = authenticateTouchID() { return error }
        if authenticateAdministrator() == nil, runInstallWithAuthorization(script: script, bundlePath: bundlePath, owner: owner) == nil {
            return nil
        }
        return runInstallWithOsascript(script: script, bundlePath: bundlePath, owner: owner)
        #endif
    }

    private func runInstallScript(script: String, bundlePath: String, owner: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script, bundlePath, owner]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            return "Couldn't install the VPN service."
        }
        process.waitUntilExit()
        if process.terminationStatus == 0 { return nil }
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return message?.isEmpty == false ? message : "Couldn't install the VPN service."
    }

    /// Touch ID / Optic ID first when the Mac has it. Nil means continue (success or no biometrics).
    private func authenticateTouchID() -> String? {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            NSLog("road tunnel-service: Touch ID unavailable (%@)", error?.localizedDescription ?? "none")
            return nil
        }
        var result: String?
        let done = DispatchSemaphore(value: 0)
        let reason = "Road needs administrator permission to run the VPN."
        context.localizedFallbackTitle = "Use Password"
        DispatchQueue.main.async {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, err in
                if success {
                    NSLog("road tunnel-service: Touch ID succeeded")
                } else if let laError = err as? LAError {
                    NSLog("road tunnel-service: Touch ID error %d", laError.code.rawValue)
                    switch laError.code {
                    case .userCancel, .appCancel, .systemCancel:
                        result = "Installing the VPN service was cancelled."
                    case .userFallback, .biometryNotAvailable, .biometryNotEnrolled, .biometryLockout:
                        break
                    default:
                        break
                    }
                }
                done.signal()
            }
        }
        done.wait()
        return result
    }

    /// System admin dialog (Touch ID when the OS offers it). Must run on the main thread.
    private func authenticateAdministrator() -> String? {
        var error: String?
        let work = {
            error = self.copyAdministratorRights()
        }
        if Thread.isMainThread {
            work()
        } else {
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                work()
                done.signal()
            }
            done.wait()
        }
        return error
    }

    private func copyAdministratorRights() -> String? {
        if let old = pendingAuth {
            AuthorizationFree(old, [.destroyRights])
            pendingAuth = nil
        }
        var auth: AuthorizationRef?
        var status = AuthorizationCreate(nil, nil, [], &auth)
        guard status == errAuthorizationSuccess, let auth else { return "Couldn't create an authorization session." }
        let prompt = "VPN mode sends all of this Mac's traffic through Road, which needs administrator permission. Use Touch ID, then the password if Touch ID is unavailable."
        status = kAuthorizationEnvironmentPrompt.withCString { promptName in
            prompt.withCString { promptCString in
                var promptItem = AuthorizationItem(
                    name: promptName,
                    valueLength: prompt.utf8.count + 1,
                    value: UnsafeMutableRawPointer(mutating: promptCString),
                    flags: 0
                )
                return withUnsafeMutablePointer(to: &promptItem) { itemPtr in
                    var environment = AuthorizationEnvironment(count: 1, items: itemPtr)
                    return "system.privilege.admin".withCString { name in
                        var right = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
                        return withUnsafeMutablePointer(to: &right) { rightPtr in
                            var rights = AuthorizationRights(count: 1, items: rightPtr)
                            return AuthorizationCopyRights(
                                auth,
                                &rights,
                                &environment,
                                [.interactionAllowed, .extendRights, .preAuthorize],
                                nil
                            )
                        }
                    }
                }
            }
        }
        NSLog("road tunnel-service: AuthorizationCopyRights status=%d", status)
        if status == errAuthorizationCanceled {
            AuthorizationFree(auth, [.destroyRights])
            return "Installing the VPN service was cancelled."
        }
        if status != errAuthorizationSuccess {
            AuthorizationFree(auth, [.destroyRights])
            return "Couldn't authorize administrator access."
        }
        pendingAuth = auth
        return nil
    }

    private func runInstallWithAuthorization(script: String, bundlePath: String, owner: String) -> String? {
        guard let execSymbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AuthorizationExecuteWithPrivileges") else {
            return "AuthorizationExecuteWithPrivileges is unavailable."
        }
        typealias AuthorizationExecuteWithPrivilegesFn = @convention(c) (
            AuthorizationRef, UnsafePointer<CChar>, AuthorizationFlags,
            UnsafePointer<UnsafeMutablePointer<CChar>?>,
            UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
        ) -> OSStatus
        let execute = unsafeBitCast(execSymbol, to: AuthorizationExecuteWithPrivilegesFn.self)
        guard let auth = pendingAuth else { return "Missing authorization." }
        pendingAuth = nil
        defer { AuthorizationFree(auth, [.destroyRights]) }
        var argv: [UnsafeMutablePointer<CChar>?] = [strdup(script), strdup(bundlePath), strdup(owner), nil]
        defer { argv.forEach { free($0) } }
        var pipe: UnsafeMutablePointer<FILE>?
        let status = argv.withUnsafeMutableBufferPointer { buffer in
            "/bin/bash".withCString { path in execute(auth, path, [], buffer.baseAddress!, &pipe) }
        }
        NSLog("road tunnel-service: AEWP status=%d", status)
        var output = ""
        if let pipe {
            let fd = fileno(pipe)
            var bytes = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = read(fd, &bytes, bytes.count)
                if n <= 0 { break }
                output += String(bytes: bytes[0..<n], encoding: .utf8) ?? ""
            }
            fclose(pipe)
        }
        if status != errAuthorizationSuccess {
            return "Couldn't install the VPN service."
        }
        if output.contains("Road VPN service installed") { return nil }
        return "privileged install produced no confirmation"
    }

    /// Password sheet used only when Touch ID and Authorization Services cannot elevate.
    private func runInstallWithOsascript(script: String, bundlePath: String, owner: String) -> String? {
        let quote = { (text: String) in
            "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let prompt = "VPN mode sends all of this Mac's traffic through Road, which needs administrator permission. Road asks for it once."
        let source = "do shell script \"/bin/bash \" & quoted form of \(quote(script)) & \" \" & quoted form of "
            + "\(quote(bundlePath)) & \" \" & quoted form of \(quote(owner)) with prompt "
            + "\(quote(prompt)) with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            return "Couldn't show the administrator password dialog."
        }
        process.waitUntilExit()
        let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        NSLog("road tunnel-service: osascript status=%d stderr=%@", process.terminationStatus, message)
        if process.terminationStatus == 0 { return nil }
        if message.contains("User canceled") || message.contains("-128") {
            return "Installing the VPN service was cancelled."
        }
        return message.isEmpty ? "Couldn't install the VPN service." : message
    }

    private static func flutterError(_ message: String) -> FlutterError {
        FlutterError(code: "MACOS_VPN", message: message, details: nil)
    }
}
