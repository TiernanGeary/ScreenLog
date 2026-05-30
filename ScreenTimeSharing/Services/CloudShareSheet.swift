import CloudKit
import LinkPresentation
import SwiftUI
import UIKit

struct CloudShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    let store: CloudKitUsageSnapshotStore
    let profile: UserProfile

    @State private var phase: InviteLinkPhase = .creating
    @State private var isShowingSystemShareSheet = false
    @State private var didCopyLink = false

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
                            isShowingSystemShareSheet = true
                        } label: {
                            Label("Share Link", systemImage: "square.and.arrow.up")
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
            .sheet(isPresented: $isShowingSystemShareSheet) {
                if case .ready(let url) = phase {
                    InviteURLActivitySheet(url: url, profileName: profile.displayName)
                }
            }
        }
    }

    private func createInviteLink() async {
        phase = .creating
        didCopyLink = false

        do {
            let result = try await store.prepareProfileShare(profile: profile)
            guard let url = result.share.url else {
                throw InviteLinkError.missingShareURL
            }

            phase = .ready(url)
            isShowingSystemShareSheet = true
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

private struct InviteURLActivitySheet: UIViewControllerRepresentable {
    let url: URL
    let profileName: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let item = InviteURLActivityItem(url: url, profileName: profileName)
        return UIActivityViewController(activityItems: [item], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class InviteURLActivityItem: NSObject, UIActivityItemSource {
    let url: URL
    let profileName: String

    init(url: URL, profileName: String) {
        self.url = url
        self.profileName = profileName
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        url
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        "deny invite"
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = "\(profileName) invited you to deny"
        metadata.originalURL = url
        metadata.url = url
        return metadata
    }
}
