import SwiftUI

/// Invite flow replacing the CloudKit share sheet: mint a short invite code to
/// share, or redeem a code received from a friend.
struct InviteFriendsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case creating
        case ready(CreatedInvite)
        case failed(String)
    }

    @State private var phase: Phase = .creating
    @State private var redeemCode = ""
    @State private var redeemError: String?
    @State private var isRedeeming = false
    @State private var didCopyCode = false

    var body: some View {
        NavigationStack {
            Form {
                inviteSection
                redeemSection
            }
            .navigationTitle("Invite Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await createInvite()
            }
        }
    }

    private var inviteSection: some View {
        Section {
            switch phase {
            case .creating:
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Creating your invite code…")
                        .foregroundStyle(.secondary)
                }
            case .ready(let invite):
                VStack(alignment: .leading, spacing: 12) {
                    Text(invite.formattedCode)
                        .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)

                    HStack {
                        ShareLink(item: shareMessage(for: invite)) {
                            Label("Share Invite", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            UIPasteboard.general.string = invite.formattedCode
                            didCopyCode = true
                        } label: {
                            Label(didCopyCode ? "Copied" : "Copy Code", systemImage: didCopyCode ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)

                    Text("Expires \(invite.expiresAt.formatted(date: .abbreviated, time: .omitted)). One friend per code.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            case .failed(let reason):
                VStack(alignment: .leading, spacing: 8) {
                    Text(reason)
                        .foregroundStyle(.red)
                    Button("Try Again") {
                        phase = .creating
                        Task {
                            await createInvite()
                        }
                    }
                }
            }
        } header: {
            Text("Your invite code")
        } footer: {
            Text("Send this code to a friend. When they enter it in deny, you're connected.")
        }
    }

    private var redeemSection: some View {
        Section {
            TextField("ABCD-EFGH", text: $redeemCode)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()

            if let redeemError {
                Text(redeemError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    await redeem()
                }
            } label: {
                if isRedeeming {
                    ProgressView()
                } else {
                    Text("Add Friend")
                }
            }
            .disabled(isRedeeming || normalizedRedeemCode.isEmpty)
        } header: {
            Text("Have a code?")
        }
    }

    private var normalizedRedeemCode: String {
        redeemCode
            .replacingOccurrences(of: "-", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func shareMessage(for invite: CreatedInvite) -> String {
        let name = model.profile.displayName == "Me" ? "your friend" : model.profile.displayName
        return "Add \(name) on deny — invite code \(invite.formattedCode). Open deny and enter it, or tap: \(invite.url.absoluteString)"
    }

    private func createInvite() async {
        guard case .creating = phase else {
            return
        }
        do {
            let invite = try await model.createInvite()
            phase = .ready(invite)
        } catch {
            phase = .failed("Could not create an invite: \(error.localizedDescription)")
        }
    }

    private func redeem() async {
        isRedeeming = true
        redeemError = nil
        defer { isRedeeming = false }

        let success = await model.redeemInvite(code: normalizedRedeemCode)
        if success {
            dismiss()
        } else {
            redeemError = model.message
        }
    }
}
