import Foundation
import UIKit
import GeckoView






final class LegacyRelayGeckoAddonPopupViewController: UIViewController {
    private let popupURL: String
    private let onDismiss: () -> Void
    private let geckoView = GeckoView(frame: .zero)
    private let popupSession: GeckoSession

    init(
        url: String,
        onDismiss: @escaping () -> Void
    ) {
        self.popupURL = url
        self.onDismiss = onDismiss

        
        
        let mode = WebsiteModeSetting(
            userAgentOverride: nil,
            platformOverride: nil,
            appVersionOverride: nil,
            oscpuOverride: nil,
            buildIDOverride: nil,
            userAgentMode: 0,
            viewportMode: 0
        )

        let settings = GeckoSessionSettings(
            websiteMode: mode,
            pageZoom: .default,
            language: .default
        )

        self.popupSession = GeckoSession(
            settings: settings,
            isPrivateMode: false,
            isAddonPopup: true
        )

        super.init(
            nibName: nil,
            bundle: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "User-Agent Switcher"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        geckoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(geckoView)

        NSLayoutConstraint.activate([
            geckoView.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor
            ),
            geckoView.leadingAnchor.constraint(
                equalTo: view.leadingAnchor
            ),
            geckoView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
            geckoView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor
            )
        ])

        popupSession.open()
        popupSession.setActive(true)
        popupSession.setFocused(true)
        geckoView.session = popupSession
        popupSession.load(popupURL)
    }

    @objc private func doneTapped() {
        dismiss(
            animated: true,
            completion: onDismiss
        )
    }
}

final class LegacyRelayGeckoViewController: UIViewController, UIDocumentPickerDelegate, AddonMessageDelegate {

    private static let snapSessionBridgeXPIBase64 = "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"
    private let snapSessionBridgeID =
        "legacyrelay-snap-session-v2@local"
    private let snapSessionBridgeNativeApp =
        "legacyrelay_snap_session"
    private var snapSessionPendingAction: String?
    private var snapSessionPendingCookies: [[String: Any]]?




    private let provider: RelayProvider
    private let geckoView = GeckoView(frame: .zero)
    private var session: GeckoSession

    private var userAgentSwitcherAddon: Addon?
    private var addonInstallInFlight = false
    private var initialAddonAttemptCompleted = false
    private var addonCheckSequence = 0
    private var addonCheckSkippedByUser = false
    private var addonRefreshPending = false
    private var addonCooldownPending = false
    private var initialProviderLoaded = false
    private var initialProviderNavigationRequested = false
    private var initialJITObserver: NSObjectProtocol?
    private var geckoDidStart = false
    private var geckoResetInFlight = false
    private var addonPopupPending = false
    private var skipJITForThisLaunch = false
    private var jitFailurePromptShown = false
    private var jitGeneration = 0
    private var tabStartupGeneration = 0
    private let startupPanel = UIView()
    private let startupSpinner = UIActivityIndicatorView(style: .large)
    private let startupLabel = UILabel()
    private let skipAddonCheckButton = UIButton(type: .system)


    private enum LegacyRelayImportPurpose {
        case session
        case pairingFile
    }

    private var importPurpose: LegacyRelayImportPurpose = .session

    private let userAgentSwitcherID = "user-agent-switcher@ninetailed.ninja"

    private func bundledUserAgentSwitcherURL() throws -> URL {
        guard let url = Bundle.main.url(
            forResource: "uaswitcher-1.4.102",
            withExtension: "xpi"
        ) else {
            throw NSError(
                domain: "LegacyRelay.Addons",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Bundled User-Agent Switcher XPI is missing."]
            )
        }
        return url
    }

    private static func makeContentSession() -> GeckoSession {
        
        
        let reynardDefaultMode = WebsiteModeSetting(
            userAgentOverride: nil,
            platformOverride: nil,
            appVersionOverride: nil,
            oscpuOverride: nil,
            buildIDOverride: nil,
            userAgentMode: 1,
            viewportMode: 1
        )

        let settings = GeckoSessionSettings(
            websiteMode: reynardDefaultMode,
            pageZoom: .default,
            language: .default
        )

        return GeckoSession(
            settings: settings,
            isPrivateMode: false,
            isAddonPopup: false
        )
    }

    init(provider: RelayProvider) {
        self.provider = provider
        self.session = Self.makeContentSession()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = provider.title
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "•••",
            style: .plain,
            target: self,
            action: #selector(moreTapped)
        )

        if let menuButton = navigationItem.rightBarButtonItem {
            let initializeButton = UIBarButtonItem(
                barButtonSystemItem: .refresh,
                target: self,
                action: #selector(initializeBrowserPreservingSession)
            )
            initializeButton.accessibilityLabel = "Initialize Browser"
            navigationItem.rightBarButtonItems = [menuButton, initializeButton]
        }

