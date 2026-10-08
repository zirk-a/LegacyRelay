import Foundation
import UIKit
import WebKit
import GeckoView



enum RelayEngine: String, Codable {
    case webKit
    case gecko
}

enum RelayBrowserProfile: String, Codable {
    case native
    case chromeMacOS

    var title: String {
        switch self {
        case .native:
            return "Native WebKit"
        case .chromeMacOS:
            return "Chrome • macOS (Desktop)"
        }
    }
}

struct RelayProvider {
    let identifier: String
    let title: String
    let symbol: String
    let loginURL: URL
    let browserProfile: RelayBrowserProfile
    let engine: RelayEngine

    static let builtIns: [RelayProvider] = [
        RelayProvider(
            identifier: "instagram",
            title: "Instagram",
            symbol: "◎",
            loginURL: URL(string: "https://www.instagram.com/accounts/login/")!,
            browserProfile: .native,
            engine: .webKit
        ),
        RelayProvider(
            identifier: "snapchat",
            title: "Snapchat",
            symbol: "👻",
            loginURL: URL(string: "https://web.snapchat.com/")!,
            browserProfile: .chromeMacOS,
            engine: .gecko
        )
    ]

    static var initialGeckoProviderIdentifier: String {
        return builtIns.first(where: { $0.engine == .gecko })?.identifier ?? "gecko-default"
    }

    static func custom(url: URL, profile: RelayBrowserProfile, engine: RelayEngine = .webKit) -> RelayProvider {
        let host = url.host?.lowercased() ?? "custom"
        let safeHost = host
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return RelayProvider(
            identifier: "custom-" + safeHost,
            title: host,
            symbol: "+",
            loginURL: url,
            browserProfile: profile,
            engine: engine
        )
    }
}



private struct RelaySavedSite: Codable {
    let id: String
    var title: String
    var address: String
    var engine: RelayEngine

    var provider: RelayProvider? {
        guard let url = URL(string: address), let host = url.host,
              !host.isEmpty else { return nil }
        return RelayProvider(identifier: "saved-" + id, title: title,
                             symbol: "🌐", loginURL: url,
                             browserProfile: .native, engine: engine)
    }
}

struct RelaySessionCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let httpOnly: Bool
    let sessionOnly: Bool
    let expires: TimeInterval?
}

struct RelaySessionProfile: Codable {
    let type: String
    let userAgent: String
    let pageLanguage: String?
}

struct LegacyMagnistraSession: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let profile: RelaySessionProfile
    let cookies: [RelaySessionCookie]
}

struct LegacyRelayExportedSession: Codable {
    let format: String
    let version: Int
    let exportedAt: String
    let provider: String
    let providerTitle: String
    let browserProfile: String
    let profile: RelaySessionProfile
    let cookies: [RelaySessionCookie]
}

struct LegacyRelayPersistedSession: Codable {
    let version: Int
    let provider: String
    let browserProfile: String
    let observedUserAgent: String?
    let cookies: [RelaySessionCookie]
}



enum LegacyRelaySessionStore {
    private static func rootDirectory() -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let root = base
            .appendingPathComponent("LegacyRelay", isDirectory: true)
            .appendingPathComponent("Sessions", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: nil
            )
            return root
        } catch {
            return nil
        }
    }

    private static func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "_" }
            .joined()
    }

    private static func fileURL(for provider: String) -> URL? {
        return rootDirectory()?
            .appendingPathComponent(safeName(provider))
            .appendingPathExtension("json")
    }

    static func load(provider: String) -> LegacyRelayPersistedSession? {
        guard let url = fileURL(for: provider),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LegacyRelayPersistedSession.self, from: data),
              decoded.provider == provider else {
            return nil
        }
        return decoded
    }

    static func save(_ session: LegacyRelayPersistedSession) {
        guard let url = fileURL(for: session.provider),
              let data = try? JSONEncoder().encode(session) else {
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        } catch {
            return
        }
    }

    static func clear(provider: String) {
        guard let url = fileURL(for: provider) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}



final class RelayHomeViewController: UIViewController {
    private var cachedControllers: [String: UIViewController] = [:]
    private var geckoPrewarmJITObserver: NSObjectProtocol?
    private let savedSitesKey = "LegacyRelay.SavedCustomSites.v1"
    private var savedSites: [RelaySavedSite] = []
    private weak var savedSitesRow: UIStackView?

    deinit {
        if let observer = geckoPrewarmJITObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        LegacyRelayJITStatus.setEnabled(true)
        title = "LegacyRelay"
        view.backgroundColor = .systemBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Settings",
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )

