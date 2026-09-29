import Foundation

/// Thin wrapper around `xcodebuild test-without-building` that launches WDA on the sim.
///
/// For the sim-only MVP we keep this opt-in: if `autoLaunch = false` (the default), the
/// user runs `Scripts/launch-wda-sim.sh` in a separate terminal and the daemon probes
/// `http://localhost:8100/status` until WDA responds. Letting the user manage WDA
/// lifecycle avoids fighting with Xcode build locks when the daemon restarts.
final class WDALauncher {
    var onReady: (() -> Void)?
    var onExit: ((Int32) -> Void)?

    var autoLaunch: Bool = false
    private var process: Process?

    func start() {
        guard autoLaunch else {
            NSLog("[fadriver-mac] wda auto-launch disabled; expecting external launch-wda-sim.sh")
            return
        }
        guard let udid = ProcessInfo.processInfo.environment["FADRIVER_SIM_UDID"] else {
            NSLog("[fadriver-mac] wda auto-launch needs FADRIVER_SIM_UDID; or run Scripts/launch-wda-sim.sh")
            return
        }
        let xctestrun = findXctestrun()
        guard let xctestrun else {
            NSLog("[fadriver-mac] wda xctestrun not found; run Scripts/launch-wda-sim.sh to build first")
            return
        }

        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = [
            "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer",
            "xcrun", "xcodebuild", "test-without-building",
            "-xctestrun", xctestrun.path,
            "-destination", "id=\(udid)"
        ]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let line = String(data: handle.availableData, encoding: .utf8) ?? ""
            if line.contains("ServerURLHere") {
                self?.onReady?()
            }
        }
        p.terminationHandler = { [weak self] proc in
            self?.onExit?(proc.terminationStatus)
        }
        do {
            try p.run()
            self.process = p
            NSLog("[fadriver-mac] wda xcodebuild pid=\(p.processIdentifier)")
        } catch {
            NSLog("[fadriver-mac] wda launch failed: \(error)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func findXctestrun() -> URL? {
        let env = ProcessInfo.processInfo.environment
        let derivedOverride = env["FADRIVER_WDA_DERIVED"]
        let candidates: [URL] = {
            var out: [URL] = []
            if let derivedOverride { out.append(URL(fileURLWithPath: derivedOverride).appendingPathComponent("Build/Products")) }
            // Repo-local submodule-built artifacts
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            out.append(cwd.appendingPathComponent("build/wda/Build/Products"))
            return out
        }()
        for dir in candidates {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
               let match = contents.first(where: { $0.hasSuffix(".xctestrun") }) {
                return dir.appendingPathComponent(match)
            }
        }
        return nil
    }
}
