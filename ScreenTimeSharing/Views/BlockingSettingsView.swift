import FamilyControls
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RequestFeedView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    var highlightedFriendRequestID: String?
    var showsDoneButton = true
    @State private var selectedPhotoRequestID = ""
    @State private var isPhotoSwipeActive = false
    @State private var isChoosingRequestGroup = false
    @State private var requestGroup: BlockGroup?
    @State private var isShowingNoRequestGroupAlert = false

    private var pendingReceivedRequests: [BlockFriendRequest] {
        model.blockingState.friendRequests
            .filter { $0.isReceived(byAny: currentFriendIdentityIDs) && $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var currentFriendIdentityIDs: Set<String> {
        [model.profile.id, "profile-\(model.profile.id)"]
    }

    private var eligibleRequestGroups: [BlockGroup] {
        model.blockingState.groups
            .filter { group in
                group.isEnabled
                    && group.mode.isValid
                    && group.friendRequestConfig.isEnabled
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var friendRequestLogs: [BlockFriendRequest] {
        model.blockingState.friendRequests
            .sorted { first, second in
                let firstIsCollectable = isCollectableLog(first)
                let secondIsCollectable = isCollectableLog(second)
                if firstIsCollectable != secondIsCollectable {
                    return firstIsCollectable
                }

                return logSortDate(first) > logSortDate(second)
            }
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
        AppScreenScroll(backgroundStyle: .white, isScrollDisabled: isPhotoSwipeActive) {
            photoBookSection

            AppSection("Logs") {
                AppCard {
                    friendRequestLogList(friendRequestLogs)
                }
            }

            if !recentQuickRequests.isEmpty {
                AppSection("Quick Requests") {
                    AppCard {
                        quickRequestList(recentQuickRequests)
                    }
                }
            }
        }
        .refreshable {
            AppHaptics.selectionChanged()
            await model.reloadFriends()
            await model.syncFriendRequests()
        }
        .navigationTitle("Request Feed")
        .onAppear {
            model.expireStaleFriendRequests()
            syncSelectedPhotoRequest(preferredID: highlightedFriendRequestID)
            Task {
                await model.syncFriendRequests()
            }
        }
        .onChange(of: highlightedFriendRequestID) { _, newValue in
            syncSelectedPhotoRequest(preferredID: newValue)
        }
        .onChange(of: pendingReceivedRequests.map(\.id)) { _, _ in
            syncSelectedPhotoRequest(preferredID: highlightedFriendRequestID)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startInAppFriendRequest()
                } label: {
                    Image(systemName: "hands.sparkles.fill")
                }
                .accessibilityLabel("Create friend request")
            }

            if showsDoneButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        AppHaptics.buttonTap()
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog(
            "Choose App Group",
            isPresented: $isChoosingRequestGroup,
            titleVisibility: .visible
        ) {
            ForEach(eligibleRequestGroups) { group in
                Button(group.name) {
                    AppHaptics.buttonTap()
                    requestGroup = group
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pick which blocked app group this request is for.")
        }
        .sheet(item: $requestGroup) { group in
            FriendApprovalRequestView(group: group)
        }
        .alert("No Friend Request Group", isPresented: $isShowingNoRequestGroupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn on friend requests for an active block group before creating an in-app request.")
        }
    }

    @ViewBuilder
    private var photoBookSection: some View {
        if pendingReceivedRequests.isEmpty {
            AppCard {
                ContentUnavailableView(
                    "No Photo Requests",
                    systemImage: "photo.on.rectangle",
                    description: Text("New requests from friends will appear here.")
                )
                .appCardRow(verticalPadding: 20)
            }
        } else {
            FriendRequestPhotoStackView(
                requests: pendingReceivedRequests,
                selectedRequestID: $selectedPhotoRequestID,
                photoData: { request in
                    model.friendRequestPhotoData(for: request)
                },
                participantName: { request in
                    FriendRequestFeedDisplay.participantName(
                        for: request,
                        direction: .received,
                        profile: model.profile,
                        friends: model.friendSummaries
                    )
                },
                avatarColorHex: { request in
                    FriendRequestFeedDisplay.participantAvatarColorHex(
                        for: request,
                        direction: .received,
                        profile: model.profile,
                        friends: model.friendSummaries
                    )
                },
                avatarImageData: { request in
                    FriendRequestFeedDisplay.participantAvatarImageData(
                        for: request,
                        direction: .received,
                        profile: model.profile,
                        friends: model.friendSummaries
                    )
                },
                groupName: { request in
                    groupName(for: request.groupID)
                },
                expiresIn: { request in
                    FriendRequestFeedDisplay.remainingTimeLabel(until: request.pendingExpiresAt)
                },
                onDeny: { request in
                    resolvePhotoBookRequest(request, approve: false)
                },
                onApprove: { request in
                    resolvePhotoBookRequest(request, approve: true)
                },
                onHorizontalSwipeActiveChanged: { isActive in
                    isPhotoSwipeActive = isActive
                }
            )
            .frame(height: 580)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func friendRequestLogList(_ requests: [BlockFriendRequest]) -> some View {
        if requests.isEmpty {
            Text("No request logs yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .appCardRow()
        } else {
            ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
                if index > 0 {
                    AppCardDivider()
                }

                friendRequestLogRow(request, isHighlighted: request.id == highlightedFriendRequestID)
                .appCardRow(verticalPadding: 12)
            }
        }
    }

    private func friendRequestLogRow(_ request: BlockFriendRequest, isHighlighted: Bool = false) -> some View {
        let direction = direction(for: request)

        return VStack(alignment: .leading, spacing: 10) {
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

                    FriendRequestPhotoThumbnail(photoData: model.friendRequestPhotoData(for: request))

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
                CollectTimeButton {
                    model.collectFriendRequest(id: request.id)
                }
                .frame(maxWidth: .infinity)
            }
        case .received:
            EmptyView()
        }
    }

    @ViewBuilder
    private func quickRequestList(_ requests: [BlockingRequestListItem]) -> some View {
        ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
            if index > 0 {
                AppCardDivider()
            }

            requestRow(request)
                .appCardRow(verticalPadding: 12)
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
        request.isSent(byAny: currentFriendIdentityIDs) ? .sent : .received
    }

    private func isCollectableLog(_ request: BlockFriendRequest) -> Bool {
        request.isSent(byAny: currentFriendIdentityIDs) && request.status == .approved
    }

    private func logSortDate(_ request: BlockFriendRequest) -> Date {
        isCollectableLog(request) ? (request.resolvedAt ?? request.createdAt) : request.createdAt
    }

    private func groupName(for groupID: String) -> String {
        model.blockingState.groups.first { $0.id == groupID }?.name ?? "Unknown group"
    }

    private func syncSelectedPhotoRequest(preferredID: String? = nil) {
        let ids = pendingReceivedRequests.map(\.id)
        if let preferredID, ids.contains(preferredID) {
            selectedPhotoRequestID = preferredID
            return
        }

        if ids.contains(selectedPhotoRequestID) {
            return
        }

        selectedPhotoRequestID = ids.first ?? ""
    }

    private func startInAppFriendRequest() {
        AppHaptics.buttonTap()

        switch eligibleRequestGroups.count {
        case 0:
            isShowingNoRequestGroupAlert = true
        case 1:
            requestGroup = eligibleRequestGroups[0]
        default:
            isChoosingRequestGroup = true
        }
    }

    private func resolvePhotoBookRequest(_ request: BlockFriendRequest, approve: Bool) {
        let currentIDs = pendingReceivedRequests.map(\.id)
        let currentIndex = currentIDs.firstIndex(of: request.id) ?? 0
        let didResolve = approve
            ? model.approveFriendRequest(id: request.id)
            : model.denyFriendRequest(id: request.id)

        guard didResolve else {
            return
        }

        let remainingIDs = currentIDs.filter { $0 != request.id }
        if remainingIDs.isEmpty {
            selectedPhotoRequestID = ""
        } else if currentIndex < remainingIDs.count {
            selectedPhotoRequestID = remainingIDs[currentIndex]
        } else {
            selectedPhotoRequestID = remainingIDs[remainingIDs.count - 1]
        }
    }
}

private struct FriendRequestPhotoStackView: View {
    let requests: [BlockFriendRequest]
    @Binding var selectedRequestID: String
    let photoData: (BlockFriendRequest) -> Data?
    let participantName: (BlockFriendRequest) -> String
    let avatarColorHex: (BlockFriendRequest) -> String
    let avatarImageData: (BlockFriendRequest) -> Data?
    let groupName: (BlockFriendRequest) -> String
    let expiresIn: (BlockFriendRequest) -> String
    let onDeny: (BlockFriendRequest) -> Void
    let onApprove: (BlockFriendRequest) -> Void
    let onHorizontalSwipeActiveChanged: (Bool) -> Void
    @State private var dragOffset: CGSize = .zero
    @State private var flyAwayOffset: CGSize = .zero
    @State private var promotionProgress: CGFloat = 0
    @State private var stackDirection = 1
    @State private var isHorizontalDragActive = false
    @State private var advancingRequestID: String?
    @State private var isAdvancing = false
    @State private var resolutionIsApprove: Bool?

    var body: some View {
        GeometryReader { proxy in
            let cardSize = CGSize(
                width: max(260, proxy.size.width - 54),
                height: max(420, proxy.size.height - 54)
            )

            ZStack {
                ForEach(Array(stackedRequests(direction: stackDirection).reversed()), id: \.request.id) { item in
                    stackedCard(
                        item.request,
                        depth: item.depth,
                        cardSize: cardSize
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.spring(response: 0.36, dampingFraction: 0.84), value: selectedRequestID)
            .animation(.interactiveSpring(response: 0.30, dampingFraction: 0.86), value: dragOffset)
            .animation(.spring(response: 0.44, dampingFraction: 0.86), value: promotionProgress)
        }
    }

    @ViewBuilder
    private func stackedCard(
        _ request: BlockFriendRequest,
        depth: Int,
        cardSize: CGSize
    ) -> some View {
        if depth == 0 {
            let effectiveOffset = advancingRequestID == request.id ? flyAwayOffset : dragOffset

            photoBookCard(for: request)
                .frame(width: cardSize.width, height: cardSize.height)
                .rotationEffect(.degrees(topCardRotation(for: effectiveOffset)))
                .offset(effectiveOffset)
                .zIndex(Double(10 - depth))
                .simultaneousGesture(dragGesture(cardWidth: cardSize.width))
                .allowsHitTesting(!isAdvancing)
        } else {
            let visualDepth = max(0, CGFloat(depth) - promotionProgress)

            photoBookCard(for: request)
                .frame(width: cardSize.width, height: cardSize.height)
                .scaleEffect(stackedScale(depth: visualDepth))
                .rotationEffect(.degrees(stackedRotation(depth: visualDepth)))
                .offset(stackedOffset(depth: visualDepth))
                .opacity(advancingRequestID == request.id ? 0 : 1)
                .zIndex(Double(10 - depth))
                .allowsHitTesting(false)
        }
    }

    private func photoBookCard(for request: BlockFriendRequest) -> some View {
        FriendRequestPhotoBookCard(
            request: request,
            photoData: photoData(request),
            participantName: participantName(request),
            avatarColorHex: avatarColorHex(request),
            avatarImageData: avatarImageData(request),
            groupName: groupName(request),
            expiresIn: expiresIn(request),
            verdictIsApprove: advancingRequestID == request.id ? resolutionIsApprove : nil,
            onDeny: {
                resolveWithAnimation(request, approve: false)
            },
            onApprove: {
                resolveWithAnimation(request, approve: true)
            }
        )
    }

    /// Flies the card off (right for approve, left for deny) with a haptic,
    /// then performs the actual resolution once the card has left the screen.
    private func resolveWithAnimation(_ request: BlockFriendRequest, approve: Bool) {
        guard !isAdvancing else {
            return
        }

        if approve {
            AppHaptics.success()
        } else {
            AppHaptics.warning()
        }

        isAdvancing = true
        advancingRequestID = request.id
        stackDirection = 1

        // Flood the card with its verdict color first, then fling it.
        withAnimation(.spring(response: 0.26, dampingFraction: 0.7)) {
            resolutionIsApprove = approve
        }
        withAnimation(.easeOut(duration: 0.34).delay(0.16)) {
            flyAwayOffset = CGSize(width: approve ? 620 : -620, height: -46)
            dragOffset = .zero
        }
        withAnimation(.spring(response: 0.44, dampingFraction: 0.86).delay(0.16)) {
            promotionProgress = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                flyAwayOffset = .zero
                promotionProgress = 0
                advancingRequestID = nil
                isAdvancing = false
                resolutionIsApprove = nil
            }
            if approve {
                onApprove(request)
            } else {
                onDeny(request)
            }
        }
    }

    private func dragGesture(cardWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard !isAdvancing else {
                    return
                }

                guard isHorizontalDrag(value) else {
                    setHorizontalDragActive(false)
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
                        dragOffset = .zero
                        promotionProgress = 0
                    }
                    return
                }

                setHorizontalDragActive(true)
                if abs(value.translation.width) > 8 {
                    stackDirection = value.translation.width < 0 ? 1 : -1
                }
                dragOffset = CGSize(width: value.translation.width, height: 0)
                promotionProgress = min(0.34, abs(value.translation.width) / max(cardWidth, 1) * 0.9)
            }
            .onEnded { value in
                guard !isAdvancing else {
                    return
                }

                guard isHorizontalDragActive, let direction = dragAdvanceDirection(value), requests.count > 1 else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        dragOffset = .zero
                        promotionProgress = 0
                    }
                    setHorizontalDragActive(false)
                    return
                }

                let exitingID = selectedRequestID
                AppHaptics.selectionChanged()
                stackDirection = direction
                isAdvancing = true
                setHorizontalDragActive(false)
                advancingRequestID = exitingID

                withAnimation(.easeOut(duration: 0.28)) {
                    flyAwayOffset = dismissalOffset(
                        direction: direction,
                        cardWidth: cardWidth,
                        drag: value
                    )
                    dragOffset = .zero
                }

                withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
                    promotionProgress = 1
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        moveSelection(by: direction)
                        flyAwayOffset = .zero
                        promotionProgress = 0
                        setHorizontalDragActive(false)
                        advancingRequestID = nil
                        isAdvancing = false
                    }
                }
            }
    }

    private func stackedRequests(direction: Int) -> [(depth: Int, request: BlockFriendRequest)] {
        guard !requests.isEmpty else {
            return []
        }

        let selectedIndex = requests.firstIndex { $0.id == selectedRequestID } ?? 0
        let stackCount = min(3, requests.count)
        let signedDirection = direction >= 0 ? 1 : -1

        return (0..<stackCount).map { depth in
            let rawIndex = selectedIndex + depth * signedDirection
            let index = (rawIndex % requests.count + requests.count) % requests.count
            return (depth: depth, request: requests[index])
        }
    }

    private func stackedScale(depth: CGFloat) -> CGFloat {
        max(0.88, 1 - depth * 0.045)
    }

    private func stackedOffset(depth: CGFloat) -> CGSize {
        interpolatedStackValue(
            depth: depth,
            top: .zero,
            middle: CGSize(width: 10, height: 18),
            back: CGSize(width: -8, height: 34)
        )
    }

    private func stackedRotation(depth: CGFloat) -> Double {
        Double(
            interpolatedStackValue(
                depth: depth,
                top: CGFloat.zero,
                middle: 2.8,
                back: -2.2
            )
        )
    }

    private func interpolatedStackValue(
        depth: CGFloat,
        top: CGFloat,
        middle: CGFloat,
        back: CGFloat
    ) -> CGFloat {
        let clampedDepth = min(2, max(0, depth))
        if clampedDepth <= 1 {
            return top + (middle - top) * clampedDepth
        }

        return middle + (back - middle) * (clampedDepth - 1)
    }

    private func interpolatedStackValue(
        depth: CGFloat,
        top: CGSize,
        middle: CGSize,
        back: CGSize
    ) -> CGSize {
        CGSize(
            width: interpolatedStackValue(depth: depth, top: top.width, middle: middle.width, back: back.width),
            height: interpolatedStackValue(depth: depth, top: top.height, middle: middle.height, back: back.height)
        )
    }

    private func topCardRotation(for offset: CGSize) -> Double {
        let rawDegrees = Double(offset.width / 18)
        return min(10, max(-10, rawDegrees))
    }

    private func isHorizontalDrag(_ value: DragGesture.Value) -> Bool {
        if isHorizontalDragActive {
            return true
        }

        let horizontal = abs(value.translation.width)
        let vertical = abs(value.translation.height)
        return horizontal > 14 && horizontal > vertical * 1.2
    }

    private func setHorizontalDragActive(_ isActive: Bool) {
        guard isHorizontalDragActive != isActive else {
            return
        }

        isHorizontalDragActive = isActive
        onHorizontalSwipeActiveChanged(isActive)
    }

    private func moveSelection(by delta: Int) {
        guard requests.count > 1 else {
            return
        }

        let currentIndex = requests.firstIndex { $0.id == selectedRequestID } ?? 0
        let nextIndex = (currentIndex + delta + requests.count) % requests.count
        selectedRequestID = requests[nextIndex].id
    }

    private func dragAdvanceDirection(_ value: DragGesture.Value) -> Int? {
        let projectedWidth = value.predictedEndTranslation.width
        let projectedHeight = value.predictedEndTranslation.height
        guard abs(projectedWidth) > 110, abs(projectedWidth) > abs(projectedHeight) * 1.15 else {
            return nil
        }

        return projectedWidth < 0 ? 1 : -1
    }

    private func dismissalOffset(
        direction: Int,
        cardWidth: CGFloat,
        drag: DragGesture.Value
    ) -> CGSize {
        let horizontal = direction > 0 ? -cardWidth * 1.28 : cardWidth * 1.28
        return CGSize(width: horizontal, height: 0)
    }
}