        if let data = UserDefaults.standard.data(forKey: savedSitesKey),
           let loaded = try? JSONDecoder().decode([RelaySavedSite].self, from: data) {
            savedSites = loaded
        }
        configureGrid()
    }

    @objc private func settingsTapped() {
        let controller =
            LegacyRelayAppSettingsViewController()

        navigationController?.pushViewController(
            controller,
            animated: true
        )
    }

    private func configureGeckoPrewarmObserver() {
        guard geckoPrewarmJITObserver == nil else { return }
        geckoPrewarmJITObserver = NotificationCenter.default.addObserver(
            forName: LegacyRelayJITStatus.notification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startGeckoPrewarmIfNeeded()
        }
        startGeckoPrewarmIfNeeded()
    }

    private func startGeckoPrewarmIfNeeded() {
        guard LegacyRelayJITStatus.enabled else { return }
        guard let provider = RelayProvider.builtIns.first(
            where: { $0.engine == .gecko }
        ) else { return }

        let defaultProvider = RelayProvider.initialGeckoProviderIdentifier
        guard LegacyRelayGeckoProfile.isActive(
            providerIdentifier: provider.identifier,
            default: defaultProvider
        ) else { return }

        let key = provider.identifier + "|" +
            provider.browserProfile.rawValue + "|" + provider.engine.rawValue
        guard cachedControllers[key] == nil else { return }

        
        
        let controller = LegacyRelayGeckoViewController(provider: provider)
        cachedControllers[key] = controller
        controller.loadViewIfNeeded()
        NSLog("LegacyRelay Gecko: offscreen JIT prewarm started")
    }

    private func configureGrid() {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let defaultsLabel = UILabel()
        defaultsLabel.text = "DEFAULT SITES"
        defaultsLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        defaultsLabel.textColor = .secondaryLabel
        container.addArrangedSubview(defaultsLabel)

        let row = UIStackView()
        row.axis = .horizontal
        row.distribution = .fill
        row.alignment = .fill
        row.spacing = 14
        for (index, provider) in RelayProvider.builtIns.enumerated() {
            let tile = ProviderTile(provider: provider)
            tile.tag = index
            tile.addTarget(self, action: #selector(providerTapped(_:)),
                           for: .touchUpInside)
            tile.widthAnchor.constraint(equalToConstant: ProviderTile.bookmarkWidth).isActive = true
            tile.heightAnchor.constraint(equalToConstant: ProviderTile.bookmarkHeight).isActive = true
            row.addArrangedSubview(tile)
        }
        let spacer = UIView()
        spacer.isUserInteractionEnabled = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)
        container.addArrangedSubview(row)
        row.heightAnchor.constraint(equalToConstant: ProviderTile.bookmarkHeight).isActive = true

        let customHeader = UILabel()
        customHeader.text = "CUSTOM SITES"
        customHeader.font = .systemFont(ofSize: 12, weight: .semibold)
        customHeader.textColor = .secondaryLabel
        container.setCustomSpacing(22, after: row)
        container.addArrangedSubview(customHeader)

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.delaysContentTouches = false
        container.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(equalToConstant: ProviderTile.bookmarkHeight).isActive = true
        let savedRow = UIStackView()
        savedRow.axis = .horizontal
        savedRow.alignment = .fill
        savedRow.spacing = 12
        savedRow.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(savedRow)
        NSLayoutConstraint.activate([
            savedRow.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            savedRow.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            savedRow.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            savedRow.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            savedRow.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor)
        ])
        savedSitesRow = savedRow
        refreshSavedSites()
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    private func refreshSavedSites() {
        guard let row = savedSitesRow else { return }
        row.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, site) in savedSites.enumerated() {
            guard let provider = site.provider else { continue }
            let tile = ProviderTile(provider: provider)
            tile.tag = index
            tile.addTarget(self, action: #selector(savedSiteTapped(_:)), for: .touchUpInside)
            let press = UILongPressGestureRecognizer(target: self,
                                                     action: #selector(savedSiteLongPressed(_:)))
            press.minimumPressDuration = 0.5
            tile.addGestureRecognizer(press)
            tile.widthAnchor.constraint(equalToConstant: ProviderTile.bookmarkWidth).isActive = true
            tile.heightAnchor.constraint(equalToConstant: ProviderTile.bookmarkHeight).isActive = true
            row.addArrangedSubview(tile)
        }
        let add = ProviderTile(title: "Add Custom", symbol: "+")
        add.widthAnchor.constraint(equalToConstant: ProviderTile.bookmarkWidth).isActive = true
        add.heightAnchor.constraint(equalToConstant: ProviderTile.bookmarkHeight).isActive = true
        add.addTarget(self, action: #selector(customTapped), for: .touchUpInside)
        row.addArrangedSubview(add)
    }

    private func persistSavedSites() {
        guard let data = try? JSONEncoder().encode(savedSites) else { return }
        UserDefaults.standard.set(data, forKey: savedSitesKey)
        refreshSavedSites()
    }

    @objc private func savedSiteTapped(_ sender: UIControl) {
        guard savedSites.indices.contains(sender.tag),
              let provider = savedSites[sender.tag].provider else { return }
        open(provider)
    }

    @objc private func savedSiteLongPressed(_ sender: UILongPressGestureRecognizer) {
        guard sender.state == .began,
              let tile = sender.view,
              savedSites.indices.contains(tile.tag) else { return }
        let index = tile.tag
        let site = savedSites[index]
        let sheet = UIAlertController(title: site.title, message: nil,
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Edit", style: .default) { [weak self] _ in
            self?.editSite(at: index)
        })
        sheet.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.confirmDeleteSite(at: index)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = tile
            pop.sourceRect = tile.bounds
        }
        present(sheet, animated: true)
    }

    private func confirmDeleteSite(at index: Int) {
        guard savedSites.indices.contains(index) else { return }
        let site = savedSites[index]
        let alert = UIAlertController(title: "Delete " + site.title + "?",
                                      message: "Only the shortcut will be removed. Browser data is not deleted.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self = self,
                  let current = self.savedSites.firstIndex(where: { $0.id == site.id }) else { return }
            self.savedSites.remove(at: current)
            self.cachedControllers = self.cachedControllers.filter {
                !$0.key.hasPrefix("saved-" + site.id + "|")
            }
            self.persistSavedSites()
        })
        present(alert, animated: true)
    }

    private func editSite(at index: Int?) {
        let existing: RelaySavedSite?
        if let index = index, savedSites.indices.contains(index) {
            existing = savedSites[index]
        } else { existing = nil }
        let alert = UIAlertController(title: existing == nil ? "Add Custom Site" : "Edit Custom Site",
                                      message: "Enter a name and website URL.", preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "Site name"
            field.text = existing?.title
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "https://example.com"
            field.text = existing?.address
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        for engine in [RelayEngine.webKit, RelayEngine.gecko] {
            let label = engine == .gecko ? "Save · Gecko" : "Save · WebKit"
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self, weak alert] _ in
                guard let self = self else { return }
                let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                var address = alert?.textFields?.last?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !address.contains("://") { address = "https://" + address }
                guard !name.isEmpty, name.count <= 80,
                      let url = URL(string: address), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      (components.scheme == "https" || components.scheme == "http"),
                      components.host != nil, components.user == nil, components.password == nil else {
                    self.showInvalidURL()
                    return
                }
                if let existing = existing,
                   let oldIndex = self.savedSites.firstIndex(where: { $0.id == existing.id }) {
                    self.savedSites[oldIndex] = RelaySavedSite(id: existing.id, title: name,
                                                              address: address, engine: engine)
                    self.cachedControllers = self.cachedControllers.filter {
                        !$0.key.hasPrefix("saved-" + existing.id + "|")
                    }
                } else {
                    self.savedSites.append(RelaySavedSite(id: UUID().uuidString,
                                                         title: name, address: address, engine: engine))
                }
                self.persistSavedSites()
            })
        }
        present(alert, animated: true)
    }

    @objc private func providerTapped(_ sender: UIControl) {
        guard sender.tag >= 0,
              sender.tag < RelayProvider.builtIns.count else {
            return
        }
        open(RelayProvider.builtIns[sender.tag])
    }

    @objc private func customTapped() {
        editSite(at: nil)
    }

    private func showInvalidURL() {
        let alert = UIAlertController(title: "Invalid URL", message: "Enter a valid web address.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func open(_ provider: RelayProvider) {
        guard Thread.isMainThread,
              let safeNavigation = navigationController,
              safeNavigation.topViewController === self,
              safeNavigation.transitionCoordinator == nil else { return }

        let key = provider.identifier + "|" + provider.browserProfile.rawValue + "|" + provider.engine.rawValue
        let controller: UIViewController
        if let cached = cachedControllers[key] {
            controller = cached
        } else if provider.engine == .gecko {
            controller = LegacyRelayGeckoViewController(provider: provider)
            cachedControllers[key] = controller
        } else {
            controller = ProviderSessionViewController(provider: provider)
            cachedControllers[key] = controller
        }
        if let gecko = controller as? LegacyRelayGeckoViewController {
            gecko.beginProviderNavigationWhenReady()
        }
        safeNavigation.legacyRelayPushProviderIfSafe(controller, animated: true)
    }
}

