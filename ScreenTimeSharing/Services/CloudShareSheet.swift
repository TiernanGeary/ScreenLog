import CloudKit
import SwiftUI
import UIKit

struct CloudShareSheet: UIViewControllerRepresentable {
    let store: CloudKitUsageSnapshotStore
    let profile: UserProfile

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let itemProvider = NSItemProvider()
        let container = CKContainer(identifier: AppConfiguration.cloudKitContainerIdentifier)
        let sharingOptions = CKAllowedSharingOptions(
            allowedParticipantPermissionOptions: .readOnly,
            allowedParticipantAccessOptions: .any
        )

        itemProvider.registerCKShare(
            container: container,
            allowedSharingOptions: sharingOptions
        ) {
            let result = try await store.prepareProfileShare(profile: profile)
            return result.share
        }

        let configuration = UIActivityItemsConfiguration(itemProviders: [itemProvider])
        configuration.metadataProvider = { key in
            key == .title ? "Screen Time Sharing" : nil
        }

        let controller = UIActivityViewController(activityItemsConfiguration: configuration)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
