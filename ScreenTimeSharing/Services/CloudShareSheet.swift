import CloudKit
import SwiftUI
import UIKit

struct CloudShareSheet: UIViewControllerRepresentable {
    let store: CloudKitUsageSnapshotStore
    let profile: UserProfile

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController { _, completion in
            Task {
                do {
                    let result = try await store.prepareProfileShare(profile: profile)
                    completion(result.share, result.container, nil)
                } catch {
                    completion(nil, nil, error)
                }
            }
        }
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadOnly]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? {
            "Screen Time Sharing"
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}
    }
}