final class ProviderTile: UIControl {
    static let bookmarkWidth: CGFloat = 72
    static let bookmarkHeight: CGFloat = 88
    private static let artworkSide: CGFloat = 58

    private let iconLabel = UILabel()
    private let coverView = UIImageView()
    private let nameLabel = UILabel()

    convenience init(provider: RelayProvider) {
        self.init(title: provider.title, symbol: provider.symbol)
        let resource: String?
        switch provider.identifier {
        case "instagram": resource = "LegacyInstagramCover.PNG"
        case "snapchat": resource = "LegacySnapchatCover.JPG"
        default: resource = nil
        }
        guard let resource = resource, let image = UIImage(named: resource) else { return }
        if provider.identifier == "snapchat", let bitmap = image.cgImage {
            let side = CGFloat(min(bitmap.width, bitmap.height))
            let inset = side * 0.075
            let region = CGRect(x: inset, y: inset,
                                width: CGFloat(bitmap.width) - 2 * inset,
                                height: CGFloat(bitmap.height) - 2 * inset).integral
            if let cropped = bitmap.cropping(to: region) {
                coverView.image = UIImage(cgImage: cropped,
                                          scale: image.scale,
                                          orientation: image.imageOrientation)
            } else {
                coverView.image = image
            }
        } else {
            coverView.image = image
        }
        coverView.isHidden = false
        iconLabel.isHidden = true
    }

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = title

