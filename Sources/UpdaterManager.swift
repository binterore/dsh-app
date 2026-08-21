import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterManager: NSObject {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController
    private var observation: AnyCancellable?
    private(set) var canCheckForUpdates = false
    var onAvailabilityChange: ((Bool) -> Void)?

    var isConfigured: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return false }
        return !key.isEmpty && !key.contains("REPLACE_WITH") && URL(string: feed) != nil
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    private override init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] available in
                self?.canCheckForUpdates = available
                self?.onAvailabilityChange?(available)
            }
    }

    func start() {
        #if DEBUG
        return
        #else
        guard isConfigured else {
            AppLogger.shared.log("Sparkle 未配置公钥；自动更新保持禁用。", category: "update")
            return
        }
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
        #if DEBUG
        return
        #else
        guard isConfigured else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
        #endif
    }
}