        geckoView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(geckoView)

        NSLayoutConstraint.activate([
            geckoView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            geckoView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            geckoView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            geckoView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        configureStartupPanel()
        updateStartup("Starting Gecko…")
        LegacyRelayGeckoAddonManager.shared.activate()
        initialAddonAttemptCompleted = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userAgentApplyFinished),
            name: LegacyRelayUAApplyGate.didFinish,
            object: nil
        )

        initialJITObserver = NotificationCenter.default.addObserver(
            forName: LegacyRelayJITStatus.notification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleJITUpdate()
        }

    }

    override func viewDidAppear(_ animated: Bool) {
        if provider.identifier.lowercased() == "snapchat",
           let notice = UserDefaults.standard.string(
                forKey: "LegacyRelay.Gecko.ImportNotice"
           ) {
            UserDefaults.standard.removeObject(
                forKey: "LegacyRelay.Gecko.ImportNotice"
            )
            showSessionNotice(notice)
        }

        super.viewDidAppear(animated)
        legacyRelayShowSnapImportResultOnce()

        if geckoDidStart {
            session.setActive(true)
            session.setFocused(true)
            session.setAddonTabActive(true)
            if addonRefreshPending && !geckoResetInFlight && !LegacyRelayUAApplyGate.isApplying {
                addonRefreshPending = false
                recreateContentSession()
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.startGeckoAfterAppearance()
        }
    }

    private func startGeckoAfterAppearance() {
        guard !geckoDidStart, viewIfLoaded?.window != nil else { return }
        geckoDidStart = true
        NSLog("LegacyRelay Gecko startup: opening session")
        session.open()
        NSLog("LegacyRelay Gecko startup: session opened")
        geckoView.session = session
        session.setActive(true)
        session.setFocused(true)
        session.setAddonTabActive(true)
        session.load("about:blank")
        if LegacyRelayJITStatus.enabled {
            prepareJITAndAddons()
        } else {
            prepareUserAgentSwitcherThenLoadProvider()
        }
    }

    deinit {
        if let observer = initialJITObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
        if geckoDidStart {
            session.setFocused(false)
            session.setActive(false)
            session.setAddonTabActive(false)
        }
    }

    @objc private func applicationDidBecomeActive() {
        guard viewIfLoaded?.window != nil, geckoDidStart else {
            return
        }

        session.setActive(true)
        session.setFocused(true)
        session.setAddonTabActive(true)
    }

    @objc private func applicationWillResignActive() {
        guard geckoDidStart else { return }
        session.setFocused(false)
        session.setActive(false)
    }

    private func configureStartupPanel() {
        startupPanel.translatesAutoresizingMaskIntoConstraints = false
        startupPanel.backgroundColor = .systemBackground
        startupLabel.translatesAutoresizingMaskIntoConstraints = false
        startupLabel.font = .systemFont(ofSize: 16, weight: .medium)
        startupLabel.textAlignment = .center
        startupLabel.numberOfLines = 0
        startupSpinner.translatesAutoresizingMaskIntoConstraints = false
        startupSpinner.startAnimating()
        startupPanel.addSubview(startupLabel)
        startupPanel.addSubview(startupSpinner)
        skipAddonCheckButton.translatesAutoresizingMaskIntoConstraints = false
        skipAddonCheckButton.setTitle("Continue without add-on", for: .normal)
        skipAddonCheckButton.isHidden = true
        skipAddonCheckButton.addTarget(self, action: #selector(skipAddonCheckTapped), for: .touchUpInside)
        startupPanel.addSubview(skipAddonCheckButton)
        view.addSubview(startupPanel)
        NSLayoutConstraint.activate([
            startupPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            startupPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            startupPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            startupPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            startupSpinner.centerXAnchor.constraint(equalTo: startupPanel.centerXAnchor),
            startupSpinner.centerYAnchor.constraint(equalTo: startupPanel.centerYAnchor, constant: -24),
            startupLabel.topAnchor.constraint(equalTo: startupSpinner.bottomAnchor, constant: 22),
            startupLabel.leadingAnchor.constraint(equalTo: startupPanel.leadingAnchor, constant: 18),
            startupLabel.trailingAnchor.constraint(equalTo: startupPanel.trailingAnchor, constant: -18),
            skipAddonCheckButton.centerXAnchor.constraint(equalTo: startupPanel.centerXAnchor),
            skipAddonCheckButton.topAnchor.constraint(equalTo: startupLabel.bottomAnchor, constant: 18),
            skipAddonCheckButton.leadingAnchor.constraint(greaterThanOrEqualTo: startupPanel.leadingAnchor, constant: 18),
            skipAddonCheckButton.trailingAnchor.constraint(lessThanOrEqualTo: startupPanel.trailingAnchor, constant: -18)
        ])
    }

    @objc private func skipAddonCheckTapped() {
        guard !skipAddonCheckButton.isHidden,
              !initialAddonAttemptCompleted,
              geckoDidStart,
              !LegacyRelayUAApplyGate.isApplying else { return }
        skipAddonCheckButton.isHidden = true
        addonCheckSkippedByUser = true
        addonInstallInFlight = false
        initialAddonAttemptCompleted = true
        updateStartup("Continuing without User-Agent Switcher…")
        loadInitialProviderWhenReady()
    }

    private func updateStartup(_ text: String) {
        startupLabel.text = text
        startupPanel.isHidden = false
        startupSpinner.startAnimating()
    }

    private func prepareJITAndAddons() {
        if skipJITForThisLaunch || !LegacyRelayJITStatus.enabled {
            prepareUserAgentSwitcherThenLoadProvider()
            return
        }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              FileManager.default.fileExists(atPath: docs.appendingPathComponent("pairingFile.plist").path) else {
            showJITFallback(reason: "Import a pairing file in Settings to enable JIT.")
            return
        }
        updateStartup("Preparing Developer Image…")
        let startupID = tabStartupGeneration
        DDIManager.shared.ensureRequiredDDIFiles(
            progress: { [weak self] value in
                guard let self = self, self.tabStartupGeneration == startupID else { return }
                self.updateStartup(String(format: "Downloading Developer Image: %.0f%%", value * 100))
            },
            completion: { [weak self] result in
                guard let self = self, self.tabStartupGeneration == startupID else { return }
                switch result {
                case .success: self.waitForJIT()
                case .failure(let error): self.showJITFallback(reason: error.localizedDescription)
                }
            }
        )
    }

    private func waitForJIT() {
        guard !skipJITForThisLaunch else { prepareUserAgentSwitcherThenLoadProvider(); return }
        updateStartup("Enabling JIT…")
        jitGeneration += 1
        let generation = jitGeneration
        LegacyRelayJITStatus.setEnabled(true)
        handleJITUpdate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in
            guard let self = self, self.jitGeneration == generation,
                  !self.initialProviderLoaded, !self.skipJITForThisLaunch else { return }
            if LegacyRelayJITStatus.state != "active" {
                self.showJITFallback(reason: "JIT could not be activated.")
            }
        }
    }

    private func handleJITUpdate() {
        guard geckoDidStart, LegacyRelayJITStatus.enabled,
              !skipJITForThisLaunch, !initialProviderLoaded else { return }
        switch LegacyRelayJITStatus.state {
        case "active":
            jitGeneration += 1
            prepareUserAgentSwitcherThenLoadProvider()
        case "failed":
            showJITFallback(reason: "JIT could not be activated.")
        default: break
        }
    }

    private func showJITFallback(reason: String) {
        guard !jitFailurePromptShown, !skipJITForThisLaunch,
              !initialProviderLoaded else { return }
        jitFailurePromptShown = true
        jitGeneration += 1
        updateStartup("JIT unavailable")
        let alert = UIAlertController(title: "JIT Unavailable",
            message: reason + " You can retry or continue. Some pages may not work correctly in JIT-less mode.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.jitFailurePromptShown = false
            self?.prepareJITAndAddons()
        })
        alert.addAction(UIAlertAction(title: "Continue JIT-less", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.skipJITForThisLaunch = true
            self.prepareUserAgentSwitcherThenLoadProvider()
        })
        present(alert, animated: true)
    }

    @objc private func userAgentApplyFinished() {
        guard geckoDidStart else { return }
        if initialProviderLoaded {
            if viewIfLoaded?.window != nil && !geckoResetInFlight {
                recreateContentSession()
            }
        } else if initialAddonAttemptCompleted {
            loadInitialProviderWhenReady()
        } else if !addonInstallInFlight {
            prepareUserAgentSwitcherThenLoadProvider()
        }
    }

    private func prepareUserAgentSwitcherThenLoadProvider() {
        if LegacyRelayUAApplyGate.isApplying {
            updateStartup("Applying User-Agent…")
            return
        }
        if initialAddonAttemptCompleted {
            loadInitialProviderWhenReady()
            return
        }
        guard !addonInstallInFlight else { return }
        updateStartup("Preparing User-Agent Switcher…")
        skipAddonCheckButton.isHidden = true
        addonCheckSkippedByUser = false
        addonInstallInFlight = true
        addonCheckSequence += 1
        let checkID = addonCheckSequence
        let startupID = tabStartupGeneration
        let isSnapchat = provider.identifier.lowercased() == "snapchat"
        addonCooldownPending = isSnapchat
        if isSnapchat {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self = self,
                      self.tabStartupGeneration == startupID,
                      self.addonCheckSequence == checkID else { return }
                self.updateStartup("Starting User-Agent Switcher…")
                self.startAddonEnsure(checkID: checkID, startupID: startupID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self = self,
                          self.tabStartupGeneration == startupID,
                          self.addonCheckSequence == checkID else { return }
                    self.addonCooldownPending = false
                    if !self.initialAddonAttemptCompleted {
                        self.addonCheckSkippedByUser = true
                        self.initialAddonAttemptCompleted = true
                    }
                    self.loadInitialProviderWhenReady()
                }
            }
        } else {
            startAddonEnsure(checkID: checkID, startupID: startupID)
        }
    }

    private func startAddonEnsure(checkID: Int, startupID: Int) {
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let xpiURL = try self.bundledUserAgentSwitcherURL()
                let addon = try await LegacyRelayBundledAddonInstaller.shared.ensure(
                    addonID: self.userAgentSwitcherID, bundledURL: xpiURL)
                let registered = addon
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          self.tabStartupGeneration == startupID,
                          self.addonCheckSequence == checkID else { return }
                    let needsRefresh = self.addonCheckSkippedByUser && self.initialProviderLoaded
                    self.userAgentSwitcherAddon = registered
                    self.session.setAddonTabActive(true)
                    self.addonInstallInFlight = false
                    self.initialAddonAttemptCompleted = true
                    self.addonCheckSkippedByUser = false
                    self.skipAddonCheckButton.isHidden = true
                    self.loadInitialProviderWhenReady()
                    if needsRefresh {
                        if LegacyRelayUAApplyGate.isApplying {
                            self.addonRefreshPending = false
                        } else if self.viewIfLoaded?.window != nil && !self.geckoResetInFlight {
                            self.recreateContentSession()
                        } else {
                            self.addonRefreshPending = true
                        }
                    }
                    if self.addonPopupPending {
                        self.addonPopupPending = false
                        self.openUserAgentSwitcher()
                    }
                }
            } catch {
                NSLog("LegacyRelay add-on recovery failed: %@", error.localizedDescription)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self,
                          self.tabStartupGeneration == startupID,
                          self.addonCheckSequence == checkID else { return }
                    self.addonInstallInFlight = false
                    guard !self.addonCheckSkippedByUser else { return }
                    self.initialAddonAttemptCompleted = false
                    if self.provider.identifier.lowercased() == "snapchat" {
                        self.updateStartup("User-Agent Switcher unavailable. Snapchat may use the wrong User-Agent.")
                    } else {
                        self.updateStartup("User-Agent Switcher unavailable. Wait, or continue without it when the option appears.")
                    }
                }
            }
        }
    }

    func beginProviderNavigationWhenReady() {
        initialProviderNavigationRequested = true
        loadInitialProviderWhenReady()
    }

    private func loadInitialProviderWhenReady() {
        guard initialProviderNavigationRequested &&
              geckoDidStart && !initialProviderLoaded else {
            return
        }
        guard initialAddonAttemptCompleted else { return }
        guard !addonCooldownPending else { return }
        guard !LegacyRelayUAApplyGate.isApplying else {
            updateStartup("Applying User-Agent…")
            return
        }
        if LegacyRelayJITStatus.enabled && !skipJITForThisLaunch {
            guard LegacyRelayJITStatus.state == "active" else { return }
        }

        initialProviderLoaded = true
        loadProvider()
    }

    private func loadProvider() {
        updateStartup("Loading " + provider.title + "…")
        session.load(provider.loginURL.absoluteString)
        let startupID = tabStartupGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self = self, self.tabStartupGeneration == startupID else { return }
            self.startupPanel.isHidden = true
            if self.geckoResetInFlight {
                self.geckoResetInFlight = false
                self.navigationItem.rightBarButtonItems?
                    .first(where: { $0.accessibilityLabel == "Initialize Browser" })?
                    .isEnabled = true
            }
        }
    }

    @objc private func moreTapped() {
        let sheet = UIAlertController(
            title: provider.title,
            message: "Session",
            preferredStyle: .actionSheet
        )

        sheet.addAction(UIAlertAction(
            title: "User-Agent Switcher…",
            style: .default
        ) { [weak self] _ in
            self?.openUserAgentSwitcher()
        })

        sheet.addAction(UIAlertAction(
            title: "Import Session",
            style: .default
        ) { [weak self] _ in
            self?.importSession()
        })

        sheet.addAction(UIAlertAction(
            title: "Export Session",
            style: .default
        ) { [weak self] _ in
            self?.exportSession()
        })

        sheet.addAction(UIAlertAction(
            title: "Clear \(provider.title) Session",
            style: .destructive
        ) { [weak self] _ in
            self?.confirmClearSession()
        })

        sheet.addAction(
            UIAlertAction(
                title: "Cancel",
                style: .cancel
            )
        )

        if let popover =
            sheet.popoverPresentationController
        {
            popover.barButtonItem =
                navigationItem.rightBarButtonItem
        }

        present(sheet, animated: true)
    }

    private func openUserAgentSwitcher() {
        guard let addon = userAgentSwitcherAddon else {
            addonPopupPending = true
            prepareUserAgentSwitcherThenLoadProvider()
            showSessionNotice("Loading add-on…")
            return
        }

        Task { [weak self] in
            guard let self = self else { return }

            do {
                
                
                self.session.setAddonTabActive(true)

                let popupURL = try await AddonRuntime.shared.clickAction(
                    kind: .browser,
                    addon: addon
                )

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }

                    if let popupURL = popupURL, !popupURL.isEmpty {
                        self.presentUserAgentSwitcherPopup(url: popupURL)
                    } else {
                        self.showMessage(
                            title: "User-Agent Switcher",
                            message: "The add-on action did not return a popup URL."
                        )
                    }
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.showMessage(
                        title: "User-Agent Switcher",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func recreateContentSession() {
        let previous = session

        previous.setAddonTabActive(false)
        previous.setFocused(false)
        previous.setActive(false)

        geckoView.session = nil
        previous.close()

        let replacement = Self.makeContentSession()
        session = replacement

        replacement.open()
        replacement.setActive(true)
        replacement.setFocused(true)
        geckoView.session = replacement
        replacement.setAddonTabActive(true)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.session === replacement else { return }
            replacement.load(self.provider.loginURL.absoluteString)
        }

        NSLog(
            "LegacyRelay Gecko: recreated provider content session"
        )
    }

    private func presentUserAgentSwitcherPopup(url: String) {
        let popup = LegacyRelayGeckoAddonPopupViewController(
            url: url
        ) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.geckoDidStart, !self.geckoResetInFlight else { return }
                self.recreateContentSession()
            }
        }

        let navigationController = UINavigationController(
            rootViewController: popup
        )

        navigationController.modalPresentationStyle = .overFullScreen
        navigationController.isModalInPresentation = false

        present(
            navigationController,
            animated: true
        )
    }

    private func reinstallUserAgentSwitcher() {
        Task { [weak self] in
            guard let self = self else { return }

            do {
                let installed = try await AddonRuntime.shared.list()

                if let existing = installed.first(where: { $0.id == self.userAgentSwitcherID }) {
                    try await AddonRuntime.shared.uninstall(existing)
                }

                let xpiURL = try self.bundledUserAgentSwitcherURL()
                LegacyRelayGeckoAddonManager.shared.beginTrustedInstall(
                    addonID: self.userAgentSwitcherID
                )
                defer {
                    LegacyRelayGeckoAddonManager.shared.endTrustedInstall()
                }
                let addon = try await AddonRuntime.shared.install(
                    url: xpiURL.absoluteString,
                    installMethod: .manager
                )

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.userAgentSwitcherAddon = addon
                    self.showMessage(
                        title: "User-Agent Switcher",
                        message: "Reinstalled. Open User-Agent Switcher and select Windows / Chrome 147 [Desktop]."
                    )
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.showMessage(
                        title: "User-Agent Switcher",
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func importSession() {
        importPurpose = .session

        let picker = UIDocumentPickerViewController(
            documentTypes: ["public.data"],
            in: .import
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func importPairingFile() {
        importPurpose = .pairingFile

        let picker = UIDocumentPickerViewController(
            documentTypes: ["public.data"],
            in: .import
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    private func standardPairingFileURL() throws -> URL {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(
                domain: "LegacyRelay.JIT",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Documents directory is unavailable."]
            )
        }
        return documents.appendingPathComponent("pairingFile.plist", isDirectory: false)
    }

    private func installPairingFile(from sourceURL: URL) throws {
        let destination = try standardPairingFileURL()
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
    }

    private func prepareStandardJIT() {
        let pairingURL: URL
        do {
            pairingURL = try standardPairingFileURL()
        } catch {
            showMessage(title: "Prepare JIT Failed", message: error.localizedDescription)
            return
        }

        guard FileManager.default.fileExists(atPath: pairingURL.path) else {
            showMessage(
                title: "Pairing File Required",
                message: "Import pairingFile.plist first. Keep LocalDevVPN connected whenever you use Gecko with JIT."
            )
            return
        }

        DDIManager.shared.ensureRequiredDDIFiles(
            progress: { progress in
                NSLog("LegacyRelay JIT: DDI download %.0f%%", progress * 100)
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success:
                    self.showMessage(
                        title: "JIT Ready",
                        message: "Pairing file and Developer Disk Image are ready. Keep LocalDevVPN connected, then close and reopen LegacyRelay once so new Gecko tab processes start with JIT."
                    )
                case .failure(let error):
                    self.showMessage(title: "Prepare JIT Failed", message: error.localizedDescription)
                }
            }
        )
    }

    private func legacyRelayShowSnapImportResultOnce() {
        guard provider.identifier.lowercased() == "snapchat" else { return }
        let key = "LegacyRelay.Gecko.ImportNotice"
        guard let notice = UserDefaults.standard.string(forKey: key) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        showSessionNotice(notice)
    }

    private func exportSession() {
        guard provider.identifier.lowercased() == "snapchat" else { return }
        let selectedProvider = provider
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let url = try LegacyRelayGeckoSessionArchive.exportSession(provider: selectedProvider)
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    let share = UIActivityViewController(
                        activityItems: [url], applicationActivities: nil
                    )
                    if let pop = share.popoverPresentationController {
                        pop.barButtonItem = self.navigationItem.rightBarButtonItem
                    }
                    self.present(share, animated: true)
                }
            } catch {
                NSLog("LegacyRelay: full session export failed: %@", error.localizedDescription)
                DispatchQueue.main.async { [weak self] in
                    self?.showSessionNotice("Couldn't export this session.")
                }
            }
        }
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        _ = controller
        guard let url = urls.first else { return }
        switch importPurpose {
        case .pairingFile:
            do {
                try installPairingFile(from: url)
                showSessionNotice("Pairing file imported.")
            } catch {
                NSLog("LegacyRelay pairing file import failed: %@", error.localizedDescription)
                showSessionNotice("Couldn't import the pairing file.")
            }
        case .session:
            guard provider.identifier.lowercased() == "snapchat" else {
                showSessionNotice("Session import is available for Snapchat only.")
                return
            }
            let selectedProvider = provider.identifier
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try LegacyRelayGeckoSessionArchive.stageCompatibleImport(
                        archiveURL: url, providerIdentifier: selectedProvider
                    )
                    DispatchQueue.main.async { [weak self] in
                        self?.showSessionNotice("Import ready. Fully close and reopen LegacyRelay.")
                    }
                } catch {
                    NSLog("LegacyRelay: session import rejected: %@", error.localizedDescription)
                    DispatchQueue.main.async { [weak self] in
                        self?.showSessionNotice("Couldn't import this session. Your existing session was kept.")
                    }
                }
            }
        }
    }

    

    @objc private func initializeBrowserPreservingSession() {
        guard geckoDidStart, !geckoResetInFlight else { return }
        guard !addonInstallInFlight, !LegacyRelayUAApplyGate.isApplying else {
            updateStartup("Finishing Add-ons…")
            return
        }
        guard presentedViewController == nil else { return }
        geckoResetInFlight = true
        tabStartupGeneration += 1
        addonCheckSequence += 1
        addonCheckSkippedByUser = false
        addonRefreshPending = false
        addonCooldownPending = false
        skipAddonCheckButton.isHidden = true
        jitGeneration += 1 // Supersede pending JIT timeout from the old tab.
        initialAddonAttemptCompleted = false
        initialProviderLoaded = false
        initialProviderNavigationRequested = true
        jitFailurePromptShown = false
        userAgentSwitcherAddon = nil // Only refresh handle, never uninstall.
        navigationItem.rightBarButtonItems?
            .first(where: { $0.accessibilityLabel == "Initialize Browser" })?
            .isEnabled = false
        updateStartup("Closing Gecko tab…")
        let oldSession = session
        oldSession.setAddonTabActive(false)
        oldSession.setFocused(false)
        oldSession.setActive(false)
        geckoView.session = nil
        oldSession.close()
        let newSession = Self.makeContentSession()
        session = newSession
        updateStartup("Starting Gecko…")
        newSession.open()
        geckoView.session = newSession
        newSession.setActive(true)
        newSession.setFocused(true)
        newSession.setAddonTabActive(true)
        newSession.load("about:blank")
        NSLog("LegacyRelay Initialize: replaced Gecko tab; browser profile preserved")
        let startupID = tabStartupGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.tabStartupGeneration == startupID,
                  self.session === newSession else { return }
            if LegacyRelayJITStatus.enabled && !self.skipJITForThisLaunch {
                self.prepareJITAndAddons()
            } else {
                self.prepareUserAgentSwitcherThenLoadProvider()
            }
        }
    }

    private func confirmClearSession() {
        let alert = UIAlertController(
            title: "Clear \(provider.title) Session?",
            message:
                "This clears cookies, authentication sessions and website " +
                "storage for this isolated Gecko provider. " +
                "User-Agent Switcher and its saved settings are preserved. The Gecko tab is recreated immediately.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(
            title: "Cancel",
            style: .cancel
        ))

        alert.addAction(UIAlertAction(
            title: "Clear Session",
            style: .destructive
        ) { [weak self] _ in
            guard let self = self else { return }
            guard !self.geckoResetInFlight, self.geckoDidStart else { return }
            self.geckoResetInFlight = true

            Task { [weak self] in
                guard let self = self else { return }

                do {
                    try await GeckoStorageController.clearData(
                        flags:
                            GeckoStorageClearFlags.cookies |
                            GeckoStorageClearFlags.authSessions
                    )

                    try await GeckoStorageController.clearData(
                        flags: GeckoStorageClearFlags.domStorages
                    )

                    await MainActor.run {
                        self.recreateContentSession()
                        self.geckoResetInFlight = false
                        self.showSessionNotice("Session cleared.")
                    }
                } catch {
                    await MainActor.run {
                        self.geckoResetInFlight = false
                        self.showSessionNotice("Couldn't clear the session. Please try again.")
                    }
                }
            }
        })

        present(alert, animated: true)
    }





    private func showSessionNotice(_ message: String) {
        let tag = 971728
        view.viewWithTag(tag)?.removeFromSuperview()
        let panel = UIView()
        panel.tag = tag
        panel.backgroundColor = UIColor(white: 0.13, alpha: 0.94)
        panel.layer.cornerRadius = 12
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.alpha = 0
        panel.isUserInteractionEnabled = false
        let label = UILabel()
        label.text = message
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 3
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(label)
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 28),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -28),
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            label.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 15),
            label.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -15),
            label.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12)
        ])
        UIView.animate(withDuration: 0.18) { panel.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak panel] in
            guard let panel = panel else { return }
            UIView.animate(withDuration: 0.22, animations: {
                panel.alpha = 0
            }, completion: { _ in panel.removeFromSuperview() })
        }
    }


    func addonMessage(
        _ message: Any,
        nativeApp: String,
        sender: AddonMessageSender
    ) async throws -> Any? {
        guard nativeApp == snapSessionBridgeNativeApp,
              sender.extensionID == snapSessionBridgeID,
              let payload = message as? [String: Any],
              (payload["legacyRelaySnapSession"] as? Bool) == true else {
            return nil
        }

        return handleSnapSessionBridgeMessage(payload)
    }


    private func snapSessionBridgeURL() throws -> URL {
        guard let data = Data(
            base64Encoded: Self.snapSessionBridgeXPIBase64
        ) else {
            throw NSError(
                domain: "LegacyRelay.SnapSession",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Snapchat session bridge is invalid."
                ]
            )
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "legacyrelay-snap-session-bridge.xpi"
            )

        try data.write(to: url, options: .atomic)
        return url
    }

    private func beginSnapSessionBridge(
        action: String,
        cookies: [[String: Any]]? = nil
    ) {
        guard provider.identifier.lowercased() == "snapchat" else {
            showMessage(
                title: "Session",
                message: "Snapchat session import/export is Snapchat-only."
            )
            return
        }

        guard snapSessionPendingAction == nil else { return }
        snapSessionPendingAction = action
        snapSessionPendingCookies = cookies

        session.setAddonMessageDelegate(
            self,
            extensionID: snapSessionBridgeID,
            nativeApp: snapSessionBridgeNativeApp
        )
        session.setAddonTabActive(true)

        Task { [weak self] in
            guard let self = self else { return }

            do {
                var existing = AddonRuntime.shared.installedAddons.first {
                    $0.id == self.snapSessionBridgeID
                }
                if existing == nil {
                    do {
                        existing = try await AddonRuntime.shared.list().first {
                            $0.id == self.snapSessionBridgeID
                        }
                    } catch {
                        NSLog("SnapTransfer: addon list unavailable, attempting direct install: %@", error.localizedDescription)
                    }
                }
                if existing == nil {
                    let xpi = try self.snapSessionBridgeURL()
                    LegacyRelayGeckoAddonManager.shared.beginTrustedInstall(
                        addonID: self.snapSessionBridgeID
                    )
                    defer {
                        LegacyRelayGeckoAddonManager.shared.endTrustedInstall()
                        try? FileManager.default.removeItem(at: xpi)
                    }
                    _ = try await AddonRuntime.shared.install(
                        url: xpi.absoluteString, installMethod: .manager
                    )
                }
                DispatchQueue.main.async { [weak self] in
                    self?.session.reload()
                }
            } catch {
                self.snapSessionPendingAction = nil
                self.snapSessionPendingCookies = nil

                DispatchQueue.main.async { [weak self] in
                    self?.showSessionNotice(
                        "Import/Export: " + error.localizedDescription
                    )
                }
            }
        }
    }

    private func handleSnapSessionBridgeMessage(
        _ payload: [String: Any]
    ) -> Any? {
        let op = payload["op"] as? String ?? ""

        switch op {
        case "pullAction":
            guard let action = snapSessionPendingAction else {
                return ["action": "none"]
            }

            if action == "import" {
                return [
                    "action": "import",
                    "cookies": snapSessionPendingCookies ?? []
                ]
            }

            if action == "export" {
                return ["action": "export"]
            }

            return ["action": "none"]

        case "exportResult":
            guard snapSessionPendingAction == "export",
                  let cookies =
                    payload["cookies"] as? [[String: Any]] else {
                return ["ok": false]
            }

            snapSessionPendingAction = nil
            snapSessionPendingCookies = nil

            let object: [String: Any] = [
                "format": "legacyrelay-session-v1",
                "version": 1,
                "provider": provider.identifier,
                "providerTitle": provider.title,
                "browserProfile": provider.browserProfile.rawValue,
                "profile": [
                    "type": provider.browserProfile.rawValue,
                    "userAgent": ""
                ],
                "cookies": cookies,
                "exportedAt":
                    ISO8601DateFormatter().string(from: Date())
            ]

            DispatchQueue.main.async { [weak self] in
                self?.shareSnapSessionObject(object)
            }

            return ["ok": true]

        case "importResult":
            let ok = payload["ok"] as? Bool ?? false
            let message = payload["error"] as? String

            snapSessionPendingAction = nil
            snapSessionPendingCookies = nil

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                if ok {
                    self.showSessionNotice("Sessione Snapchat importata.")
                } else {
                    self.showSessionNotice(message ?? "Importazione non riuscita.")
                }
            }

            return ["ok": true]

        case "bridgeError":
            let message = payload["error"] as? String ??
                "Unknown session bridge error."

            snapSessionPendingAction = nil
            snapSessionPendingCookies = nil

            DispatchQueue.main.async { [weak self] in
                self?.showMessage(
                    title: "Operazione non riuscita",
                    message: message
                )
            }

            return ["ok": true]

        default:
            return nil
        }
    }

    private func shareSnapSessionObject(
        _ object: [String: Any]
    ) {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
            )

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("snapchat.mgsession")

            try data.write(to: url, options: .atomic)

            let share = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )

            if let popover = share.popoverPresentationController {
                popover.barButtonItem =
                    navigationItem.rightBarButtonItem
            }

            present(share, animated: true)
        } catch {
            showMessage(
                title: "Esportazione non riuscita",
                message: error.localizedDescription
            )
        }
    }

    private func cookiesFromSnapSession(
        at url: URL
    ) throws -> [[String: Any]] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        guard data.count <= 8 * 1024 * 1024 else {
            throw NSError(domain: "LegacyRelay.SnapSession", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Il file di sessione è troppo grande."])
        }
        let fullProfileMagic =
            Data("LEGACYRELAY_GECKO_SESSION_V1\n".utf8)

        if data.starts(with: fullProfileMagic) {
            throw NSError(
                domain: "LegacyRelay.SnapSession",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Questo vecchio backup non è compatibile. " +
                        "Esporta una sessione Snapchat aggiornata."
                ]
            )
        }

        guard let any = try JSONSerialization.jsonObject(
                with: data,
                options: []
              ) as? [String: Any],
              (any["format"] as? String) ==
                "legacyrelay-session-v1",
              (any["version"] as? NSNumber)?.intValue == 1,
              (any["provider"] as? String)?
                .lowercased() == "snapchat",
              let cookies =
                any["cookies"] as? [[String: Any]],
              !cookies.isEmpty, cookies.count <= 1500 else {
            throw NSError(
                domain: "LegacyRelay.SnapSession",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This is not a compatible Snapchat session file."
                ]
            )
        }

        for cookie in cookies {
            guard let domain = cookie["domain"] as? String,
                  let name = cookie["name"] as? String,
                  let value = cookie["value"] as? String,
                  !name.isEmpty, name.count < 1024, value.count < 65536,
                  !name.contains(";"), !name.contains("\n"),
                  !domain.contains("/"), !domain.contains(":"),
                  !domain.contains("@") else {
                throw NSError(
                    domain: "LegacyRelay.SnapSession",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The Snapchat session contains an invalid cookie."
                    ]
                )
            }

            let host = domain
                .trimmingCharacters(
                    in: CharacterSet(charactersIn: ".")
                )
                .lowercased()

            guard host == "snapchat.com" ||
                  host.hasSuffix(".snapchat.com") ||
                  host == "snapkit.com" ||
                  host.hasSuffix(".snapkit.com") else {
                throw NSError(
                    domain: "LegacyRelay.SnapSession",
                    code: 5,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "The session contains a non-Snapchat cookie."
                    ]
                )
            }
        }

        return cookies
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
