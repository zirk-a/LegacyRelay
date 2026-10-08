import Foundation
import GeckoView
import UIKit

final class LegacyRelayGeckoAddonManager: NSObject, AddonEmbedderDelegate {
    static let shared = LegacyRelayGeckoAddonManager()

    private var trustedInstallAddonID: String?
    private weak var installPresenter: UIViewController?

    func beginFileInstall(presenter: UIViewController) {
        installPresenter = presenter
        activate()
    }

    func endFileInstall() { installPresenter = nil }
    private(set) var lastInstallFailure: AddonInstallFailure?

    private override init() {
        super.init()
    }

    func activate() {
        AddonRuntime.shared.delegate = self
    }

    func beginTrustedInstall(addonID: String) {
        trustedInstallAddonID = addonID
        AddonRuntime.shared.delegate = self
    }

    func endTrustedInstall() {
        trustedInstallAddonID = nil
    }

    func addonController(_ controller: AddonRuntime, didUpdate addon: Addon) {
        _ = controller
        _ = addon
    }

    func addonController(
        _ controller: AddonRuntime,
        didFailInstall failure: AddonInstallFailure
    ) {
        _ = controller
        lastInstallFailure = failure
        NSLog(
            "LegacyRelay Gecko addon install failure: code=%@ id=%@ name=%@ version=%@",
            failure.code ?? "nil",
            failure.extensionID ?? "nil",
            failure.extensionName ?? "nil",
            failure.extensionVersion ?? "nil"
        )
    }

    @MainActor
    func addonController(
        _ controller: AddonRuntime,
        promptFor prompt: AddonPermissionPrompt
    ) async -> AddonPermissionPromptResponse {
        _ = controller

        if let trusted = trustedInstallAddonID, prompt.addon.id == trusted {
            return AddonPermissionPromptResponse(allow: true,
                privateBrowsingAllowed: false, technicalAndInteractionDataGranted: false)
        }
        guard let presenter = installPresenter, presenter.viewIfLoaded?.window != nil else {
            return .deny
        }
        return await withCheckedContinuation { continuation in
            let name = prompt.addon.metaData.name ?? "This add-on"
            let permissions = (prompt.permissions + prompt.origins + prompt.dataCollectionPermissions)
                .joined(separator: ", ")
            let detail = permissions.isEmpty ? "No additional permissions requested." : "Requested access: " + permissions
            let alert = UIAlertController(title: "Allow " + name + "?",
                message: detail, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Deny", style: .cancel) { _ in
                continuation.resume(returning: .deny)
            })
            alert.addAction(UIAlertAction(title: "Allow", style: .default) { _ in
                continuation.resume(returning: AddonPermissionPromptResponse(allow: true))
            })
            presenter.present(alert, animated: true)
        }
    }
}


@MainActor
final class LegacyRelayBundledAddonInstaller {
    static let shared = LegacyRelayBundledAddonInstaller()
    private var pending: Task<Addon, Error>?

    func ensure(addonID: String, bundledURL: URL) async throws -> Addon {
        if let running = pending { return try await running.value }
        if let found = AddonRuntime.shared.installedAddons.first(where: { $0.id == addonID }) {
            return found
        }
        let job = Task { @MainActor () throws -> Addon in
            if let found = AddonRuntime.shared.installedAddons.first(where: { $0.id == addonID }) {
                return found
            }
            let list = try await AddonRuntime.shared.list()
            if let found = list.first(where: { $0.id == addonID }) { return found }
            LegacyRelayGeckoAddonManager.shared.beginTrustedInstall(addonID: addonID)
            defer { LegacyRelayGeckoAddonManager.shared.endTrustedInstall() }
            do {
                return try await AddonRuntime.shared.install(
                    url: bundledURL.absoluteString, installMethod: .manager)
            } catch {
                if let recovered = try? await AddonRuntime.shared.list(),
                   let found = recovered.first(where: { $0.id == addonID }) {
                    return found
                }
                throw error
            }
        }
        pending = job
        defer { pending = nil }
        return try await job.value
    }
}