        iconLabel.text = symbol
        iconLabel.font = .systemFont(ofSize: 30, weight: .medium)
        iconLabel.textColor = .label
        iconLabel.textAlignment = .center
        iconLabel.backgroundColor = .secondarySystemBackground
        iconLabel.layer.cornerRadius = 13
        iconLabel.layer.masksToBounds = true
        iconLabel.adjustsFontSizeToFitWidth = true
        iconLabel.minimumScaleFactor = 0.65
        iconLabel.isUserInteractionEnabled = false
        iconLabel.translatesAutoresizingMaskIntoConstraints = false

        coverView.contentMode = .scaleAspectFill
        coverView.clipsToBounds = true
        coverView.layer.cornerRadius = 13
        coverView.layer.cornerCurve = .continuous
        coverView.isHidden = true
        coverView.isUserInteractionEnabled = false
        coverView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.text = title
        nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        nameLabel.textAlignment = .center
        nameLabel.textColor = .label
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.65
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.numberOfLines = 1
        nameLabel.isUserInteractionEnabled = false
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconLabel)
        addSubview(coverView)
        addSubview(nameLabel)
        NSLayoutConstraint.activate([
            iconLabel.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            iconLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconLabel.widthAnchor.constraint(equalToConstant: Self.artworkSide),
            iconLabel.heightAnchor.constraint(equalToConstant: Self.artworkSide),

            coverView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            coverView.centerXAnchor.constraint(equalTo: centerXAnchor),
            coverView.widthAnchor.constraint(equalToConstant: Self.artworkSide),
            coverView.heightAnchor.constraint(equalToConstant: Self.artworkSide),

            nameLabel.topAnchor.constraint(equalTo: coverView.bottomAnchor, constant: 4),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameLabel.heightAnchor.constraint(equalToConstant: 21)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1.0 }
    }
}

