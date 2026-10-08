import Foundation
import GeckoView

LegacyRelayGeckoProfile.prepareBeforeGeckoStarts(
    defaultProfileIdentifier: RelayProvider.initialGeckoProviderIdentifier
)
GeckoRuntime.main(argc: CommandLine.argc, argv: CommandLine.unsafeArgv)
