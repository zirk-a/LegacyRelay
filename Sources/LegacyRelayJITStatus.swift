import Foundation

@_silgen_name("LegacyRelaySetBuiltInJITEnabled")
private func LegacyRelaySetBuiltInJITEnabledC(
    _ enabled: Int32
)

enum LegacyRelayJITStatus {
    static let notification =
        Notification.Name(
            "LegacyRelay.JITStatusDidChange"
        )

    private static let defaults =
        UserDefaults.standard

    static var enabled: Bool {
        return defaults.bool(
            forKey: "LegacyRelay.JIT.enabled"
        )
    }

    static var state: String {
        return defaults.string(
            forKey: "LegacyRelay.JIT.state"
        ) ?? "off"
    }

    static var detail: String {
        return defaults.string(
            forKey: "LegacyRelay.JIT.detail"
        ) ?? ""
    }

    static var statusText: String {
        switch state {
        case "waiting":
            return "Waiting for Gecko"
        case "enabling":
            return "Enabling…"
        case "active":
            return "Active"
        case "failed":
            return "Failed"
        default:
            return "Off"
        }
    }

    static func setEnabled(_ enabled: Bool) {
        defaults.set(
            enabled,
            forKey: "LegacyRelay.JIT.enabled"
        )

        LegacyRelaySetBuiltInJITEnabledC(
            enabled ? 1 : 0
        )
    }
}


import GeckoView
import UIKit

final class LegacyRelaySettingsGeckoStarter {
    static let shared = LegacyRelaySettingsGeckoStarter()
    private let hostGeckoView = GeckoView(frame: CGRect(x: 2, y: 2, width: 16, height: 16))
    private var session: GeckoSession?
    private var starting = false
    private var completions: [() -> Void] = []
    private init() {
        hostGeckoView.isUserInteractionEnabled = false
        hostGeckoView.alpha = 0.03
    }

    func start(hostView: UIView, completion: @escaping () -> Void) {
        assert(Thread.isMainThread)
        if hostGeckoView.superview !== hostView {
            hostGeckoView.removeFromSuperview()
            hostView.insertSubview(hostGeckoView, at: 0)
        }
        if let existing = session {
            hostGeckoView.session = existing
            existing.setActive(true)
            existing.setAddonTabActive(true)
            completion()
            return
        }
        completions.append(completion)
        guard !starting else { return }
        starting = true
        LegacyRelayGeckoAddonManager.shared.activate()
        let mode = WebsiteModeSetting(
            userAgentOverride: nil, platformOverride: nil,
            appVersionOverride: nil, oscpuOverride: nil,
            buildIDOverride: nil, userAgentMode: 1, viewportMode: 1
        )
        let settings = GeckoSessionSettings(
            websiteMode: mode, pageZoom: .default, language: .default
        )
        let newSession = GeckoSession(settings: settings,
            isPrivateMode: false, isAddonPopup: false)
        session = newSession
        newSession.open()
        hostGeckoView.session = newSession
        newSession.setActive(true)
        newSession.setAddonTabActive(true)
        newSession.load("about:blank")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.starting = false
            let callbacks = self.completions
            self.completions.removeAll()
            callbacks.forEach { $0() }
        }
    }
}

final class LegacyRelayDDIPreparation {
    static let shared = LegacyRelayDDIPreparation()
    private var running = false
    private var generation = 0
    private var currentProgress: Double = 0
    private var progressListeners: [(Double) -> Void] = []
    private var completionListeners: [(Result<Void, Error>) -> Void] = []
    private init() {}

    func ensure(progress: @escaping (Double) -> Void,
                completion: @escaping (Result<Void, Error>) -> Void) {
        assert(Thread.isMainThread)
        progressListeners.append(progress)
        completionListeners.append(completion)
        if running {
            progress(currentProgress)
            return
        }
        running = true
        generation += 1
        let request = generation
        currentProgress = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self = self, self.running, self.generation == request else { return }
            NSLog("LegacyRelay DDI timed out after 300s; allowing user to retry")
            DDIManager.shared.cancelActiveDownload()
        }
        DDIManager.shared.ensureRequiredDDIFiles(
            progress: { [weak self] value in
                guard let self = self else { return }
                self.currentProgress = value
                self.progressListeners.forEach { $0(value) }
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.running = false
                let callbacks = self.completionListeners
                self.completionListeners.removeAll()
                self.progressListeners.removeAll()
                callbacks.forEach { $0(result) }
            }
        )
    }
}

enum LegacyRelayUAApplyGate {
    static let didFinish = Notification.Name("LegacyRelay.UserAgentDidApply")
    private(set) static var isApplying = false

    static func begin() {
        assert(Thread.isMainThread)
        isApplying = true
    }
    static func finish() {
        assert(Thread.isMainThread)
        isApplying = false
        NotificationCenter.default.post(name: didFinish, object: nil)
    }
}
