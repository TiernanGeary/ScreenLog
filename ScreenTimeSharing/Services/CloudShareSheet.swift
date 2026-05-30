import CloudKit
import SwiftUI
import UIKit

struct CloudShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let store: CloudKitUsageSnapshotStore
    let profile: UserProfile

    @State private var phase: InviteLinkPhase = .creating
    @State private var didCopyLink = false
    @State private var preparedShare: CKShare?
    @State private var preparedContainer: CKContainer?
    @State private var sharingPayload: CloudSharePayload?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 12)

                switch phase {
                case .creating:
                    ProgressView()
                        .controlSize(.large)

                    VStack(spacing: 6) {
                        Text("Creating invite link")
                            .font(.headline)

                        Text("This usually takes a few seconds.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                case .ready(let url):
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.blue)

                    VStack(spacing: 6) {
                        Text("Invite link ready")
                            .font(.headline)

                        Text("Send this link to a friend so they can accept your Screen Time sharing invite.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(spacing: 12) {
                        Button {
                            AppHaptics.buttonTap()
                            presentCloudSharing()
                        } label: {
                            Label("Share Invite", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            AppHaptics.buttonTap()
                            UIPasteboard.general.url = url
                            didCopyLink = true
                        } label: {
                            Label(didCopyLink ? "Copied" : "Copy Link", systemImage: didCopyLink ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)

                    VStack(spacing: 6) {
                        Text("Could not create link")
                            .font(.headline)

                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        AppHaptics.buttonTap()
                        Task {
                            await createInviteLink()
                        }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Spacer(minLength: 12)
            }
            .padding(24)
            .navigationTitle("Invite Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await createInviteLink()
            }
            .sheet(item: $sharingPayload) { payload in
                CloudSharingControllerView(
                    share: payload.share,
                    container: payload.container,
                    profileName: profile.displayName
                ) {
                    sharingPayload = nil
                }
                .ignoresSafeArea()
            }
        }
    }

    private func presentCloudSharing() {
        guard let preparedShare, let preparedContainer else {
            return
        }
        sharingPayload = CloudSharePayload(share: preparedShare, container: preparedContainer)
    }

    private func createInviteLink() async {
        phase = .creating
        didCopyLink = false

        do {
            let result = try await store.prepareProfileShare(profile: profile)
            guard let url = result.share.url else {
                throw InviteLinkError.missingShareURL
            }

            preparedShare = result.share
            preparedContainer = result.container
            phase = .ready(url)
            presentCloudSharing()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

private enum InviteLinkPhase: Equatable {
    case creating
    case ready(URL)
    case failed(String)
}

private enum InviteLinkError: LocalizedError {
    case missingShareURL

    var errorDescription: String? {
        "iCloud created the share, but did not return an invite URL. Try again after checking iCloud is enabled for this app."
    }
}

private struct CloudSharePayload: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// Presents Apple's native CloudKit sharing UI. Sending the invite as a real
/// CKShare invitation (rather than a bare iCloud URL) makes iOS reliably hand the
/// tapped link off to the app instead of opening the iCloud.com web page.
private struct CloudSharingControllerView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let profileName: String
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        // Friends need write access (to write their participant mirror + approvals
        // back into the channel), and link-based sharing keeps the existing UX.
        controller.availablePermissions = [.allowReadWrite, .allowPublic]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(profileName: profileName, onFinish: onFinish)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let profileName: String
        let onFinish: () -> Void

        init(profileName: String, onFinish: @escaping () -> Void) {
            self.profileName = profileName
            self.onFinish = onFinish
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "\(profileName)'s Screen Time"
        }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: any Error
        ) {
            onFinish()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onFinish()
        }
    }
}