private struct FriendRequestPhotoBookCard: View {
    let request: BlockFriendRequest
    let photoData: Data?
    let participantName: String
    let avatarColorHex: String
    let avatarImageData: Data?
    let groupName: String
    let expiresIn: String
    var verdictIsApprove: Bool? = nil
    let onDeny: () -> Void
    let onApprove: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            FriendRequestPhotoImage(photoData: photoData)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.0), location: 0.25),
                    .init(color: .black.opacity(0.48), location: 0.70),
                    .init(color: .black.opacity(0.74), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    HStack(spacing: 10) {
                        ProfileAvatar(
                            imageData: avatarImageData,
                            colorHex: avatarColorHex,
                            initials: participantName.initials,
                            size: 44
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(participantName)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text(FriendRequestFeedDisplay.relativeRequestAge(request.createdAt))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.76))
                        }
                    }

                    Spacer()

                    Text("Expires in \(expiresIn)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.28), in: Capsule())
                }

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        if let appNames = request.groupAppNames, !appNames.isEmpty {
                            // The requester's top apps inside the group — a much
                            // clearer picture of what's being unlocked than a
                            // generated group thumbnail.
                            HStack(spacing: -10) {
                                ForEach(Array(appNames.prefix(3).enumerated()), id: \.offset) { index, appName in
                                    AppUsageIcon(name: appName, size: 30)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 30 * 0.24, style: .continuous)
                                                .strokeBorder(.black.opacity(0.45), lineWidth: 1.5)
                                        }
                                        .zIndex(Double(3 - index))
                                }
                            }
                        } else {
                            AppUsageIcon(name: groupName)
                                .scaleEffect(0.78)
                                .frame(width: 34, height: 34)
                        }

                        Text(groupName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Text(BlockingDisplayFormatter.durationLabel(request.requestedSeconds))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }

                    if let message = FriendRequestFeedDisplay.message(for: request) {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.90))
                            .lineLimit(3)
                    }

                    HStack(spacing: 10) {
                        Button {
                            onDeny()
                        } label: {
                            Text("Deny")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.red.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)

                        Button {
                            onApprove()
                        } label: {
                            Text("Approve")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Color.green.opacity(0.86), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(18)

            if let verdictIsApprove {
                (verdictIsApprove ? Color.green : Color.red)
                    .opacity(0.92)
                    .overlay {
                        Image(systemName: verdictIsApprove ? "checkmark" : "xmark")
                            .font(.system(size: 76, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 26, x: 0, y: 15)
    }
}

private struct FriendRequestPhotoThumbnail: View {
    let photoData: Data?
    private let thumbnailSize = CGSize(width: 58, height: 72)

    var body: some View {
        FriendRequestPhotoImage(photoData: photoData)
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
            }
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
    }
}

private struct FriendRequestPhotoImage: View {
    let photoData: Data?

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let photoData, let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.22, blue: 0.28),
                Color(red: 0.08, green: 0.10, blue: 0.14)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "camera.fill")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.62))
        }
    }
}