final class ProviderSessionViewController:
    UIViewController,
    WKNavigationDelegate,
    WKUIDelegate,
    UIDocumentPickerDelegate {

    private let provider: RelayProvider
    private var webView: WKWebView!
    private var importedUserAgent: String?

    private let chromeMacUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/154.0.0.0 Safari/537.36"

    init(provider: RelayProvider) {
        self.provider = provider
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
        rebuildWebView(restorePersistedSession: true)
    }

    private func rebuildWebView(restorePersistedSession: Bool) {
        webView?.removeFromSuperview()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = provider.identifier == "instagram"
            ? WKWebsiteDataStore.default()
            : WKWebsiteDataStore.nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        if shouldUseChromeMacOS {
            configuration.defaultWebpagePreferences.preferredContentMode = .desktop
            configuration.userContentController.addUserScript(
                WKUserScript(
                    source: Self.chromeDesktopCompatibilityJavaScript,
                    injectionTime: .atDocumentStart,
                    forMainFrameOnly: false
                )
            )
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = provider.identifier != "instagram"
        webView.translatesAutoresizingMaskIntoConstraints = false

        if shouldUseChromeMacOS {
            webView.customUserAgent = chromeMacUserAgent
        } else if webKitUserAgentPreference == nil,
                  provider.identifier != "instagram",
                  let importedUserAgent = importedUserAgent,
                  !importedUserAgent.isEmpty {
            webView.customUserAgent = importedUserAgent
        }

        self.webView = webView
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        if shouldUseChromeMacOS {
            if #available(iOS 14.0, *) {
                webView.pageZoom = 0.82
            }
        }

        if restorePersistedSession,
           let saved = LegacyRelaySessionStore.load(provider: provider.identifier) {
            if webKitUserAgentPreference == nil && provider.identifier != "instagram" {
                importedUserAgent = saved.observedUserAgent
                if let userAgent = saved.observedUserAgent,
                   !userAgent.isEmpty {
                    webView.customUserAgent = userAgent
                }
            } else if shouldUseChromeMacOS {
                importedUserAgent = chromeMacUserAgent
                webView.customUserAgent = chromeMacUserAgent
            } else {
                importedUserAgent = nil
                webView.customUserAgent = nil
            }
            installCookies(saved.cookies) { [weak self] _ in
                self?.loadLogin()
            }
        } else {
            loadLogin()
        }
    }

    private func loadLogin() {
        webView.load(URLRequest(url: provider.loginURL))
    }

    @objc private func moreTapped() {
        let sheet = UIAlertController(title: provider.title, message: provider.browserProfile.title, preferredStyle: .actionSheet)

        sheet.addAction(UIAlertAction(title: "Export Session", style: .default) { [weak self] _ in
            self?.exportSession()
        })
        sheet.addAction(UIAlertAction(title: "Import Session", style: .default) { [weak self] _ in
            self?.importSessionPicker()
        })
        sheet.addAction(UIAlertAction(title: "User-Agent…", style: .default) { [weak self] _ in
            self?.showWebKitUserAgentPicker()
        })
        sheet.addAction(UIAlertAction(title: "Reload Login Page", style: .default) { [weak self] _ in
            self?.loadLogin()
        })
        sheet.addAction(UIAlertAction(title: "Clear Session", style: .destructive) { [weak self] _ in
            self?.confirmClearSession()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        present(sheet, animated: true)
    }

    private var webKitUserAgentPreferenceKey: String {
        return "LegacyRelay.WebKit.UserAgent." + provider.identifier
    }

    private var webKitUserAgentPreference: String? {
        return UserDefaults.standard.string(
            forKey: webKitUserAgentPreferenceKey
        )
    }

    private var shouldUseChromeMacOS: Bool {
        if let preference = webKitUserAgentPreference {
            return preference == "chrome-macos"
        }
        return provider.browserProfile == .chromeMacOS
    }

    private func showWebKitUserAgentPicker() {
        let sheet = UIAlertController(
            title: "User-Agent",
            message: shouldUseChromeMacOS
                ? "Chrome macOS"
                : "Native WebKit",
            preferredStyle: .actionSheet
        )

        sheet.addAction(UIAlertAction(
            title: "Native WebKit",
            style: .default
        ) { [weak self] _ in
            self?.setWebKitUserAgentPreference("native")
        })

        sheet.addAction(UIAlertAction(
            title: "Chrome macOS",
            style: .default
        ) { [weak self] _ in
            self?.setWebKitUserAgentPreference("chrome-macos")
        })

        sheet.addAction(UIAlertAction(
            title: "Cancel",
            style: .cancel
        ))

        if let popover = sheet.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }

        present(sheet, animated: true)
    }

    private func setWebKitUserAgentPreference(_ value: String) {
        UserDefaults.standard.set(
            value,
            forKey: webKitUserAgentPreferenceKey
        )
        UserDefaults.standard.synchronize()

        importedUserAgent = nil
        rebuildWebView(restorePersistedSession: true)
    }

    private func confirmClearSession() {
        let alert = UIAlertController(
            title: "Clear \(provider.title)?",
            message: "Only this provider's LegacyRelay session will be removed.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            LegacyRelaySessionStore.clear(provider: self.provider.identifier)
            self.importedUserAgent = nil
            if self.provider.identifier == "instagram" {
                let store = WKWebsiteDataStore.default()
                let types = WKWebsiteDataStore.allWebsiteDataTypes()
                store.fetchDataRecords(ofTypes: types) { [weak self] records in
                    let instagramRecords = records.filter { record in
                        let domain = record.displayName.lowercased()
                        return domain == "instagram.com" || domain.hasSuffix(".instagram.com")
                    }
                    store.removeData(ofTypes: types, for: instagramRecords) { [weak self] in
                        DispatchQueue.main.async {
                            self?.rebuildWebView(restorePersistedSession: false)
                        }
                    }
                }
            } else {
                self.rebuildWebView(restorePersistedSession: false)
            }
        })
        present(alert, animated: true)
    }

    private func importSessionPicker() {
        let picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importSession(from: url)
    }

    private func importSession(from url: URL) {
        do {
            if provider.identifier == "snapchat" {
                try LegacyRelayGeckoSessionArchive.stageImport(
                    archiveURL: url,
                    providerIdentifier: provider.identifier
                )
                showMessage(
                    title: "Session Imported",
                    message: "The Snapchat Gecko session is ready to apply. Close and reopen LegacyRelay manually when you want to activate it."
                )
                return
            }

            let data = try Data(contentsOf: url)

            if let generic = try? JSONDecoder().decode(LegacyRelayExportedSession.self, from: data),
               generic.format == "legacyrelay-session-v1",
               generic.version == 1 {
                guard generic.provider == provider.identifier else {
                    showMessage(
                        title: "Wrong Provider",
                        message: "This session belongs to \(generic.providerTitle), not \(provider.title)."
                    )
                    return
                }
                importedUserAgent = generic.profile.userAgent
                let persisted = LegacyRelayPersistedSession(
                    version: 1,
                    provider: provider.identifier,
                    browserProfile: generic.browserProfile,
                    observedUserAgent: generic.profile.userAgent,
                    cookies: generic.cookies
                )
                LegacyRelaySessionStore.save(persisted)
                rebuildWebView(restorePersistedSession: true)
                return
            }

            if provider.identifier == "instagram",
               let magnistra = try? JSONDecoder().decode(LegacyMagnistraSession.self, from: data),
               magnistra.format == "magnistra-session-v1",
               magnistra.version == 1 {
                importedUserAgent = magnistra.profile.userAgent
                let persisted = LegacyRelayPersistedSession(
                    version: 1,
                    provider: provider.identifier,
                    browserProfile: provider.browserProfile.rawValue,
                    observedUserAgent: magnistra.profile.userAgent,
                    cookies: magnistra.cookies
                )
                LegacyRelaySessionStore.save(persisted)
                rebuildWebView(restorePersistedSession: true)
                return
            }

            showMessage(title: "Import Failed", message: "The selected file is not a valid session for this provider.")
        } catch {
            showMessage(title: "Import Failed", message: error.localizedDescription)
        }
    }

    private func exportSession() {
        if provider.identifier == "snapchat" {
            do {
                let url = try LegacyRelayGeckoSessionArchive.exportFullProfile(
                    providerIdentifier: provider.identifier
                )
                let activity = UIActivityViewController(
                    activityItems: [url],
                    applicationActivities: nil
                )
                if let popover = activity.popoverPresentationController {
                    popover.barButtonItem = navigationItem.rightBarButtonItem
                }
                present(activity, animated: true)
            } catch {
                showMessage(
                    title: "Export Session Failed",
                    message: error.localizedDescription
                )
            }
            return
        }

        readObservedBrowserState { [weak self] userAgent, language in
            guard let self = self else { return }
            self.readCookies { [weak self] cookies in
                guard let self = self else { return }
                guard !cookies.isEmpty else {
                    self.showMessage(
                        title: "No Session",
                        message: "No cookies are available for \(self.provider.title). Log in first."
                    )
                    return
                }

                let encoded = cookies.map(self.encodeCookie)
                let profileType: String
                if self.provider.identifier == "instagram" {
                    profileType = "native"
                } else {
                    profileType = self.provider.browserProfile.rawValue
                }
                let profile = RelaySessionProfile(
                    type: profileType,
                    userAgent: userAgent,
                    pageLanguage: language
                )

                if self.provider.identifier == "instagram" {
                    let document = LegacyMagnistraSession(
                        format: "magnistra-session-v1",
                        version: 1,
                        exportedAt: ISO8601DateFormatter().string(from: Date()),
                        profile: profile,
                        cookies: encoded
                    )
                    self.writeAndShare(
                        document,
                        fileName: "MagnistraSession.mgsession"
                    )
                } else {
                    let document = LegacyRelayExportedSession(
                        format: "legacyrelay-session-v1",
                        version: 1,
                        exportedAt: ISO8601DateFormatter().string(from: Date()),
                        provider: self.provider.identifier,
                        providerTitle: self.provider.title,
                        browserProfile: self.provider.browserProfile.rawValue,
                        profile: profile,
                        cookies: encoded
                    )
                    self.writeAndShare(
                        document,
                        fileName: "custom.mgsession"
                    )
                }
            }
        }
    }

    private func writeAndShare<T: Encodable>(_ document: T, fileName: String) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            present(activity, animated: true)
        } catch {
            showMessage(title: "Export Failed", message: error.localizedDescription)
        }
    }

    private func persistCurrentCookies() {
        readCookies { [weak self] cookies in
            guard let self = self else { return }
            let encoded = cookies.map(self.encodeCookie)
            self.readObservedBrowserState { [weak self] userAgent, _ in
                guard let self = self else { return }
                LegacyRelaySessionStore.save(
                    LegacyRelayPersistedSession(
                        version: 1,
                        provider: self.provider.identifier,
                        browserProfile: self.provider.browserProfile.rawValue,
                        observedUserAgent: userAgent,
                        cookies: encoded
                    )
                )
            }
        }
    }

    private func readCookies(completion: @escaping ([HTTPCookie]) -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            DispatchQueue.main.async {
                completion(cookies)
            }
        }
    }

    private func installCookies(_ cookies: [RelaySessionCookie], completion: @escaping (Int) -> Void) {
        guard !cookies.isEmpty else {
            completion(0)
            return
        }

        let store = webView.configuration.websiteDataStore.httpCookieStore
        let group = DispatchGroup()
        let lock = NSLock()
        var installed = 0

        for cookie in cookies {
            guard let native = makeCookie(from: cookie) else { continue }
            group.enter()
            store.setCookie(native) {
                lock.lock()
                installed += 1
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(installed)
        }
    }

    private func readObservedBrowserState(completion: @escaping (String, String?) -> Void) {
        let script = "({ userAgent: navigator.userAgent, language: navigator.language })"
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            guard let self = self else { return }
            var userAgent = self.webView.customUserAgent ?? "native-wkwebview"
            var language: String?
            if let dictionary = value as? [String: Any] {
                if let observed = dictionary["userAgent"] as? String, !observed.isEmpty {
                    userAgent = observed
                }
                language = dictionary["language"] as? String
            }
            completion(userAgent, language)
        }
    }

    private func encodeCookie(_ cookie: HTTPCookie) -> RelaySessionCookie {
        let httpOnlyKey = HTTPCookiePropertyKey(rawValue: "HttpOnly")
        let httpOnly = cookie.properties?[httpOnlyKey] != nil
        return RelaySessionCookie(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            secure: cookie.isSecure,
            httpOnly: httpOnly,
            sessionOnly: cookie.isSessionOnly,
            expires: cookie.expiresDate?.timeIntervalSince1970
        )
    }

    private func makeCookie(from cookie: RelaySessionCookie) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: cookie.name,
            .value: cookie.value,
            .domain: cookie.domain,
            .path: cookie.path
        ]
        if cookie.secure {
            properties[.secure] = "TRUE"
        }
        if cookie.httpOnly {
            properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
        }
        if let expires = cookie.expires, !cookie.sessionOnly {
            properties[.expires] = Date(timeIntervalSince1970: expires)
        }
        return HTTPCookie(properties: properties)
    }

    

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        persistCurrentCookies()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if provider.identifier == "instagram" {
            let issue = error as NSError
            NSLog("LegacyRelay Instagram WK: provisional navigation failed domain=%@ code=%ld host=%@",
                  issue.domain, issue.code, webView.url?.host ?? "unknown")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if provider.identifier == "instagram" {
            let issue = error as NSError
            NSLog("LegacyRelay Instagram WK: navigation failed domain=%@ code=%ld host=%@",
                  issue.domain, issue.code, webView.url?.host ?? "unknown")
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
              let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }

        if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "data" || scheme == "blob" {
            decisionHandler(.allow)
            return
        }

        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    private func showMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    

    private static let chromeDesktopCompatibilityJavaScript = #"""
    (function() {
      function define(target, key, value) {
        try {
          Object.defineProperty(target, key, {
            configurable: true,
            get: function() { return value; }
          });
        } catch (_) {}
      }

      try {
        define(navigator, 'platform', 'MacIntel');
        define(navigator, 'vendor', 'Google Inc.');
        define(navigator, 'maxTouchPoints', 0);
        define(navigator, 'webdriver', undefined);
        define(navigator, 'hardwareConcurrency', 8);
        define(navigator, 'deviceMemory', 8);
        define(navigator, 'standalone', undefined);
      } catch (_) {}

      try {
        var navProto = Object.getPrototypeOf(navigator);
        define(navProto, 'platform', 'MacIntel');
        define(navProto, 'vendor', 'Google Inc.');
        define(navProto, 'maxTouchPoints', 0);
        define(navProto, 'webdriver', undefined);
        define(navProto, 'hardwareConcurrency', 8);
        define(navProto, 'deviceMemory', 8);
      } catch (_) {}

      try {
        var uaData = {
          brands: [
            { brand: 'Chromium', version: '154' },
            { brand: 'Google Chrome', version: '154' },
            { brand: 'Not_A Brand', version: '99' }
          ],
          mobile: false,
          platform: 'macOS',
          getHighEntropyValues: function(hints) {
            var values = {
              architecture: 'arm',
              bitness: '64',
              brands: this.brands,
              fullVersionList: [
                { brand: 'Chromium', version: '154.0.0.0' },
                { brand: 'Google Chrome', version: '154.0.0.0' },
                { brand: 'Not_A Brand', version: '99.0.0.0' }
              ],
              mobile: false,
              model: '',
              platform: 'macOS',
              platformVersion: '15.0.0',
              uaFullVersion: '154.0.0.0',
              wow64: false
            };
            return Promise.resolve(values);
          },
          toJSON: function() {
            return {
              brands: this.brands,
              mobile: false,
              platform: 'macOS'
            };
          }
        };
        try {
          Object.defineProperty(navigator, 'userAgentData', {
            configurable: true,
            get: function() { return uaData; }
          });
        } catch (_) {}
        try {
          Object.defineProperty(Object.getPrototypeOf(navigator), 'userAgentData', {
            configurable: true,
            get: function() { return uaData; }
          });
        } catch (_) {}
      } catch (_) {}

      try {
        if (!window.chrome) {
          Object.defineProperty(window, 'chrome', {
            configurable: true,
            value: {
              app: {},
              runtime: {},
              loadTimes: function() { return {}; },
              csi: function() { return {}; }
            }
          });
        }
      } catch (_) {}

      try {
        var screenProto = Object.getPrototypeOf(window.screen);
        define(window.screen, 'width', 1440);
        define(window.screen, 'height', 900);
        define(window.screen, 'availWidth', 1440);
        define(window.screen, 'availHeight', 875);
        define(window.screen, 'colorDepth', 24);
        define(window.screen, 'pixelDepth', 24);
        define(screenProto, 'width', 1440);
        define(screenProto, 'height', 900);
        define(screenProto, 'availWidth', 1440);
        define(screenProto, 'availHeight', 875);
        define(screenProto, 'colorDepth', 24);
        define(screenProto, 'pixelDepth', 24);
      } catch (_) {}

      try {
        define(window, 'outerWidth', 1440);
        define(window, 'outerHeight', 900);
        define(window, 'screenX', 0);
        define(window, 'screenY', 0);
      } catch (_) {}

      try {
        var nativeMatchMedia = window.matchMedia ? window.matchMedia.bind(window) : null;
        if (nativeMatchMedia) {
          window.matchMedia = function(query) {
            var q = String(query || '').toLowerCase();
            if (q.indexOf('pointer: coarse') >= 0 ||
                q.indexOf('any-pointer: coarse') >= 0 ||
                q.indexOf('hover: none') >= 0 ||
                q.indexOf('any-hover: none') >= 0) {
              return {
                matches: false,
                media: query,
                onchange: null,
                addListener: function(){},
                removeListener: function(){},
                addEventListener: function(){},
                removeEventListener: function(){},
                dispatchEvent: function(){ return false; }
              };
            }
            if (q.indexOf('pointer: fine') >= 0 ||
                q.indexOf('any-pointer: fine') >= 0 ||
                q.indexOf('hover: hover') >= 0 ||
                q.indexOf('any-hover: hover') >= 0) {
              return {
                matches: true,
                media: query,
                onchange: null,
                addListener: function(){},
                removeListener: function(){},
                addEventListener: function(){},
                removeEventListener: function(){},
                dispatchEvent: function(){ return false; }
              };
            }
            return nativeMatchMedia(query);
          };
        }
      } catch (_) {}

      function forceDesktopViewport() {
        try {
          var head = document.head || document.getElementsByTagName('head')[0];
          if (!head) return false;

          var viewport = document.querySelector('meta[name="viewport"]');
          if (!viewport) {
            viewport = document.createElement('meta');
            viewport.setAttribute('name', 'viewport');
            head.appendChild(viewport);
          }
          viewport.setAttribute(
            'content',
            'width=1280, initial-scale=1.0, maximum-scale=1.0, viewport-fit=cover'
          );
          if (document.documentElement) {
            document.documentElement.setAttribute('data-legacyrelay-desktop', '1');
          }
          return true;
        } catch (_) {
          return false;
        }
      }

      try {
        if (!forceDesktopViewport()) {
          var tries = 0;
          var timer = setInterval(function() {
            tries += 1;
            if (forceDesktopViewport() || tries > 100) {
              clearInterval(timer);
            }
          }, 10);
        }
      } catch (_) {}
    })();
    """#

}

private extension UINavigationController {
    func legacyRelayPushProviderIfSafe(_ controller: UIViewController, animated: Bool) {
        guard Thread.isMainThread,
              transitionCoordinator == nil,
              topViewController !== controller,
              !viewControllers.contains(where: { $0 === controller }) else { return }
        pushViewController(controller, animated: animated)
    }
}
