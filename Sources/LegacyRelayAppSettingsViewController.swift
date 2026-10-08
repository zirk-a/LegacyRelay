import Foundation
import UIKit
import GeckoView

final class LegacyRelayAppSettingsViewController:
    UITableViewController,
    UIDocumentPickerDelegate
{
    private let userAgentSwitcherID =
        "user-agent-switcher@ninetailed.ninja"

    private var jitSwitch: UISwitch?
    private var jitPreparationStatus: String?
    private var jitPreparationPending = false
    private var jitRequestGeneration = 0

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError(
            "init(coder:) has not been implemented"
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "LegacyRelay Settings"

        LegacyRelayGeckoAddonManager
            .shared
            .activate()

        NotificationCenter.default.addObserver(
            self,
            selector:
                #selector(jitStatusDidChange(_:)),
            name:
                LegacyRelayJITStatus.notification,
            object: nil
        )
    }

    override func viewWillAppear(
        _ animated: Bool
    ) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }

    @objc private func jitStatusDidChange(
        _ notification: Notification
    ) {
        _ = notification

        DispatchQueue.main.async {
            [weak self] in

            self?.jitSwitch?.setOn(
                LegacyRelayJITStatus.enabled,
                animated: true
            )

            if LegacyRelayJITStatus.state == "active" || LegacyRelayJITStatus.state == "failed" {
                self?.jitPreparationStatus = nil
            }
            self?.tableView.reloadData()
        }
    }

    override func numberOfSections(
        in tableView: UITableView
    ) -> Int {
        return 2
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        return section == 0
            ? "App / Gecko"
            : "JIT"
    }

    override func tableView(
        _ tableView: UITableView,
        titleForFooterInSection section: Int
    ) -> String? {
        guard section == 1 else {
            return nil
        }

        return
            "Turn on LocalDevVPN before enabling JIT. " +
            "LegacyRelay uses Reynard's built-in RPPairing " +
            "backend on the Gecko tab process."
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        return section == 0 ? 2 : 2
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(
            style: (indexPath.section == 1 && indexPath.row == 1) ? .subtitle : .value1,
            reuseIdentifier: nil
        )

        if indexPath.section == 0 {
            if indexPath.row == 0 {
                cell.textLabel?.text =
                    "Add-ons"
                cell.accessoryType =
                    .disclosureIndicator
            } else {
                cell.textLabel?.text =
                    "Import Pairing File…"
                cell.detailTextLabel?.text =
                    pairingFileExists()
                    ? "Imported"
                    : "Not imported"
                cell.accessoryType =
                    .disclosureIndicator
            }

            return cell
        }

        if indexPath.row == 0 {
            cell.textLabel?.text =
                "Enable JIT"

            let control = UISwitch()
            control.isOn =
                LegacyRelayJITStatus.enabled || jitPreparationPending
            control.isEnabled = !jitPreparationPending
            control.addTarget(
                self,
                action: #selector(
                    jitSwitchChanged(_:)
                ),
                for: .valueChanged
            )

            jitSwitch = control
            cell.accessoryView = control
            cell.selectionStyle = .none
        } else {
            cell.textLabel?.text =
                "JIT Status"
            cell.detailTextLabel?.text =
                jitPreparationStatus ?? LegacyRelayJITStatus.statusText
            cell.selectionStyle = .none
            cell.isUserInteractionEnabled = false
        }

        return cell
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(
            at: indexPath,
            animated: true
        )

        guard indexPath.section == 0 else {
            return
        }

        if indexPath.row == 0 {
            openAddons()
        } else {
            importPairingFile()
        }
    }

    @objc private func jitSwitchChanged(_ sender: UISwitch) {
        jitRequestGeneration += 1
        let generation = jitRequestGeneration
        if !sender.isOn {
            jitPreparationPending = false
            jitPreparationStatus = nil
            LegacyRelayJITStatus.setEnabled(false)
            tableView.reloadData()
            return
        }
        guard pairingFileExists() else {
            sender.setOn(false, animated: true)
            jitPreparationStatus = "Import a pairing file first"
            tableView.reloadData()
            return
        }
        jitPreparationPending = true
        jitPreparationStatus = "Preparing Developer Image…"
        tableView.reloadData()
        LegacyRelayDDIPreparation.shared.ensure(
            progress: { [weak self] value in
                guard let self = self, self.jitRequestGeneration == generation else { return }
                let percent = min(99, Int(value * 100))
                self.jitPreparationStatus = "Downloading Developer Image: \(percent)%"
                self.tableView.reloadData()
            },
            completion: { [weak self] result in
                guard let self = self, self.jitRequestGeneration == generation else { return }
                self.jitPreparationPending = false
                switch result {
                case .success:
                    self.jitPreparationStatus = "Starting Gecko…"
                    LegacyRelayJITStatus.setEnabled(true)
                    self.tableView.reloadData()
                    LegacyRelaySettingsGeckoStarter.shared.start(
                        hostView: self.navigationController?.view ?? self.view
                    ) { [weak self] in
                        guard let self = self else { return }
                        self.jitPreparationStatus = nil
                        self.tableView.reloadData()
                    }
                case .failure(let error):
                    LegacyRelayJITStatus.setEnabled(false)
                    self.jitPreparationStatus = "Developer Image unavailable — retry"
                    self.tableView.reloadData()
                    NSLog("LegacyRelay DDI preparation failed: %@", error.localizedDescription)
                }
            }
        )
    }

    private func openAddons() {
        let manager = LegacyRelayAddonsViewController()
        navigationController?.pushViewController(manager, animated: true)
    }

    private func bundledUserAgentSwitcherURL()
        throws -> URL
    {
        guard let url =
            Bundle.main.url(
                forResource:
                    "uaswitcher-1.4.102",
                withExtension: "xpi"
            )
        else {
            throw NSError(
                domain:
                    "LegacyRelay.Addons",
                code: 404,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Bundled User-Agent Switcher " +
                        "XPI is missing."
                ]
            )
        }

        return url
    }

    private func reinstallUserAgentSwitcher() {
        Task { [weak self] in
            guard let self = self else {
                return
            }

            do {
                let installed =
                    try await AddonRuntime
                        .shared
                        .list()

                if let existing =
                    installed.first(
                        where: {
                            $0.id ==
                                self
                                .userAgentSwitcherID
                        }
                    )
                {
                    try await AddonRuntime
                        .shared
                        .uninstall(existing)
                }

                let xpiURL =
                    try self
                        .bundledUserAgentSwitcherURL()

                LegacyRelayGeckoAddonManager
                    .shared
                    .beginTrustedInstall(
                        addonID:
                            self
                            .userAgentSwitcherID
                    )

                defer {
                    LegacyRelayGeckoAddonManager
                        .shared
                        .endTrustedInstall()
                }

                _ = try await AddonRuntime
                    .shared
                    .install(
                        url:
                            xpiURL.absoluteString,
                        installMethod:
                            .manager
                    )

                DispatchQueue.main.async {
                    [weak self] in

                    self?.showMessage(
                        title:
                            "User-Agent Switcher",
                        message:
                            "Reinstalled successfully."
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    [weak self] in

                    self?.showMessage(
                        title:
                            "User-Agent Switcher",
                        message:
                            error.localizedDescription
                    )
                }
            }
        }
    }

    private func pairingFileURL() -> URL? {
        guard let documents =
            FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            ).first
        else {
            return nil
        }

        return documents
            .appendingPathComponent(
                "pairingFile.plist",
                isDirectory: false
            )
    }

    private func pairingFileExists() -> Bool {
        guard let url =
            pairingFileURL()
        else {
            return false
        }

        return FileManager.default
            .fileExists(
                atPath: url.path
            )
    }

    private func importPairingFile() {
        let picker =
            UIDocumentPickerViewController(
                documentTypes:
                    ["public.data"],
                in: .import
            )

        picker.delegate = self
        picker.allowsMultipleSelection =
            false

        present(
            picker,
            animated: true
        )
    }

    func documentPicker(
        _ controller:
            UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        _ = controller

        guard
            let sourceURL = urls.first,
            let destination =
                pairingFileURL()
        else {
            return
        }

        do {
            let fm =
                FileManager.default

            if fm.fileExists(
                atPath:
                    destination.path
            ) {
                try fm.removeItem(
                    at: destination
                )
            }

            try fm.copyItem(
                at: sourceURL,
                to: destination
            )

            tableView.reloadData()

            jitPreparationStatus = nil
            tableView.reloadData()
        } catch {
            showMessage(
                title:
                    "Pairing File Import Failed",
                message:
                    error.localizedDescription
            )
        }
    }

    private func showMessage(
        title: String,
        message: String
    ) {
        let alert =
            UIAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )

        alert.addAction(
            UIAlertAction(
                title: "OK",
                style: .default
            )
        )

        present(
            alert,
            animated: true
        )
    }
}