private struct FriendRequestDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let requestID: String

    private var request: BlockFriendRequest? {
        model.blockingState.friendRequests.first { $0.id == requestID }
    }

    private var currentFriendIdentityIDs: Set<String> {
        [model.profile.id, "profile-\(model.profile.id)"]
    }

    var body: some View {
        AppScreenScroll(backgroundStyle: .white) {
            if let request {
                let direction = FriendRequestFeedDisplay.direction(for: request, currentUserIDs: currentFriendIdentityIDs)
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
                let avatarImageData = FriendRequestFeedDisplay.participantAvatarImageData(
                    for: request,
                    direction: direction,
                    profile: model.profile,
                    friends: model.friendSummaries
                )

                FriendRequestPhotoImage(photoData: model.friendRequestPhotoData(for: request))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 5, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)

                VStack(spacing: 9) {
                    ProfileAvatar(
                        imageData: avatarImageData,
                        colorHex: avatarColorHex,
                        initials: participantName.initials,
                        size: 64
                    )

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
                .padding(.top, 2)
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
                CollectTimeButton(
                    title: "Collect Time",
                    font: .subheadline.weight(.semibold),
                    verticalPadding: 11
                ) {
                    model.collectFriendRequest(id: request.id)
                }
            }
        case .received:
            EmptyView()
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
    static func direction(for request: BlockFriendRequest, currentUserIDs: Set<String>) -> FriendRequestDirection {
        request.isSent(byAny: currentUserIDs) ? .sent : .received
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

    static func remainingTimeLabel(until date: Date, now: Date = Date()) -> String {
        let remainingSeconds = max(0, date.timeIntervalSince(now))
        guard remainingSeconds > 0 else {
            return "0m"
        }

        let hours = Int(remainingSeconds) / 3_600
        let minutes = max(1, (Int(remainingSeconds) % 3_600 + 59) / 60)

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
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

    static func participantAvatarImageData(
        for request: BlockFriendRequest,
        direction: FriendRequestDirection,
        profile: UserProfile,
        friends: [FriendUsageSummary]
    ) -> Data? {
        switch direction {
        case .sent:
            guard let firstFriendID = request.selectedFriendIDs.first else {
                return nil
            }
            return friendAvatarImageData(firstFriendID, profile: profile, friends: friends)
        case .received:
            guard let requesterID = request.requesterID else {
                return nil
            }
            return friendAvatarImageData(requesterID, profile: profile, friends: friends)
        }
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

    private static func friendAvatarImageData(
        _ id: String,
        profile: UserProfile,
        friends: [FriendUsageSummary]
    ) -> Data? {
        if id == profile.id {
            return profile.avatarImageData
        }

        return friends.first { $0.id == id }?.avatarImageData
    }
}

struct BlockingSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var model: AppModel
    var highlightedFriendRequestID: String?

    @State private var editorDraft: BlockGroupDraft?
    @State private var passwordAction: PasswordProtectedAction?

    var body: some View {
        AppScreenScroll(backgroundStyle: .white) {
            if model.blockingState.groups.isEmpty {
                AppSection("Block Groups") {
                    AppCard {
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
                    }
                }
            } else {
                AppSection("Block Groups") {
                    AppCard {
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
                    }
                }

                if !activeBlockGroups.isEmpty {
                    AppSection("Active") {
                        groupListCard(activeBlockGroups)
                    }
                }

                if !inactiveBlockGroups.isEmpty {
                    AppSection("Inactive") {
                        groupListCard(inactiveBlockGroups, isMuted: true)
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
                    let didSave = model.upsertBlockGroup(group, password: password)
                    if didSave {
                        editorDraft = nil
                    }
                    return didSave
                }
            }
        }
        .sheet(item: $passwordAction) { action in
            PasswordPromptView(action: action) { resolvedAction, group, verifiedPassword in
                passwordAction = nil
                handleUnlockedAction(resolvedAction, group: group, verifiedPassword: verifiedPassword)
            } onSetPassword: { group in
                passwordAction = nil
                editorDraft = BlockGroupDraft(group: group)
            }
        }
    }

    private var activeBlockGroups: [BlockGroup] {
        model.blockingState.groups.filter(\.isEnabled)
    }

    private var inactiveBlockGroups: [BlockGroup] {
        model.blockingState.groups.filter { !$0.isEnabled }
    }

    private var currentFriendIdentityIDs: Set<String> {
        [model.profile.id, "profile-\(model.profile.id)"]
    }

    private var sentFriendRequests: [BlockFriendRequest] {
        model.blockingState.friendRequests
            .filter { $0.isSent(byAny: currentFriendIdentityIDs) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var receivedFriendRequests: [BlockFriendRequest] {
        model.blockingState.friendRequests
            .filter { $0.isReceived(byAny: currentFriendIdentityIDs) }
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
                    #if DENY_INTERNAL_DEBUG
                    Text("dbg me=\(model.profile.id.prefix(6)) req=\(request.requesterID?.prefix(6) ?? "nil") to=[\(request.selectedFriendIDs.map { String($0.prefix(6)) }.joined(separator: ","))]")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.orange)
                    #endif
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
                CollectTimeButton {
                    model.collectFriendRequest(id: request.id)
                }
            }
        case .received:
            EmptyView()
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
        request.isSent(byAny: currentFriendIdentityIDs) ? .sent : .received
    }

    private func groupListCard(_ groups: [BlockGroup], isMuted: Bool = false) -> some View {
        AppCard {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    AppCardDivider()
                }
                groupRow(group, isMuted: isMuted)
                    .appCardRow(verticalPadding: 13)
            }
        }
    }

    private func groupRow(_ group: BlockGroup, isMuted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Circle()
                    .fill(isMuted ? Color.secondary.opacity(0.36) : Color(hex: group.colorHex))
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
                    if let reset = group.passwordReset {
                        TimelineView(.periodic(from: Date(), by: 60)) { context in
                            Label(
                                PasswordResetDisplayFormatter.statusLabel(for: reset, now: context.date),
                                systemImage: "clock.badge.exclamationmark"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.yellow)
                            .lineLimit(1)
                        }
                    }
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

            }

            HStack(spacing: 8) {
                pill(group.isEnabled ? "Active" : "Inactive", systemImage: group.isEnabled ? "checkmark.circle" : "pause.circle")
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
        .saturation(isMuted ? 0 : 1)
        .opacity(isMuted ? 0.62 : 1)
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

        passwordAction = PasswordProtectedAction(kind: kind, groupID: group.id)
    }

    private func handleUnlockedAction(
        _ kind: PasswordProtectedAction.Kind,
        group: BlockGroup,
        verifiedPassword: String?
    ) {
        switch kind {
        case .edit:
            editorDraft = BlockGroupDraft(group: group)
        case .toggleEnabled:
            _ = model.toggleBlockGroup(group, password: verifiedPassword)
        case .delete:
            _ = model.deleteBlockGroup(group, password: verifiedPassword)
        }
    }

    private func pill(
        _ title: String,
        systemImage: String,
        foregroundStyle: Color = .secondary
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(pillBackground, in: Capsule())
    }

    private var pillBackground: Color {
        colorScheme == .dark
            ? Color(uiColor: .tertiarySystemGroupedBackground)
            : Color.white.opacity(0.58)
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

private enum PasswordResetDisplayFormatter {
    static func statusLabel(for reset: BlockPasswordResetState, now: Date = Date()) -> String {
        guard !reset.isAvailable(now: now) else {
            return "Recovery ready"
        }

        return "Recovery in \(remainingLabel(for: reset, now: now))"
    }

    static func detailLabel(for reset: BlockPasswordResetState, now: Date = Date()) -> String {
        guard !reset.isAvailable(now: now) else {
            return "Recovery ready. Set a new password."
        }

        return "Recovery unlocks in \(remainingLabel(for: reset, now: now))"
    }

    private static func remainingLabel(for reset: BlockPasswordResetState, now: Date) -> String {
        let remaining = max(0, reset.availableAt.timeIntervalSince(now))
        let totalMinutes = max(1, Int(ceil(remaining / 60)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

struct PasswordPromptView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    let action: PasswordProtectedAction
    let onUnlocked: (PasswordProtectedAction.Kind, BlockGroup, String?) -> Void
    let onSetPassword: (BlockGroup) -> Void

    @State private var password = ""
    @State private var newPassword = ""
    @State private var isConfirmingPasswordRecovery = false
    @State private var passwordError: String?

    private var group: BlockGroup? {
        model.blockingState.groups.first { $0.id == action.groupID }
    }

    private var navigationTitle: String {
        switch action.kind {
        case .delete:
            return "Delete Group"
        case .edit, .toggleEnabled:
            return "Unlock Group"
        }
    }

    private var submitLabel: String {
        switch action.kind {
        case .delete:
            return "Delete"
        case .edit, .toggleEnabled:
            return "Unlock"
        }
    }

    private var submitSystemImage: String {
        switch action.kind {
        case .delete:
            return "trash"
        case .edit, .toggleEnabled:
            return "lock.open"
        }
    }

    private var submitColor: Color {
        switch action.kind {
        case .delete:
            return Color(red: 0.86, green: 0.24, blue: 0.22)
        case .edit, .toggleEnabled:
            return Color.accentColor
        }
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

                                    if let passwordError {
                                        Label(passwordError, systemImage: "exclamationmark.circle.fill")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundStyle(Color(red: 0.86, green: 0.24, blue: 0.22))
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }

                                    Button {
                                        if model.verifyPassword(for: group, password: password) {
                                            AppHaptics.buttonTap()
                                            passwordError = nil
                                            onUnlocked(action.kind, group, password)
                                        } else {
                                            AppHaptics.selectionChanged()
                                            withAnimation(.snappy(duration: 0.18)) {
                                                passwordError = password.isEmpty
                                                    ? "Enter the group passcode."
                                                    : "Incorrect passcode. Try again."
                                            }
                                        }
                                    } label: {
                                        Label(submitLabel, systemImage: submitSystemImage)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(submitColor)
                                }
                                .appCardRow()
                            }
                        }
                    }
                }
                .onChange(of: password) {
                    if passwordError != nil {
                        withAnimation(.snappy(duration: 0.18)) {
                            passwordError = nil
                        }
                    }
                }

                if let group, !group.requiresPasswordSetup {
                    AppSection("Recovery") {
                        AppCard {
                            if let reset = group.passwordReset {
                                VStack(alignment: .leading, spacing: 12) {
                                    TimelineView(.periodic(from: Date(), by: 60)) { context in
                                        Label(
                                            PasswordResetDisplayFormatter.detailLabel(for: reset, now: context.date),
                                            systemImage: "clock.badge.exclamationmark"
                                        )
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(reset.isAvailable(now: context.date) ? Color.green : Color.yellow)
                                    }

                                    if reset.isAvailable() {
                                        SecureField("New passcode", text: $newPassword)
                                            .textContentType(.newPassword)
                                        Button {
                                            if model.completePasswordReset(for: group, newPassword: newPassword),
                                               let updatedGroup = model.blockingState.groups.first(where: { $0.id == group.id }) {
                                                AppHaptics.buttonTap()
                                                onUnlocked(action.kind, updatedGroup, newPassword)
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
                                    isConfirmingPasswordRecovery = true
                                } label: {
                                    Label("Forgot Password", systemImage: "clock.badge.exclamationmark")
                                        .appCardRow()
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AppHaptics.buttonTap()
                        dismiss()
                    }
                }
            }
            .alert("Start Password Recovery?", isPresented: $isConfirmingPasswordRecovery) {
                Button("Cancel", role: .cancel) {}
                Button("Start Recovery") {
                    guard let group else {
                        return
                    }
                    AppHaptics.buttonTap()
                    model.requestPasswordReset(for: group)
                }
            } message: {
                Text("This starts a recovery timer. You will need to wait about 1 minute before you can set a new password for this block group.")
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
    @State private var editorPassword: String?
    @State private var isConfirmingDelete = false
    @State private var pendingDeletePassword: String?

    private var group: BlockGroup? {
        model.blockingState.groups.first { $0.id == groupID }
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                if let group {
                    header(for: group)

                    AppSection("Status") {
                        AppCard {
                            activeToggle(for: group)
                        }
                    }

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
                                value: passcodeStatus(for: group),
                                systemImage: "key"
                            )

                            if let reset = group.passwordReset {
                                AppCardDivider()

                                TimelineView(.periodic(from: Date(), by: 60)) { context in
                                    configurationRow(
                                        title: "Recovery",
                                        value: PasswordResetDisplayFormatter.statusLabel(for: reset, now: context.date),
                                        systemImage: "clock.badge.exclamationmark",
                                        tint: .yellow
                                    )
                                }
                            }
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
                    footerActions(for: group)
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
                PasswordPromptView(action: action) { resolvedAction, group, verifiedPassword in
                    passwordAction = nil
                    switch resolvedAction {
                    case .edit:
                        editorPassword = verifiedPassword
                        editorDraft = BlockGroupDraft(group: group)
                    case .toggleEnabled:
                        _ = model.toggleBlockGroup(group, password: verifiedPassword)
                    case .delete:
                        pendingDeletePassword = verifiedPassword
                        isConfirmingDelete = true
                    }
                } onSetPassword: { group in
                    passwordAction = nil
                    editorPassword = nil
                    editorDraft = BlockGroupDraft(group: group)
                }
            }
            .sheet(item: $editorDraft) { draft in
                NavigationStack {
                    BlockGroupEditorView(
                        initialDraft: draft,
                        canDelete: !draft.isNew,
                        onSave: { group, password in
                            let didSave = model.upsertBlockGroup(group, password: password)
                            if didSave {
                                editorDraft = nil
                            }
                            return didSave
                        },
                        onDelete: {
                            guard let group else {
                                return
                            }
                            if model.deleteBlockGroup(group, password: editorPassword) {
                                editorDraft = nil
                                dismiss()
                            }
                        }
                    )
                }
            }
            .alert("Delete Block Group?", isPresented: $isConfirmingDelete) {
                Button("Cancel", role: .cancel) {
                    pendingDeletePassword = nil
                }
                Button("Delete", role: .destructive) {
                    guard let group else {
                        return
                    }

                    AppHaptics.buttonTap()
                    if model.deleteBlockGroup(group, password: pendingDeletePassword) {
                        pendingDeletePassword = nil
                        dismiss()
                    }
                }
            } message: {
                Text("This removes the block group, its requests, and unblock history.")
            }
        }
    }

    private func activeToggle(for group: BlockGroup) -> some View {
        Button {
            beginPasscodeToggle(for: group)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: group.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.isEnabled ? "Active" : "Inactive")
                        .font(.subheadline.weight(.semibold))
                    Text(group.isEnabled ? "This block group is currently enforcing." : "This block group is paused.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: .constant(group.isEnabled))
                    .labelsHidden()
                    .disabled(true)
                    .allowsHitTesting(false)
                    .tint(.secondary)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(0.72)
        .appCardRow(verticalPadding: 12)
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

    private func configurationRow(
        title: String,
        value: String,
        systemImage: String,
        tint: Color = .secondary
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
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

    private func passcodeStatus(for group: BlockGroup) -> String {
        if group.requiresPasswordSetup {
            return "Needs setup"
        }

        return "Required"
    }

    private func footerActions(for group: BlockGroup) -> some View {
        VStack(spacing: 10) {
            Button {
                AppHaptics.buttonTap()
                beginPasscodeEdit(for: group)
            } label: {
                Label(editButtonTitle(for: group), systemImage: "lock.open")
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
            .appRoundedButtonHitArea(cornerRadius: 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func editButtonTitle(for group: BlockGroup) -> String {
        if group.requiresPasswordSetup {
            return "Set Passcode to Edit"
        }

        return "Edit with Passcode"
    }

    private func isUnlockedForDisplay(_ group: BlockGroup) -> Bool {
        model.groupUnlockExpirations[group.id, default: .distantPast] > Date()
    }

    private func beginPasscodeEdit(for group: BlockGroup) {
        if group.requiresPasswordSetup {
            editorDraft = BlockGroupDraft(group: group)
        } else {
            passwordAction = PasswordProtectedAction(kind: .edit, groupID: group.id)
        }
    }

    private func beginPasscodeToggle(for group: BlockGroup) {
        AppHaptics.buttonTap()
        passwordAction = PasswordProtectedAction(kind: .toggleEnabled, groupID: group.id)
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
    @State private var passwordSetupGroup: BlockGroup?
    @State private var saveError: String?
    @State private var isSaving = false
    @FocusState private var isNameFieldFocused: Bool
    @State private var isConfirmingDelete = false
    let canDelete: Bool
    let onSave: (BlockGroup, String?) -> Bool
    let onDelete: (() -> Void)?

    init(
        initialDraft: BlockGroupDraft,
        canDelete: Bool = false,
        onSave: @escaping (BlockGroup, String?) -> Bool,
        onDelete: (() -> Void)? = nil
    ) {
        _draft = State(initialValue: initialDraft)
        self.canDelete = canDelete
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private func onDeleteDraft() {
        onDelete?()
    }

    var body: some View {
        AppScreenScroll(backgroundStyle: .white) {
            AppSection("Status") {
                AppCard {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            TextField("New Block Group", text: $draft.name)
                                .font(.headline)
                                .textInputAutocapitalization(.words)
                                .submitLabel(.done)
                                .focused($isNameFieldFocused)
                                .accessibilityLabel("Block group name")

                            Button {
                                AppHaptics.buttonTap()
                                isNameFieldFocused = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Edit group name")
                        }
                        .appCardRow(verticalPadding: 4)

                        Divider()

                        Toggle(
                            isOn: $draft.isEnabled
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: draft.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill")
                                    .foregroundStyle(draft.isEnabled ? Color.green : Color.secondary)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(draft.isEnabled ? "Active" : "Inactive")
                                        .font(.subheadline.weight(.semibold))
                                    Text(draft.isEnabled ? "This block group is currently enforcing." : "This block group is paused.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(.green)
                        .onChange(of: draft.isEnabled) {
                            AppHaptics.selectionChanged()
                        }
                    }
                }
            }

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

            if let saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }

            if canDelete, onDelete != nil {
                Button(role: .destructive) {
                    AppHaptics.buttonTap()
                    isConfirmingDelete = true
                } label: {
                    Text("Delete Block Group")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.86, green: 0.24, blue: 0.22))
                }
                .appRoundedButtonHitArea(cornerRadius: 16)
                .padding(.top, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .alert("Delete Block Group?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDeleteDraft()
            }
        } message: {
            Text("This permanently removes \(draft.name.isEmpty ? "this block group" : draft.name) and its rules.")
        }
        .safeAreaInset(edge: .bottom) {
            saveButton
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    AppHaptics.buttonTap()
                    dismiss()
                }
                .disabled(isSaving)
            }

            ToolbarItem(placement: .principal) {
                Text(draft.name.isEmpty ? "New Block Group" : draft.name)
                    .font(.headline)
                    .lineLimit(1)
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
        .sheet(item: $passwordSetupGroup) { group in
            NavigationStack {
                BlockGroupPasswordSetupView(groupName: group.name) { password in
                    onSave(group, password)
                }
            }
        }
    }

    private var saveButton: some View {
        VStack(spacing: 0) {
            Button {
                AppHaptics.buttonTap()
                save()
            } label: {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }

                    Text(isSaving ? "Saving..." : "Save")
                }
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
            .appRoundedButtonHitArea(cornerRadius: 16)
            .disabled(isSaving)
            .opacity(isSaving ? 0.82 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
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
        guard !isSaving else {
            return
        }

        do {
            let group = try draft.makeGroup()
            saveError = nil
            if draft.requiresPassword {
                passwordSetupGroup = group
            } else {
                isSaving = true
                Task { @MainActor in
                    let didSave = onSave(group, nil)
                    if !didSave {
                        saveError = "Could not save this block group. Please check the settings and try again."
                        isSaving = false
                    }
                }
            }
        } catch {
            saveError = "Could not save this block group. Please check the settings and try again."
        }
    }
}

private struct BlockGroupPasswordSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let groupName: String
    let onSave: (String) -> Bool

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var validationMessage: String?
    @State private var isSaving = false

    var body: some View {
        AppScreenScroll(backgroundStyle: .white) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "key.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(Color.accentColor)

                Text("Set a Password")
                    .font(.title2.bold())

                Text("This password is required before \(groupName) can be edited, disabled, or deleted.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            AppSection("How It Works") {
                AppCard {
                    passwordInfoRow(
                        systemImage: "lock.fill",
                        title: "Protects this group",
                        message: Text("You will need this password to change the block group later.")
                    )

                    AppCardDivider()

                    passwordInfoRow(
                        systemImage: "clock.badge.exclamationmark",
                        title: "Forgot password delay",
                        message: Text("If you forget it, reset takes ")
                            + Text("about 1 minute before it unlocks.").bold(),
                        iconColor: .yellow
                    )

                    AppCardDivider()

                    passwordInfoRow(
                        systemImage: "square.and.arrow.down",
                        title: "Store it safely",
                        message: Text("Pick something difficult to casually remember and keep it somewhere safe.")
                    )
                }
            }

            AppSection("Password") {
                AppCard {
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .appCardRow()

                    AppCardDivider()

                    SecureField("Confirm password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .appCardRow()
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
        .disabled(isSaving)
        .safeAreaInset(edge: .bottom) {
            bottomSaveButton
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    AppHaptics.buttonTap()
                    dismiss()
                }
                .disabled(isSaving)
            }
        }
    }

    private var bottomSaveButton: some View {
        VStack(spacing: 0) {
            Button {
                save()
            } label: {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }

                    Text(isSaving ? "Saving..." : "Save Block Group")
                }
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
            .appRoundedButtonHitArea(cornerRadius: 16)
            .disabled(isSaving)
            .opacity(isSaving ? 0.82 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func passwordInfoRow(
        systemImage: String,
        title: String,
        message: Text,
        iconColor: Color = Color.accentColor
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                message
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appCardRow(verticalPadding: 12)
    }

    private func save() {
        guard !isSaving else {
            return
        }

        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            validationMessage = "Enter a password before saving."
            return
        }

        guard password == confirmPassword else {
            validationMessage = "Passwords do not match."
            return
        }

        validationMessage = nil
        AppHaptics.buttonTap()
        isSaving = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            let didSave = onSave(trimmedPassword)
            if !didSave {
                validationMessage = "Could not save this block group. Please check the settings and try again."
                isSaving = false
            }
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
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
        localUnblocksEnabled = false
        unblocksPerDay = 3
        maxUnblockMinutes = 15
        friendRequestsEnabled = true
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
    @Environment(\.colorScheme) private var colorScheme
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
                                        .fill(selectedDays.contains(day) ? Color.accentColor : unselectedDayBackground)
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

    private var unselectedDayBackground: Color {
        colorScheme == .dark
            ? Color(uiColor: .tertiarySystemGroupedBackground)
            : Color.white.opacity(0.62)
    }
}

private struct DurationWheelPicker: View {
    @Binding var minutes: Int
    private let options = Array(stride(from: 5, through: 480, by: 5))

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Time you can use these apps per day", selection: $minutes) {
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

            Text("This is the time you can use these apps per day.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Time you can use these apps per day")
        .accessibilityValue("\(minutes) minutes")
    }
}

/// Collect button with a celebratory resolve: success haptic, bouncing
/// checkmark, and a green pulse before the collection (and the button's exit)
/// animate through.
private struct CollectTimeButton: View {
    var title = "Collect"
    var font: Font = .caption.weight(.semibold)
    var verticalPadding: CGFloat = 9
    let collect: () -> Bool

    @State private var isCelebrating = false

    var body: some View {
        Button {
            guard !isCelebrating else {
                return
            }

            AppHaptics.success()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.5)) {
                isCelebrating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    _ = collect()
                }
                isCelebrating = false
            }
        } label: {
            Label(title, systemImage: "checkmark.circle.fill")
                .font(font)
                .symbolEffect(.bounce, value: isCelebrating)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.green.opacity(isCelebrating ? 0.32 : 0.12))
                )
                .appRoundedButtonHitArea(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(red: 0.08, green: 0.58, blue: 0.32))
        .scaleEffect(isCelebrating ? 1.05 : 1)
    }
}
