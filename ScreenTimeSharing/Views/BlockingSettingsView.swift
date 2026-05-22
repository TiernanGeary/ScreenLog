import FamilyControls
import SwiftUI

struct RequestFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    var highlightedFriendRequestID: String?
    var showsDoneButton = true

    private var highlightedFriendRequest: BlockFriendRequest? {
        guard let highlightedFriendRequestID else {
            return nil
        }

        return model.blockingState.friendRequests.first { $0.id == highlightedFriendRequestID }
    }

    private var attentionRequests: [BlockFriendRequest] {
        model.blockingState.friendRequests
            .filter { request in
                (request.isReceived(by: model.profile.id) && request.status == .pending)
                    || (request.isSent(by: model.profile.id) && request.status == .approved)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var receivedFriendRequests: [BlockFriendRequest] {
        model.blockingState.friendRequests
            .filter { $0.isReceived(by: model.profile.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var sentFriendRequests: [BlockFriendRequest] {
        model.blockingState.friendRequests
            .filter { $0.isSent(by: model.profile.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var recentQuickRequests: [BlockingRequestListItem] {
        model.blockingState.requests
            .map { request in
                BlockingRequestListItem(
                    id: "legacy-\(request.id)",
                    groupID: request.groupID,
                    duration: request.requestedSeconds,
                    status: request.status,
                    createdAt: request.createdAt,
                    kind: "Quick request",
                    message: nil
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        AppScreenScroll(backgroundStyle: .white) {
            if let highlightedFriendRequest {
                AppSection("Opened Request") {
                    AppCard {
                        friendRequestRow(
                            highlightedFriendRequest,
                            direction: direction(for: highlightedFriendRequest),
                            isHighlighted: true
                        )
                        .appCardRow(verticalPadding: 12)
                    }
                }
            }

            AppSection("Needs Attention") {
                AppCard {
                    friendRequestList(
                        attentionRequests,
                        emptyText: "No requests need attention right now."
                    )
                }
            }

            AppSection("Received") {
                AppCard {
                    friendRequestList(
                        receivedFriendRequests,
                        emptyText: "No received friend requests yet."
                    )
                }
            }

            AppSection("Sent") {
                AppCard {
                    friendRequestList(
                        sentFriendRequests,
                        emptyText: "No sent friend requests yet."
                    )
                }
            }

            AppSection("Quick Requests") {
                AppCard {
                    if recentQuickRequests.isEmpty {
                        Text("No quick requests yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .appCardRow()
                    } else {
                        ForEach(Array(recentQuickRequests.enumerated()), id: \.element.id) { index, request in
                            if index > 0 {
                                AppCardDivider()
                            }

                            requestRow(request)
                                .appCardRow(verticalPadding: 12)
                        }
                    }
                }
            }
        }
        .navigationTitle("Request Feed")
        .onAppear {
            model.expireStaleFriendRequests()
        }
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        AppHaptics.buttonTap()
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func friendRequestList(
        _ requests: [BlockFriendRequest],
        emptyText: String
    ) -> some View {
        if requests.isEmpty {
            Text(emptyText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .appCardRow()
        } else {
            ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
                if index > 0 {
                    AppCardDivider()
                }

                friendRequestRow(
                    request,
                    direction: direction(for: request),
                    isHighlighted: request.id == highlightedFriendRequestID
                )
                .appCardRow(verticalPadding: 12)
            }
        }
    }

    private func friendRequestRow(
        _ request: BlockFriendRequest,
        direction: FriendRequestDirection,
        isHighlighted: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                FriendRequestDetailView(requestID: request.id)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    let participantName = FriendRequestFeedDisplay.participantName(
                        for: request,
                        direction: direction,
                        profile: model.profile,
                        friends: model.friendSummaries
                    )

                    Avatar(
                        colorHex: FriendRequestFeedDisplay.participantAvatarColorHex(
                            for: request,
                            direction: direction,
                            profile: model.profile,
                            friends: model.friendSummaries
                        ),
                        initials: participantName.initials
                    )
                    .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(participantName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text(FriendRequestFeedDisplay.relativeRequestAge(request.createdAt))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text("\(BlockingDisplayFormatter.durationLabel(request.requestedSeconds)) requested")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let message = FriendRequestFeedDisplay.message(for: request) {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            friendRequestActions(request, direction: direction)
        }
        .padding(isHighlighted ? 10 : 0)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            }
        }
    }

    @ViewBuilder
    private func friendRequestActions(
        _ request: BlockFriendRequest,
        direction: FriendRequestDirection
    ) -> some View {
        switch direction {
        case .sent:
            if request.status == .approved {
                Button {
                    if model.collectFriendRequest(id: request.id) {
                        AppHaptics.buttonTap()
                    }
                } label: {
                    Label("Collect", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.green.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.08, green: 0.58, blue: 0.32))
                .frame(maxWidth: .infinity)
            }
        case .received:
            if request.status == .pending {
                HStack(spacing: 8) {
                    Button {
                        if model.approveFriendRequest(id: request.id) {
                            AppHaptics.buttonTap()
                        }
                    } label: {
                        Text("Approve")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.green.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.08, green: 0.58, blue: 0.32))

                    Button {
                        if model.denyFriendRequest(id: request.id) {
                            AppHaptics.buttonTap()
                        }
                    } label: {
                        Text("Deny")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.86, green: 0.24, blue: 0.22))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func requestRow(_ request: BlockingRequestListItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "timer")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(BlockingDisplayFormatter.durationLabel(request.duration)) \(request.kind)")
                    .font(.subheadline.weight(.semibold))
                Text(groupName(for: request.groupID))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let message = request.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(request.status.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func direction(for request: BlockFriendRequest) -> FriendRequestDirection {
        request.isSent(by: model.profile.id) ? .sent : .received
    }

    private func groupName(for groupID: String) -> String {
        model.blockingState.groups.first { $0.id == groupID }?.name ?? "Unknown group"
    }
}

private struct FriendRequestDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let requestID: String

    private var request: BlockFriendRequest? {
        model.blockingState.friendRequests.first { $0.id == requestID }
    }

    var body: some View {
        AppScreenScroll(backgroundStyle: .white) {
            if let request {
                let direction = FriendRequestFeedDisplay.direction(for: request, currentUserID: model.profile.id)
                let participantName = FriendRequestFeedDisplay.participantName(
                    for: request,
                    direction: direction,
                    profile: model.profile,
                    friends: model.friendSummaries
                )
                let avatarColorHex = FriendRequestFeedDisplay.participantAvatarColorHex(
                    for: request,
                    direction: direction,
                    profile: model.profile,
                    friends: model.friendSummaries
                )

                VStack(spacing: 9) {
                    Avatar(colorHex: avatarColorHex, initials: participantName.initials)
                        .frame(width: 88, height: 88)

                    Text(participantName)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(FriendRequestFeedDisplay.statusLabel(for: request))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(FriendRequestFeedDisplay.statusColor(for: request))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(FriendRequestFeedDisplay.statusColor(for: request).opacity(0.10))
                        )
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 2)

                AppSection("Request") {
                    AppCard {
                        requestSummaryRow(
                            appName: FriendRequestFeedDisplay.groupName(for: request.groupID, groups: model.blockingState.groups),
                            duration: BlockingDisplayFormatter.durationLabel(request.requestedSeconds)
                        )

                        if let message = FriendRequestFeedDisplay.message(for: request) {
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                                .appCardRow(verticalPadding: 12)
                        }

                        if let expirationText = detailExpirationText(for: request) {
                            expirationRow(expirationText)
                        }
                    }
                }

                detailActions(for: request, direction: direction)
            } else {
                AppCard {
                    ContentUnavailableView(
                        "Request Not Found",
                        systemImage: "tray",
                        description: Text("This request may have been removed.")
                    )
                    .appCardRow(verticalPadding: 16)
                }
            }
        }
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.58), lineWidth: 0.75)
                        )
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
        }
        .onAppear {
            model.expireStaleFriendRequests()
        }
    }

    @ViewBuilder
    private func detailActions(for request: BlockFriendRequest, direction: FriendRequestDirection) -> some View {
        switch direction {
        case .sent:
            if request.status == .approved {
                Button {
                    if model.collectFriendRequest(id: request.id) {
                        AppHaptics.buttonTap()
                    }
                } label: {
                    Label("Collect Time", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.green.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.08, green: 0.58, blue: 0.32))
            }
        case .received:
            if request.status == .pending {
                HStack(spacing: 8) {
                    Button {
                        if model.approveFriendRequest(id: request.id) {
                            AppHaptics.buttonTap()
                        }
                    } label: {
                        Text("Approve")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.green.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.08, green: 0.58, blue: 0.32))

                    Button {
                        if model.denyFriendRequest(id: request.id) {
                            AppHaptics.buttonTap()
                        }
                    } label: {
                        Text("Deny")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.86, green: 0.24, blue: 0.22))
                }
            }
        }
    }

    private func detailExpirationText(for request: BlockFriendRequest) -> String? {
        switch request.status {
        case .pending:
            return remainingTimeLabel(until: request.pendingExpiresAt)
        case .approved:
            guard let collectionExpiresAt = request.collectionExpiresAt else {
                return nil
            }
            return remainingTimeLabel(until: collectionExpiresAt)
        case .denied, .expired, .collected:
            return nil
        }
    }

    private func remainingTimeLabel(until date: Date, now: Date = Date()) -> String {
        let remainingSeconds = max(0, date.timeIntervalSince(now))
        guard remainingSeconds > 0 else {
            return "Expired"
        }

        let hours = Int(remainingSeconds) / 3_600
        let minutes = max(1, (Int(remainingSeconds) % 3_600 + 59) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

    private func expirationRow(_ value: String) -> some View {
        Text("Expires in \(value)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .appCardRow(verticalPadding: 4)
    }

    private func requestSummaryRow(appName: String, duration: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                AppUsageIcon(name: appName)
                    .scaleEffect(0.72)
                    .frame(width: 30, height: 30)

                Text(appName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Text(duration)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .appCardRow(verticalPadding: 10)
    }
}

private enum FriendRequestFeedDisplay {
    static func direction(for request: BlockFriendRequest, currentUserID: String) -> FriendRequestDirection {
        request.isSent(by: currentUserID) ? .sent : .received
    }

    static func participantName(
        for request: BlockFriendRequest,
        direction: FriendRequestDirection,
        profile: UserProfile,
        friends: [FriendUsageSummary]
    ) -> String {
        switch direction {
        case .sent:
            let names = request.selectedFriendIDs.map { friendName($0, profile: profile, friends: friends) }
            guard let firstName = names.first else {
                return "Friend"
            }

            if names.count == 1 {
                return firstName
            }

            return "\(firstName) +\(names.count - 1)"
        case .received:
            if let requesterID = request.requesterID {
                return friendName(
                    requesterID,
                    profile: profile,
                    friends: friends,
                    fallback: request.requesterDisplayName
                )
            }

            let trimmedName = request.requesterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmedName.isEmpty ? "Friend" : trimmedName
        }
    }

    static func participantAvatarColorHex(
        for request: BlockFriendRequest,
        direction: FriendRequestDirection,
        profile: UserProfile,
        friends: [FriendUsageSummary]
    ) -> String {
        switch direction {
        case .sent:
            guard let firstFriendID = request.selectedFriendIDs.first else {
                return AppConfiguration.defaultAvatarColor
            }
            return friendAvatarColorHex(firstFriendID, profile: profile, friends: friends)
        case .received:
            guard let requesterID = request.requesterID else {
                return AppConfiguration.defaultAvatarColor
            }
            return friendAvatarColorHex(requesterID, profile: profile, friends: friends)
        }
    }

    static func message(for request: BlockFriendRequest) -> String? {
        let trimmed = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func relativeRequestAge(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))

        if seconds < 60 {
            return "now"
        }

        if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        }

        if seconds < 86_400 {
            return "\(Int(seconds / 3_600))h ago"
        }

        return "\(Int(seconds / 86_400))d ago"
    }

    static func groupName(for groupID: String, groups: [BlockGroup]) -> String {
        groups.first { $0.id == groupID }?.name ?? "Unknown group"
    }

    static func statusLabel(for request: BlockFriendRequest) -> String {
        switch request.status {
        case .pending:
            return "Pending"
        case .approved:
            return "\(BlockingDisplayFormatter.durationLabel(request.requestedSeconds)) left"
        case .denied:
            return "Denied"
        case .expired:
            return request.approvedByFriendID == nil ? "Expired" : "Approval expired"
        case .collected:
            return "Collected"
        }
    }

    static func statusColor(for request: BlockFriendRequest) -> Color {
        switch request.status {
        case .pending:
            return .secondary
        case .approved, .collected:
            return Color(red: 0.08, green: 0.58, blue: 0.32)
        case .denied, .expired:
            return Color(red: 0.86, green: 0.24, blue: 0.22)
        }
    }

    private static func friendName(
        _ id: String,
        profile: UserProfile,
        friends: [FriendUsageSummary],
        fallback: String? = nil
    ) -> String {
        if id == profile.id {
            return profile.displayName == "Me" ? "You" : profile.displayName
        }

        if let friendName = friends.first(where: { $0.id == id })?.displayName {
            return friendName
        }

        let trimmedFallback = fallback?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedFallback.isEmpty ? id : trimmedFallback
    }

    private static func friendAvatarColorHex(
        _ id: String,
        profile: UserProfile,
        friends: [FriendUsageSummary]
    ) -> String {
        if id == profile.id {
            return profile.avatarColorHex
        }

        return friends.first { $0.id == id }?.avatarColorHex ?? AppConfiguration.defaultAvatarColor
    }
}

struct BlockingSettingsView: View {
    @EnvironmentObject private var model: AppModel
    var highlightedFriendRequestID: String?
    var onShowBlockingActivityPicker: (() -> Void)?

    @State private var editorDraft: BlockGroupDraft?
    @State private var passwordAction: PasswordProtectedAction?

    var body: some View {
        AppScreenScroll(backgroundStyle: .white) {
            AppSection("Block Groups") {
                AppCard {
                    if model.blockingState.groups.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("No block groups yet", systemImage: "lock.shield")
                                .font(.headline)
                            Text("Create a group, pick apps and websites, then choose a schedule or daily time limit.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button {
                                AppHaptics.buttonTap()
                                editorDraft = BlockGroupDraft()
                            } label: {
                                Label("Create Block Group", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                        }
                        .appCardRow()
                    } else {
                        Button {
                            AppHaptics.buttonTap()
                            editorDraft = BlockGroupDraft()
                        } label: {
                            Label("New Block Group", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)

                        AppCardDivider()

                        ForEach(Array(model.blockingState.groups.enumerated()), id: \.element.id) { index, group in
                            if index > 0 {
                                AppCardDivider()
                            }
                            groupRow(group)
                                .appCardRow(verticalPadding: 13)
                        }
                    }
                }
            }
        }
        .navigationTitle("Blocking")
        .onAppear {
            model.expireStaleFriendRequests()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    AppHaptics.buttonTap()
                    editorDraft = BlockGroupDraft()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create block group")
            }
        }
        .sheet(item: $editorDraft) { draft in
            NavigationStack {
                BlockGroupEditorView(initialDraft: draft) { group, password in
                    if model.upsertBlockGroup(group, password: password) {
                        editorDraft = nil
                    }
                }
            }
        }
        .sheet(item: $passwordAction) { action in
            PasswordPromptView(action: action) { resolvedAction, group in
                passwordAction = nil
                handleUnlockedAction(resolvedAction, group: group)
            } onSetPassword: { group in
                passwordAction = nil
                editorDraft = BlockGroupDraft(group: group)
            }
        }
    }

    private var sentFriendRequests: [BlockFriendRequest] {
        model.blockingState.friendRequests
            .filter { $0.isSent(by: model.profile.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var receivedFriendRequests: [BlockFriendRequest] {
        model.blockingState.friendRequests
            .filter { $0.isReceived(by: model.profile.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var recentQuickRequests: [BlockingRequestListItem] {
        let legacy = model.blockingState.requests.map { request in
            BlockingRequestListItem(
                id: "legacy-\(request.id)",
                groupID: request.groupID,
                duration: request.requestedSeconds,
                status: request.status,
                createdAt: request.createdAt,
                kind: "Quick request",
                message: nil
            )
        }
        return legacy.sorted { $0.createdAt > $1.createdAt }
    }

    private var highlightedFriendRequest: BlockFriendRequest? {
        guard let highlightedFriendRequestID else {
            return nil
        }

        return model.blockingState.friendRequests.first { $0.id == highlightedFriendRequestID }
    }

    @ViewBuilder
    private func friendRequestList(
        _ requests: [BlockFriendRequest],
        direction: FriendRequestDirection
    ) -> some View {
        if requests.isEmpty {
            Text(direction.emptyText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .appCardRow()
        } else {
            ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
                if index > 0 {
                    AppCardDivider()
                }
                friendRequestRow(
                    request,
                    direction: direction,
                    isHighlighted: request.id == highlightedFriendRequestID
                )
                    .appCardRow(verticalPadding: 12)
            }
        }
    }

    private func friendRequestRow(
        _ request: BlockFriendRequest,
        direction: FriendRequestDirection,
        isHighlighted: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: direction.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(BlockingDisplayFormatter.durationLabel(request.requestedSeconds)) \(direction.title)")
                        .font(.subheadline.weight(.semibold))
                    Text(friendRequestDetail(request, direction: direction))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if let message = friendRequestMessage(request) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let deadline = friendRequestDeadlineText(request) {
                        Text(deadline)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                Text(friendRequestStatusLabel(request))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(friendRequestStatusColor(request))
            }

            friendRequestActions(request, direction: direction)
        }
        .padding(isHighlighted ? 10 : 0)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.08))
            }
        }
    }

    @ViewBuilder
    private func friendRequestActions(
        _ request: BlockFriendRequest,
        direction: FriendRequestDirection
    ) -> some View {
        switch direction {
        case .sent:
            if request.status == .approved {
                Button {
                    if model.collectFriendRequest(id: request.id) {
                        AppHaptics.buttonTap()
                    }
                } label: {
                    Label("Collect", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.green.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.08, green: 0.58, blue: 0.32))
            }
        case .received:
            if request.status == .pending {
                HStack(spacing: 8) {
                    Button {
                        if model.approveFriendRequest(id: request.id) {
                            AppHaptics.buttonTap()
                        }
                    } label: {
                        Text("Approve")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.green.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.08, green: 0.58, blue: 0.32))

                    Button {
                        if model.denyFriendRequest(id: request.id) {
                            AppHaptics.buttonTap()
                        }
                    } label: {
                        Text("Deny")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(0.10))
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color(red: 0.86, green: 0.24, blue: 0.22))
                }
            }
        }
    }

    private func friendRequestDetail(
        _ request: BlockFriendRequest,
        direction: FriendRequestDirection
    ) -> String {
        let group = groupName(for: request.groupID)
        let party: String
        switch direction {
        case .sent:
            let names = request.selectedFriendIDs.map(friendName).joined(separator: ", ")
            party = names.isEmpty ? "No friends selected" : "To \(names)"
        case .received:
            party = "From \(request.requesterDisplayName ?? request.requesterID.map(friendName) ?? "Friend")"
        }

        return "\(party) • \(group) • \(request.createdAt.formatted(date: .omitted, time: .shortened))"
    }

    private func friendRequestMessage(_ request: BlockFriendRequest) -> String? {
        let trimmed = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func friendRequestDeadlineText(_ request: BlockFriendRequest) -> String? {
        switch request.status {
        case .pending:
            return "Expires \(request.pendingExpiresAt.formatted(date: .omitted, time: .shortened))"
        case .approved:
            guard let collectionExpiresAt = request.collectionExpiresAt else {
                return nil
            }
            return "Collect by \(collectionExpiresAt.formatted(date: .abbreviated, time: .shortened))"
        case .denied, .expired, .collected:
            return nil
        }
    }

    private func friendRequestStatusLabel(_ request: BlockFriendRequest) -> String {
        switch request.status {
        case .pending:
            return "Pending"
        case .approved:
            return "\(BlockingDisplayFormatter.durationLabel(request.requestedSeconds)) left"
        case .denied:
            return "Denied"
        case .expired:
            return request.approvedByFriendID == nil ? "Expired" : "Approval expired"
        case .collected:
            return "Collected"
        }
    }

    private func friendRequestStatusColor(_ request: BlockFriendRequest) -> Color {
        switch request.status {
        case .pending:
            return .secondary
        case .approved, .collected:
            return Color(red: 0.08, green: 0.58, blue: 0.32)
        case .denied, .expired:
            return Color(red: 0.86, green: 0.24, blue: 0.22)
        }
    }

    private func friendName(_ id: String) -> String {
        if id == model.profile.id {
            return model.profile.displayName == "Me" ? "You" : model.profile.displayName
        }

        return model.friendSummaries.first { $0.id == id }?.displayName ?? id
    }

    private func direction(for request: BlockFriendRequest) -> FriendRequestDirection {
        request.isSent(by: model.profile.id) ? .sent : .received
    }

    private func groupRow(_ group: BlockGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(hex: group.colorHex))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(group.name)
                            .font(.headline)
                        if group.requiresPasswordSetup {
                            Text("Needs password")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(group.mode.label)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    beginProtectedAction(.edit, group: group)
                } label: {
                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("Edit group")

                Button {
                    beginProtectedAction(.toggleEnabled, group: group)
                } label: {
                    Image(systemName: group.isEnabled ? "pause.circle" : "play.circle")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel(group.isEnabled ? "Pause group" : "Resume group")
            }

            HStack(spacing: 8) {
                pill("\(selectionCount(for: group)) selected", systemImage: "app.badge")
                if group.unblockConfig.isEnabled {
                    pill("\(group.unblockConfig.unblocksPerDay)x unblocks", systemImage: "lock.open")
                }
                if group.friendRequestConfig.isEnabled {
                    pill("Friend requests", systemImage: "person.2.badge.gearshape")
                }

                Spacer()

                Button(role: .destructive) {
                    beginProtectedAction(.delete, group: group)
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func requestRow(_ request: BlockingRequestListItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: request.kind == "Friend approval" ? "person.2.badge.gearshape" : "timer")
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(BlockingDisplayFormatter.durationLabel(request.duration)) \(request.kind)")
                    .font(.subheadline.weight(.semibold))
                Text(groupName(for: request.groupID))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let message = request.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Text(request.status.rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func beginProtectedAction(_ kind: PasswordProtectedAction.Kind, group: BlockGroup) {
        AppHaptics.buttonTap()
        if kind == .edit, group.requiresPasswordSetup {
            editorDraft = BlockGroupDraft(group: group)
            return
        }

        if model.isGroupUnlocked(group) {
            handleUnlockedAction(kind, group: group)
        } else {
            passwordAction = PasswordProtectedAction(kind: kind, groupID: group.id)
        }
    }

    private func handleUnlockedAction(_ kind: PasswordProtectedAction.Kind, group: BlockGroup) {
        switch kind {
        case .edit:
            editorDraft = BlockGroupDraft(group: group)
        case .toggleEnabled:
            _ = model.toggleBlockGroup(group)
        case .delete:
            _ = model.deleteBlockGroup(group)
        }
    }

    private func pill(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.58), in: Capsule())
    }

    private func selectionCount(for group: BlockGroup) -> Int {
        guard let selection = try? BlockingSelectionCodec.decode(group.selectionData) else {
            return 0
        }

        return selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    private func groupName(for groupID: String) -> String {
        model.blockingState.groups.first { $0.id == groupID }?.name ?? "Unknown group"
    }
}

private struct BlockingRequestListItem: Identifiable {
    let id: String
    let groupID: String
    let duration: TimeInterval
    let status: BlockRequestStatus
    let createdAt: Date
    let kind: String
    let message: String?
}

private enum FriendRequestDirection {
    case sent
    case received

    var title: String {
        switch self {
        case .sent:
            return "request"
        case .received:
            return "request"
        }
    }

    var emptyText: String {
        switch self {
        case .sent:
            return "No sent friend requests yet."
        case .received:
            return "No received friend requests yet."
        }
    }

    var systemImage: String {
        switch self {
        case .sent:
            return "paperplane.fill"
        case .received:
            return "tray.and.arrow.down.fill"
        }
    }
}

struct PasswordProtectedAction: Identifiable {
    enum Kind {
        case edit
        case toggleEnabled
        case delete
    }

    let id = UUID()
    let kind: Kind
    let groupID: String
}

struct PasswordPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let action: PasswordProtectedAction
    let onUnlocked: (PasswordProtectedAction.Kind, BlockGroup) -> Void
    let onSetPassword: (BlockGroup) -> Void

    @State private var password = ""
    @State private var newPassword = ""

    private var group: BlockGroup? {
        model.blockingState.groups.first { $0.id == action.groupID }
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                AppSection("Passcode") {
                    AppCard {
                        if let group {
                            if group.requiresPasswordSetup {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("\(group.name) needs a passcode before it can be changed.")
                                        .font(.subheadline)
                                    Button {
                                        AppHaptics.buttonTap()
                                        onSetPassword(group)
                                    } label: {
                                        Label("Set Passcode", systemImage: "key")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tint)
                                }
                                .appCardRow()
                            } else {
                                VStack(alignment: .leading, spacing: 14) {
                                    SecureField("Group passcode", text: $password)
                                        .textContentType(.password)

                                    Button {
                                        if model.verifyPassword(for: group, password: password) {
                                            AppHaptics.buttonTap()
                                            onUnlocked(action.kind, group)
                                        }
                                    } label: {
                                        Label("Unlock", systemImage: "lock.open")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tint)
                                }
                                .appCardRow()
                            }
                        }
                    }
                }

                if let group, !group.requiresPasswordSetup {
                    AppSection("Recovery") {
                        AppCard {
                            if let reset = group.passwordReset {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(reset.isAvailable() ? "Reset is available." : "Reset will unlock after 24 hours.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)

                                    if reset.isAvailable() {
                                        SecureField("New passcode", text: $newPassword)
                                            .textContentType(.newPassword)
                                        Button {
                                            if model.completePasswordReset(for: group, newPassword: newPassword),
                                               let updatedGroup = model.blockingState.groups.first(where: { $0.id == group.id }) {
                                                AppHaptics.buttonTap()
                                                onUnlocked(action.kind, updatedGroup)
                                            }
                                        } label: {
                                            Label("Reset Passcode", systemImage: "key.fill")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.tint)
                                    }
                                }
                                .appCardRow()
                            } else {
                                Button {
                                    AppHaptics.buttonTap()
                                    model.requestPasswordReset(for: group)
                                } label: {
                                    Label("Forgot Password", systemImage: "clock.badge.exclamationmark")
                                        .appCardRow()
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Unlock Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppHaptics.buttonTap()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BlockGroupConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let groupID: String

    @State private var passwordAction: PasswordProtectedAction?
    @State private var editorDraft: BlockGroupDraft?

    private var group: BlockGroup? {
        model.blockingState.groups.first { $0.id == groupID }
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                if let group {
                    header(for: group)

                    AppSection("Apps & Websites") {
                        AppCard {
                            configurationRow(
                                title: "Selected items",
                                value: "\(selectionCount(for: group))",
                                systemImage: "app.badge"
                            )
                        }
                    }

                    AppSection("Mode") {
                        AppCard {
                            modeRows(for: group)
                        }
                    }

                    AppSection("Unblock") {
                        AppCard {
                            configurationRow(
                                title: "Limited unblocks",
                                value: group.unblockConfig.isEnabled ? "On" : "Off",
                                systemImage: "lock.open"
                            )

                            if group.unblockConfig.isEnabled {
                                AppCardDivider()

                                configurationRow(
                                    title: "Unblocks per day",
                                    value: "\(group.unblockConfig.unblocksPerDay)",
                                    systemImage: "number"
                                )

                                AppCardDivider()

                                configurationRow(
                                    title: "Max duration",
                                    value: BlockingDisplayFormatter.fullDurationLabel(group.unblockConfig.maxDurationSeconds),
                                    systemImage: "timer"
                                )
                            }
                        }
                    }

                    AppSection("Friend Requests") {
                        AppCard {
                            configurationRow(
                                title: "Friend approval requests",
                                value: group.friendRequestConfig.isEnabled ? "On" : "Off",
                                systemImage: "person.2.badge.gearshape"
                            )
                        }
                    }

                    AppSection("Security") {
                        AppCard {
                            configurationRow(
                                title: "Passcode",
                                value: group.requiresPasswordSetup ? "Needs setup" : "Required",
                                systemImage: "key"
                            )
                        }
                    }
                } else {
                    AppCard {
                        Text("This block group is no longer available.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .appCardRow()
                    }
                }
            }
            .navigationTitle(group?.name ?? "Block Group")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if let group {
                    editButton(for: group)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        AppHaptics.buttonTap()
                        dismiss()
                    }
                }
            }
            .sheet(item: $passwordAction) { action in
                PasswordPromptView(action: action) { resolvedAction, group in
                    passwordAction = nil
                    if case .edit = resolvedAction {
                        editorDraft = BlockGroupDraft(group: group)
                    }
                } onSetPassword: { group in
                    passwordAction = nil
                    editorDraft = BlockGroupDraft(group: group)
                }
            }
            .sheet(item: $editorDraft) { draft in
                NavigationStack {
                    BlockGroupEditorView(initialDraft: draft) { group, password in
                        if model.upsertBlockGroup(group, password: password) {
                            editorDraft = nil
                        }
                    }
                }
            }
        }
    }

    private func header(for group: BlockGroup) -> some View {
        AppCard(cornerRadius: 24, opacity: 0.78) {
            HStack(spacing: 14) {
                Circle()
                    .fill(Color(hex: group.colorHex))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "lock.shield.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text(group.isEnabled ? "Blocking enabled" : "Blocking paused")
                        .font(.subheadline)
                        .foregroundStyle(group.isEnabled ? Color.green : Color.secondary)
                }

                Spacer()
            }
            .appCardRow(verticalPadding: 16)
        }
    }

    @ViewBuilder
    private func modeRows(for group: BlockGroup) -> some View {
        switch group.mode {
        case .scheduled(let startMinute, let endMinute, let days):
            configurationRow(title: "Current setting", value: "Schedule", systemImage: "calendar")
            AppCardDivider()
            configurationRow(title: "Days", value: BlockRuleKind.dayLabel(days), systemImage: "repeat")
            AppCardDivider()
            configurationRow(title: "Start", value: BlockRuleKind.timeLabel(startMinute), systemImage: "clock")
            AppCardDivider()
            configurationRow(title: "End", value: BlockRuleKind.timeLabel(endMinute), systemImage: "clock.arrow.circlepath")
        case .timeLimit(let limitSeconds, let days):
            configurationRow(title: "Current setting", value: "Daily time limit", systemImage: "hourglass")
            AppCardDivider()
            configurationRow(title: "Limit", value: BlockingDisplayFormatter.fullDurationLabel(limitSeconds), systemImage: "timer")
            AppCardDivider()
            configurationRow(title: "Days", value: BlockRuleKind.dayLabel(days), systemImage: "repeat")
        }
    }

    private func configurationRow(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer(minLength: 12)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
        }
        .appCardRow(verticalPadding: 12)
    }

    private func editButton(for group: BlockGroup) -> some View {
        VStack(spacing: 0) {
            Button {
                AppHaptics.buttonTap()
                beginPasscodeEdit(for: group)
            } label: {
                Label(group.requiresPasswordSetup ? "Set Passcode to Edit" : "Edit with Passcode", systemImage: "lock.open")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func beginPasscodeEdit(for group: BlockGroup) {
        if group.requiresPasswordSetup {
            editorDraft = BlockGroupDraft(group: group)
        } else {
            passwordAction = PasswordProtectedAction(kind: .edit, groupID: group.id)
        }
    }

    private func selectionCount(for group: BlockGroup) -> Int {
        guard let selection = try? BlockingSelectionCodec.decode(group.selectionData) else {
            return 0
        }

        return selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }
}

struct BlockGroupEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BlockGroupDraft
    @State private var isShowingActivityPicker = false
    @State private var unblockPicker: UnblockPicker?
    let onSave: (BlockGroup, String?) -> Void

    init(initialDraft: BlockGroupDraft, onSave: @escaping (BlockGroup, String?) -> Void) {
        _draft = State(initialValue: initialDraft)
        self.onSave = onSave
    }

    var body: some View {
        AppScreenScroll(backgroundStyle: .white) {
            AppSection("Apps & Websites To Block") {
                AppCard {
                    Button {
                        AppHaptics.buttonTap()
                        isShowingActivityPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "app.badge")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Choose Apps & Websites")
                                    .font(.subheadline.weight(.semibold))
                                Text("\(draft.selectionCount) selected")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .appCardRow()
                    }
                    .buttonStyle(.plain)
                }
            }

            AppSection("Mode") {
                AppCard {
                    Picker("Mode", selection: $draft.modeChoice) {
                        ForEach(BlockGroupModeChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .appCardRow()
                    .onChange(of: draft.modeChoice) {
                        AppHaptics.selectionChanged()
                    }

                    AppCardDivider()

                    if draft.modeChoice == .scheduled {
                        scheduledEditor
                    } else {
                        timeLimitEditor
                    }
                }
            }

            AppSection("Unblock") {
                AppCard {
                    unblockValueRow(
                        title: "Unblocks per day",
                        value: draft.localUnblocksEnabled ? "\(draft.unblocksPerDay)" : "None",
                        isEnabled: true
                    ) {
                        unblockPicker = .unblocksPerDay
                    }

                    AppCardDivider()

                    unblockValueRow(
                        title: "Max duration",
                        value: BlockingDisplayFormatter.fullDurationLabel(TimeInterval(draft.maxUnblockMinutes * 60)),
                        isEnabled: draft.localUnblocksEnabled
                    ) {
                        unblockPicker = .maxDuration
                    }
                }
            }

            AppSection("Friend Requests") {
                AppCard {
                    Toggle("Allow friend approval requests", isOn: $draft.friendRequestsEnabled)
                        .appCardRow()
                }
            }

            if draft.requiresPassword {
                AppSection("Passcode") {
                    AppCard {
                        SecureField("Group passcode", text: $draft.password)
                            .textContentType(.newPassword)
                            .appCardRow()

                        AppCardDivider()

                        SecureField("Confirm passcode", text: $draft.confirmPassword)
                            .textContentType(.newPassword)
                            .appCardRow()
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    AppHaptics.buttonTap()
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    AppHaptics.buttonTap()
                    save()
                }
            }

            ToolbarItem(placement: .principal) {
                TextField("New Block Group", text: $draft.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .frame(width: 210)
                    .accessibilityLabel("Block group name")
            }
        }
        .sheet(isPresented: $isShowingActivityPicker) {
            NavigationStack {
                FamilyActivityPicker(selection: $draft.selection)
                    .navigationTitle("Blocked Apps")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                AppHaptics.buttonTap()
                                isShowingActivityPicker = false
                            }
                        }
                    }
            }
        }
        .sheet(item: $unblockPicker) { picker in
            NavigationStack {
                switch picker {
                case .unblocksPerDay:
                    UnblocksPerDayPicker(selection: unblocksPerDaySelection)
                        .navigationTitle("Unblocks per Day")
                case .maxDuration:
                    MaxUnblockDurationPicker(minutes: $draft.maxUnblockMinutes)
                        .navigationTitle("Max Duration")
                }
            }
        }
    }

    private var scheduledEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            DatePicker(
                "Start at",
                selection: $draft.scheduledStartDate,
                displayedComponents: .hourAndMinute
            )
            .appCardRow()

            AppCardDivider()

            DatePicker(
                "End at",
                selection: $draft.scheduledEndDate,
                displayedComponents: .hourAndMinute
            )
            .appCardRow()

            AppCardDivider()

            RepeatDaysPicker(selectedDays: $draft.selectedDays)
                .appCardRow()
        }
    }

    private var timeLimitEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            DurationWheelPicker(minutes: $draft.limitMinutes)
                .appCardRow(verticalPadding: 14)

            AppCardDivider()

            RepeatDaysPicker(selectedDays: $draft.selectedDays)
                .appCardRow()
        }
    }

    private var unblocksPerDaySelection: Binding<Int> {
        Binding(
            get: {
                draft.localUnblocksEnabled ? draft.unblocksPerDay : 0
            },
            set: { value in
                if value == 0 {
                    draft.localUnblocksEnabled = false
                } else {
                    draft.localUnblocksEnabled = true
                    draft.unblocksPerDay = value
                }
            }
        )
    }

    private func unblockValueRow(
        title: String,
        value: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            AppHaptics.buttonTap()
            action()
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                Spacer()
                Text(value)
                    .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .appCardRow()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private func save() {
        guard !draft.requiresPassword || !draft.password.isEmpty else {
            return
        }

        guard draft.password == draft.confirmPassword else {
            return
        }

        do {
            let group = try draft.makeGroup()
            onSave(group, draft.requiresPassword ? draft.password : nil)
        } catch {
            return
        }
    }
}

enum BlockGroupModeChoice: String, CaseIterable, Identifiable {
    case scheduled = "Scheduled"
    case timeLimit = "Time Limit"

    var id: String { rawValue }
}

private enum UnblockPicker: Identifiable {
    case unblocksPerDay
    case maxDuration

    var id: String {
        switch self {
        case .unblocksPerDay:
            return "unblocksPerDay"
        case .maxDuration:
            return "maxDuration"
        }
    }
}

private struct UnblocksPerDayPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: Int

    var body: some View {
        VStack(spacing: 12) {
            Picker("Unblocks per day", selection: $selection) {
                Text("None").tag(0)
                ForEach(1...10, id: \.self) { count in
                    Text("\(count)").tag(count)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 220)
            .clipped()
            .onChange(of: selection) {
                AppHaptics.selectionChanged()
            }
        }
        .padding(.horizontal, 24)
        .background(Color.white.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    AppHaptics.buttonTap()
                    dismiss()
                }
            }
        }
    }
}

private struct MaxUnblockDurationPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var minutes: Int

    var body: some View {
        VStack(spacing: 12) {
            Picker("Max duration", selection: $minutes) {
                ForEach(BlockingUnblockDurationOptions.minutes, id: \.self) { option in
                    Text(BlockingDisplayFormatter.fullDurationLabel(TimeInterval(option * 60)))
                        .tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 220)
            .clipped()
            .onChange(of: minutes) {
                AppHaptics.selectionChanged()
            }
        }
        .padding(.horizontal, 24)
        .background(Color.white.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    AppHaptics.buttonTap()
                    dismiss()
                }
            }
        }
    }
}

struct BlockGroupDraft: Identifiable {
    var id: String
    var isNew: Bool
    var name: String
    var colorHex: String
    var selection: FamilyActivitySelection
    var isEnabled: Bool
    var modeChoice: BlockGroupModeChoice
    var scheduledStartDate: Date
    var scheduledEndDate: Date
    var limitMinutes: Int
    var selectedDays: Set<BlockWeekday>
    var localUnblocksEnabled: Bool
    var unblocksPerDay: Int
    var maxUnblockMinutes: Int
    var friendRequestsEnabled: Bool
    var requiresPassword: Bool
    var password = ""
    var confirmPassword = ""
    var createdAt: Date

    init() {
        let now = Date()
        id = UUID().uuidString
        isNew = true
        name = "New Block Group"
        colorHex = "#2E86AB"
        selection = FamilyActivitySelection()
        isEnabled = true
        modeChoice = .timeLimit
        scheduledStartDate = Self.date(forMinute: 22 * 60)
        scheduledEndDate = Self.date(forMinute: 7 * 60)
        limitMinutes = 30
        selectedDays = Set(BlockWeekday.everyDay)
        localUnblocksEnabled = true
        unblocksPerDay = 3
        maxUnblockMinutes = 15
        friendRequestsEnabled = false
        requiresPassword = true
        createdAt = now
    }

    init(group: BlockGroup) {
        id = group.id
        isNew = false
        name = group.name
        colorHex = group.colorHex
        selection = (try? BlockingSelectionCodec.decode(group.selectionData)) ?? FamilyActivitySelection()
        isEnabled = group.isEnabled
        localUnblocksEnabled = group.unblockConfig.isEnabled
        unblocksPerDay = group.unblockConfig.unblocksPerDay
        maxUnblockMinutes = BlockingUnblockDurationOptions.normalizedMinutes(
            max(1, Int(group.unblockConfig.maxDurationSeconds / 60))
        )
        friendRequestsEnabled = group.friendRequestConfig.isEnabled
        requiresPassword = group.requiresPasswordSetup
        createdAt = group.createdAt

        switch group.mode {
        case .scheduled(let startMinute, let endMinute, let days):
            modeChoice = .scheduled
            scheduledStartDate = Self.date(forMinute: startMinute)
            scheduledEndDate = Self.date(forMinute: endMinute)
            limitMinutes = 30
            selectedDays = Set(days)
        case .timeLimit(let limitSeconds, let days):
            modeChoice = .timeLimit
            scheduledStartDate = Self.date(forMinute: 22 * 60)
            scheduledEndDate = Self.date(forMinute: 7 * 60)
            limitMinutes = max(5, Int(limitSeconds / 60))
            selectedDays = Set(days)
        }
    }

    var selectionCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    func makeGroup() throws -> BlockGroup {
        let days = BlockRuleKind.normalizedDays(Array(selectedDays))
        let mode: BlockGroupMode
        switch modeChoice {
        case .scheduled:
            mode = .scheduled(
                startMinute: Self.minuteOfDay(from: scheduledStartDate),
                endMinute: Self.minuteOfDay(from: scheduledEndDate),
                days: days
            )
        case .timeLimit:
            mode = .timeLimit(
                limitSeconds: TimeInterval(limitMinutes * 60),
                days: days
            )
        }

        return BlockGroup(
            id: id,
            name: name,
            colorHex: colorHex,
            selectionData: try BlockingSelectionCodec.encode(selection),
            isEnabled: isEnabled,
            mode: mode,
            unblockConfig: BlockUnblockConfig(
                isEnabled: localUnblocksEnabled,
                unblocksPerDay: unblocksPerDay,
                maxDurationSeconds: TimeInterval(maxUnblockMinutes * 60)
            ),
            friendRequestConfig: BlockFriendRequestConfig(isEnabled: friendRequestsEnabled),
            createdAt: createdAt,
            updatedAt: Date()
        )
    }

    private static func date(forMinute minute: Int) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minute, to: start) ?? Date()
    }

    private static func minuteOfDay(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

private struct RepeatDaysPicker: View {
    @Binding var selectedDays: Set<BlockWeekday>

    private var everyDayBinding: Binding<Bool> {
        Binding(
            get: { selectedDays == Set(BlockWeekday.everyDay) },
            set: { isOn in
                AppHaptics.selectionChanged()
                if isOn {
                    selectedDays = Set(BlockWeekday.everyDay)
                } else {
                    selectedDays = Set(BlockWeekday.weekdays)
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Repeat every day", isOn: everyDayBinding)

            if selectedDays != Set(BlockWeekday.everyDay) {
                HStack(spacing: 7) {
                    ForEach(BlockWeekday.everyDay) { day in
                        Button {
                            AppHaptics.selectionChanged()
                            toggle(day)
                        } label: {
                            Text(day.shortLabel)
                                .font(.caption.weight(.semibold))
                                .frame(width: 36, height: 32)
                                .foregroundStyle(selectedDays.contains(day) ? Color.white : Color.primary)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selectedDays.contains(day) ? Color.accentColor : Color.white.opacity(0.62))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func toggle(_ day: BlockWeekday) {
        if selectedDays.contains(day), selectedDays.count > 1 {
            selectedDays.remove(day)
        } else {
            selectedDays.insert(day)
        }
    }
}

private struct DurationWheelPicker: View {
    @Binding var minutes: Int
    private let options = Array(stride(from: 5, through: 480, by: 5))

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Daily time available", selection: $minutes) {
                ForEach(options, id: \.self) { option in
                    Text(BlockingDisplayFormatter.fullDurationLabel(TimeInterval(option * 60)))
                        .tag(option)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .clipped()
            .onChange(of: minutes) {
                AppHaptics.selectionChanged()
            }

            Text("Daily time available")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Daily time limit")
        .accessibilityValue("\(minutes) minutes")
    }
}