final class LegacyRelayAddonsViewController: UITableViewController, UIDocumentPickerDelegate {
    private var installed: [Addon] = []
    private var busy = false
    private var message = "Starting Gecko…"
    private let bundledID = "user-agent-switcher@ninetailed.ninja"
    private var didStartAddonList = false
    private var didCompleteAddonList = false
    private var bundledAddon: Addon? { installed.first { $0.id == bundledID } }
    private var otherAddons: [Addon] { installed.filter { $0.id != bundledID } }

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Add-ons"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .refresh, target: self, action: #selector(refreshTapped)
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !didStartAddonList {
            didStartAddonList = true
            refreshTapped()
        }
    }

    @objc private func refreshTapped() {
        guard !busy else { return }
        busy = true
        message = "Starting Gecko…"
        tableView.reloadData()
        LegacyRelaySettingsGeckoStarter.shared.start(
            hostView: navigationController?.view ?? view
        ) { [weak self] in
            guard let self = self else { return }
            self.message = "Loading Add-ons…"
            self.tableView.reloadData()
            Task { [weak self] in
                guard let self = self else { return }
                do {
                    let list = try await AddonRuntime.shared.list()
                    await MainActor.run {
                        self.didCompleteAddonList = true
                        self.installed = list.sorted {
                            ($0.metaData.name ?? $0.id).localizedCaseInsensitiveCompare(
                                $1.metaData.name ?? $1.id
                            ) == .orderedAscending
                        }
                        self.message = self.installed.isEmpty ? "No Add-ons Installed" : ""
                        self.busy = false
                        self.tableView.reloadData()
                    }
                } catch {
                    await MainActor.run {
                        self.message = "Couldn't load add-ons. Tap refresh to retry."
                        self.busy = false
                        self.tableView.reloadData()
                    }
                }
            }
        }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { return 2 }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Installed Add-ons" : nil
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? otherAddons.count + 1 : 3
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                cell.textLabel?.text = "User-Agent Switcher"
                if busy {
                    cell.detailTextLabel?.text = message
                } else if message.hasPrefix("Couldn't") {
                    cell.detailTextLabel?.text = message
                } else if let addon = bundledAddon {
                    cell.detailTextLabel?.text = addon.metaData.enabled
                        ? "Installed · Tap to choose a default User-Agent"
                        : "Disabled · Tap to enable and configure"
                } else {
                    cell.detailTextLabel?.text = busy
                        ? "Checking installation…"
                        : (didCompleteAddonList ? "Not installed · Tap to install" : "Checking installation…")
                }
                cell.accessoryType = .disclosureIndicator
            } else {
                let addon = otherAddons[indexPath.row - 1]
                cell.textLabel?.text = addon.metaData.name ?? addon.id
                cell.detailTextLabel?.text = addon.metaData.enabled ? "Enabled" : "Disabled"
                cell.accessoryType = .disclosureIndicator
            }
        } else {
            cell.textLabel?.text = ["Discover Add-ons…", "Install Add-on from File…", "Update All Add-ons"][indexPath.row]
            cell.textLabel?.textColor = .systemBlue
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !busy else { return }
        if indexPath.section == 0 {
            if indexPath.row == 0 {
                openOrInstallUserAgentSwitcher()
                return
            }
            let addon = otherAddons[indexPath.row - 1]
            let sheet = UIAlertController(title: addon.metaData.name ?? addon.id,
                                          message: "Version " + addon.metaData.version,
                                          preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: addon.metaData.enabled ? "Disable" : "Enable",
                                          style: .default) { [weak self] _ in
                self?.performAddonAction {
                    if addon.metaData.enabled { _ = try await AddonRuntime.shared.disable(addon) }
                    else { _ = try await AddonRuntime.shared.enable(addon) }
                }
            })
            sheet.addAction(UIAlertAction(title: "Check for Update", style: .default) { [weak self] _ in
                self?.performAddonAction { _ = try await AddonRuntime.shared.update(addon) }
            })
            if !addon.isBuiltIn {
                sheet.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
                    self?.performAddonAction { try await AddonRuntime.shared.uninstall(addon) }
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            if let pop = sheet.popoverPresentationController {
                pop.sourceView = tableView
                pop.sourceRect = tableView.rectForRow(at: indexPath)
            }
            present(sheet, animated: true)
        } else if indexPath.row == 0 {
            if let url = URL(string: "https://addons.mozilla.org/android/") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        } else if indexPath.row == 1 {
            let picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
            picker.delegate = self
            present(picker, animated: true)
        } else {
            performAddonAction {
                for addon in self.installed { _ = try await AddonRuntime.shared.update(addon) }
            }
        }
    }

    private func openOrInstallUserAgentSwitcher() {
        guard !busy else { return }
        busy = true
        message = bundledAddon == nil ? "Installing User-Agent Switcher…" : "Opening User-Agent Switcher…"
        tableView.reloadData()
        Task { [weak self] in
            guard let self = self else { return }
            do {
                guard let xpiURL = Bundle.main.url(
                    forResource: "uaswitcher-1.4.102", withExtension: "xpi"
                ) else {
                    throw NSError(domain: "LegacyRelay.Addons", code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "Bundled User-Agent Switcher is missing."])
                }
                let addon = try await LegacyRelayBundledAddonInstaller.shared.ensure(
                    addonID: self.bundledID, bundledURL: xpiURL)
                let ready = addon.metaData.enabled ? addon : try await AddonRuntime.shared.enable(addon)
                let list = (try? await AddonRuntime.shared.list()) ?? [ready]
                let popupURL = try await AddonRuntime.shared.clickAction(kind: .browser, addon: ready)
                await MainActor.run {
                    self.installed = list
                    self.didCompleteAddonList = true
                    self.busy = false
                    self.tableView.reloadData()
                    if let popupURL = popupURL, !popupURL.isEmpty {
                        let popup = LegacyRelayGeckoAddonPopupViewController(url: popupURL) { [weak self] in
                            guard let self = self else { return }
                            LegacyRelayUAApplyGate.begin()
                            self.message = "Applying User-Agent…"
                            self.tableView.reloadData()
                            Task { @MainActor [weak self] in
                                guard let self = self else {
                                    LegacyRelayUAApplyGate.finish()
                                    return
                                }
                                do {
                                    let latest = try await AddonRuntime.shared.addon(byID: self.bundledID) ?? ready
                                    let disabled = try await AddonRuntime.shared.disable(latest)
                                    _ = try await AddonRuntime.shared.enable(disabled)
                                    await MainActor.run {
                                        self.message = "User-Agent applied"
                                        self.tableView.reloadData()
                                        LegacyRelayUAApplyGate.finish()
                                    }
                                } catch {
                                    if let current = try? await AddonRuntime.shared.addon(byID: self.bundledID),
                                       !current.metaData.enabled {
                                        _ = try? await AddonRuntime.shared.enable(current)
                                    }
                                    NSLog("LegacyRelay: UA activation failed: %@", error.localizedDescription)
                                    await MainActor.run {
                                        self.message = "Couldn't apply User-Agent. Tap to retry."
                                        self.tableView.reloadData()
                                        LegacyRelayUAApplyGate.finish()
                                    }
                                }
                            }
                        }
                        let nav = UINavigationController(rootViewController: popup)
                        nav.modalPresentationStyle = .overFullScreen
                        self.present(nav, animated: true)
                    } else {
                        self.message = "Couldn't open the User-Agent selection. Tap to retry."
                        self.tableView.reloadData()
                    }
                }
            } catch {
                NSLog("LegacyRelay User-Agent settings failed: %@", error.localizedDescription)
                let recovered = try? await AddonRuntime.shared.list()
                await MainActor.run {
                    if let recovered = recovered {
                        self.installed = recovered
                    }
                    self.busy = false
                    self.message = self.bundledAddon == nil
                        ? "Couldn't install User-Agent Switcher. Tap to retry."
                        : "User-Agent Switcher installed. Tap to open."
                    self.tableView.reloadData()
                }
            }
        }
    }

    private func performAddonAction(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        message = "Updating Add-ons…"
        tableView.reloadData()
        Task { [weak self] in
            guard let self = self else { return }
            do { try await action() }
            catch {
                NSLog("LegacyRelay add-on operation: %@", error.localizedDescription)
                await MainActor.run {
                    self.message = "Couldn't complete the add-on operation."
                    self.busy = false
                    self.tableView.reloadData()
                }
                return
            }
            await MainActor.run { self.busy = false; self.refreshTapped() }
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, url.pathExtension.lowercased() == "xpi" else {
            message = "Select a Firefox .xpi add-on file."
            tableView.reloadData()
            return
        }
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".xpi")
        do { try FileManager.default.copyItem(at: url, to: destination) }
        catch { message = "Couldn't open that add-on file."; tableView.reloadData(); return }
        performAddonAction {
            defer { try? FileManager.default.removeItem(at: destination) }
            LegacyRelayGeckoAddonManager.shared.beginFileInstall(presenter: self)
            defer { LegacyRelayGeckoAddonManager.shared.endFileInstall() }
            _ = try await AddonRuntime.shared.install(url: destination.absoluteString, installMethod: .manager)
        }
    }
}
