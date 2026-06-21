import FamilyControls
import SwiftUI

struct GroupsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingCreateGroup = false

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                AppSection("Groups") {
                    if model.myGroups.isEmpty {
                        AppCard {
                            ContentUnavailableView(
                                "No Groups Yet",
                                systemImage: "person.3",
                                description: Text("Create a group to share a daily limit with friends.")
                            )
                            .appCardRow(verticalPadding: 16)
                        }
                    } else {
                        AppCard {
                            ForEach(Array(model.myGroups.enumerated()), id: \.element.id) { index, group in
                                NavigationLink {
                                    GroupDetailView(groupID: group.id)
                                } label: {
                                    GroupSummaryRow(group: group)
                                        .appCardRow(verticalPadding: 10)
                                }
                                .buttonStyle(.plain)

                                if index < model.myGroups.count - 1 {
                                    AppCardDivider()
                                }
                            }
                        }
                    }
                }
            }
            .refreshable {
                AppHaptics.selectionChanged()
                await model.loadMyGroups()
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        AppHaptics.buttonTap()
                        isShowingCreateGroup = true
                    } label: {
                        Label("Create Group", systemImage: "plus")
                    }
                    .accessibilityLabel("Create Group")
                }
            }
            .sheet(isPresented: $isShowingCreateGroup) {
                CreateGroupSheet()
            }
            .task {
                await model.loadMyGroups()
            }
        }
    }
}

struct CreateGroupSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var mode: GroupMode = .perMember
    @State private var newAppName = ""
    @State private var appNames: [String] = []
    @State private var minutes = 30
    @State private var approvalsRequired = 1
    @State private var isCreating = false
    @State private var created: CreatedGroup?

    private var limitSeconds: Int {
        minutes * 60
    }

    private var limitMinuteRange: ClosedRange<Int> {
        Int(BlockingTimeLimitRange.minimumSeconds / 60)...Int(BlockingTimeLimitRange.maximumSeconds / 60)
    }

    private var limitMinuteStep: Int {
        Int(BlockingTimeLimitRange.stepSeconds / 60)
    }

    private var validationErrors: [String] {
        GroupConfigValidation.errors(
            mode: mode,
            appNames: appNames,
            limitSeconds: limitSeconds,
            approvalsRequired: approvalsRequired
        )
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && validationErrors.isEmpty
            && !isCreating
    }

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    shareSection(created)
                } else {
                    detailsSection
                    appsSection
                    limitSection
                    createSection
                }
            }
            .navigationTitle(created == nil ? "Create Group" : "Group Created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(created == nil ? "Cancel" : "Done") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
            }
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Group name", text: $name)
                .textInputAutocapitalization(.words)

            Picker("Mode", selection: $mode) {
                Text("Per-member daily limit").tag(GroupMode.perMember)
                Text("Shared pool").tag(GroupMode.pool)
            }
        } header: {
            Text("Details")
        }
    }

    private var appsSection: some View {
        Section {
            HStack(spacing: 10) {
                TextField("App name", text: $newAppName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(addAppName)

                Button(action: addAppName) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .disabled(newAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add App")
            }

            ForEach(appNames, id: \.self) { appName in
                Text(appName)
            }
            .onDelete { offsets in
                appNames.remove(atOffsets: offsets)
            }
        } header: {
            Text("Apps")
        } footer: {
            Text("Add the app names this group will track.")
        }
    }

    private var limitSection: some View {
        Section {
            Stepper(value: $minutes, in: limitMinuteRange, step: limitMinuteStep) {
                Text("\(minutes) \(limitLabel)")
            }

            Stepper(value: $approvalsRequired, in: 1...10) {
                Text("\(approvalsRequired) approval\(approvalsRequired == 1 ? "" : "s") required")
            }
        } header: {
            Text("Limit")
        }
    }

    private var createSection: some View {
        Section {
            if !validationErrors.isEmpty {
                ForEach(validationErrors, id: \.self) { error in
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Button {
                Task {
                    await createGroup()
                }
            } label: {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView()
                            .tint(.white)
                    }

                    Text(isCreating ? "Creating" : "Create")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canCreate)
        }
    }

    private func shareSection(_ created: CreatedGroup) -> some View {
        let shareText = shareText(for: created)

        return Section {
            VStack(alignment: .leading, spacing: 14) {
                Text(GroupInviteCode.formatted(created.code))
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)

                ShareLink(item: shareText) {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Invite")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Done") {
                    dismiss()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Invite code")
        } footer: {
            Text("Share this link with friends you want to add to the group.")
        }
    }

    private var limitLabel: String {
        switch mode {
        case .perMember:
            return "minutes per person / day"
        case .pool:
            return "shared minutes / day"
        }
    }

    private func addAppName() {
        let trimmed = newAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        if !appNames.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            appNames.append(trimmed)
        }
        newAppName = ""
    }

    private func createGroup() async {
        guard canCreate else {
            return
        }

        isCreating = true
        defer { isCreating = false }

        let createdGroup = await model.createGroup(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            mode: mode,
            appNames: appNames,
            limitSeconds: limitSeconds,
            approvalsRequired: approvalsRequired
        )
        if let createdGroup {
            AppHaptics.success()
            created = createdGroup
        }
    }

    private func shareText(for created: CreatedGroup) -> String {
        "Join my Deny group: \(AppConfiguration.groupInviteWebLink(created.code).absoluteString)"
    }
}

struct GroupDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let groupID: String

    @State private var detail: GroupDetail?
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingLeave = false
    @State private var isShowingBlockSetup = false
    @State private var isShowingAskGroupTime = false
    @State private var didSendGroupTimeRequest = false
    @State private var poolState: GroupPoolState?
    @State private var isLoadingPoolState = false
    @State private var memberToRemove: GroupMemberInfo?

    var body: some View {
        AppScreenScroll {
            if isLoading && detail == nil {
                AppCard {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Loading group...")
                            .foregroundStyle(.secondary)
                    }
                    .appCardRow()
                }
            } else if let detail {
                summarySection(detail)
                blockSetupSection(detail)
                membersSection(detail)
                actionsSection(detail)
            } else {
                AppCard {
                    ContentUnavailableView(
                        "Group Unavailable",
                        systemImage: "person.3.sequence",
                        description: Text("This group could not be loaded.")
                    )
                    .appCardRow(verticalPadding: 16)
                }
            }
        }
        .navigationTitle(detail?.group.name ?? "Group")
        .refreshable {
            AppHaptics.selectionChanged()
            await reload()
        }
        .task {
            await reload()
        }
        .alert("Delete group?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    await deleteGroup()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the group for every member.")
        }
        .alert("Leave group?", isPresented: $isConfirmingLeave) {
            Button("Leave", role: .destructive) {
                Task {
                    await leaveGroup()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will no longer be part of this group.")
        }
        .alert("Remove member?", isPresented: Binding(
            get: { memberToRemove != nil },
            set: { if !$0 { memberToRemove = nil } }
        )) {
            Button("Remove", role: .destructive) {
                guard let memberToRemove else {
                    return
                }
                Task {
                    await removeMember(memberToRemove)
                }
            }
            Button("Cancel", role: .cancel) {
                memberToRemove = nil
            }
        } message: {
            Text(memberToRemove.map { "Remove \($0.displayName) from this group?" } ?? "Remove this member from the group?")
        }
        .alert("Request sent", isPresented: $didSendGroupTimeRequest) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your group can approve it from the requests feed.")
        }
        .sheet(isPresented: $isShowingBlockSetup) {
            if let detail {
                GroupBlockSetupSheet(
                    groupID: groupID,
                    appNames: detail.config.appNames,
                    limitSeconds: blockSetupLimitSeconds(for: detail),
                    mode: detail.group.mode,
                    onDone: {
                        isShowingBlockSetup = false
                        Task {
                            await reload()
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingAskGroupTime) {
            AskGroupTimeSheet(
                socialGroupID: groupID,
                onDone: {
                    isShowingAskGroupTime = false
                    didSendGroupTimeRequest = true
                    AppHaptics.success()
                    Task {
                        await reload()
                    }
                }
            )
        }
    }

    private func summarySection(_ detail: GroupDetail) -> some View {
        AppSection("Configuration") {
            AppCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(detail.group.name)
                            .font(.headline)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        GroupModeBadge(mode: detail.group.mode)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        GroupInfoLine(title: "Apps", value: detail.config.appNames.joined(separator: ", "))
                        GroupInfoLine(title: "Limit", value: limitText(config: detail.config, mode: detail.group.mode))
                        GroupInfoLine(title: "Approvals", value: "\(detail.config.approvalsRequired)")
                    }
                }
                .appCardRow()
            }
        }
    }

    private func membersSection(_ detail: GroupDetail) -> some View {
        let summary = GroupMembership.configuredSummary(detail.members)

        return AppSection("Members") {
            AppCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(summary.configured) of \(summary.total) configured")
                        .font(.subheadline.weight(.semibold))

                    if !summary.pending.isEmpty {
                        Text("Pending: \(summary.pending.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .appCardRow(verticalPadding: 12)

                AppCardDivider()

                ForEach(Array(detail.members.enumerated()), id: \.element.id) { index, member in
                    GroupMemberRow(
                        member: member,
                        canRemove: detail.group.role == .owner && member.role != .owner,
                        onRemove: {
                            AppHaptics.buttonTap()
                            memberToRemove = member
                        }
                    )
                    .appCardRow(verticalPadding: 10)

                    if index < detail.members.count - 1 {
                        AppCardDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func blockSetupSection(_ detail: GroupDetail) -> some View {
        if detail.group.mode == .perMember {
            let limitSeconds = detail.config.perMemberLimitSeconds ?? 0
            let isConfigured = viewerIsConfigured(in: detail)

            AppSection("Your Block") {
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if isConfigured {
                            Text("✓ You're set up — \(detail.config.appNames.count) apps · \(limitSeconds / 60) min/day")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Button {
                                AppHaptics.buttonTap()
                                isShowingBlockSetup = true
                            } label: {
                                Text("Update apps")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)

                            Button {
                                AppHaptics.buttonTap()
                                isShowingAskGroupTime = true
                            } label: {
                                Text("Ask group for more time")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        } else {
                            Text("Choose the apps on this device that match your group's agreed block list.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button {
                                AppHaptics.buttonTap()
                                isShowingBlockSetup = true
                            } label: {
                                Text("Set up your block")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                    .appCardRow()
                }
            }
        } else {
            let poolSeconds = detail.config.poolSeconds ?? 0
            let isConfigured = viewerIsConfigured(in: detail)

            AppSection("Your Block") {
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if isConfigured {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Shared pool: \(minutesText(poolSeconds))/day")
                                    .font(.subheadline.weight(.semibold))

                                if let poolState {
                                    if poolState.exhausted {
                                        Text("Pool used up — blocked until reset")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.red)
                                    } else {
                                        Text("\(minutesText(poolState.remainingSeconds)) left today")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Shared daily pool: \(minutesText(poolSeconds))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }

                                if isLoadingPoolState {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Updating pool status...")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }

                            Text("Your device keeps a local backstop for the selected apps so the shared budget still has a limit when you're offline.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Button {
                                AppHaptics.buttonTap()
                                isShowingBlockSetup = true
                            } label: {
                                Text("Update apps")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        } else {
                            Text("This group shares one daily budget across everyone. Choose the matching apps on this device; your device will keep a local backstop limit for the shared pool.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button {
                                AppHaptics.buttonTap()
                                isShowingBlockSetup = true
                            } label: {
                                Text("Set up your block")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                    .appCardRow()
                }
            }
        }
    }

    private func actionsSection(_ detail: GroupDetail) -> some View {
        AppSection("Actions") {
            AppCard {
                VStack(spacing: 12) {
                    if detail.group.role == .owner {
                        Button(role: .destructive) {
                            AppHaptics.buttonTap()
                            isConfirmingDelete = true
                        } label: {
                            Text("Delete group")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isMutating)
                    } else {
                        Button(role: .destructive) {
                            AppHaptics.buttonTap()
                            isConfirmingLeave = true
                        } label: {
                            Text("Leave group")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(isMutating)
                    }
                }
                .appCardRow()
            }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        if let loadedDetail = await model.loadGroupDetail(groupID: groupID) {
            detail = loadedDetail
            await reloadPoolState(for: loadedDetail)
        }
    }

    private func reloadPoolState(for detail: GroupDetail?) async {
        guard let detail, detail.group.mode == .pool else {
            poolState = nil
            return
        }

        isLoadingPoolState = true
        defer { isLoadingPoolState = false }
        poolState = try? await model.snapshotStore.getGroupPoolState(groupID: groupID)
    }

    private func removeMember(_ member: GroupMemberInfo) async {
        isMutating = true
        defer {
            isMutating = false
            memberToRemove = nil
        }

        await model.removeGroupMember(groupID: groupID, userID: member.userID)
        await reload()
    }

    private func leaveGroup() async {
        isMutating = true
        defer { isMutating = false }

        await model.leaveGroup(groupID)
        dismiss()
    }

    private func deleteGroup() async {
        isMutating = true
        defer { isMutating = false }

        await model.deleteGroup(groupID)
        dismiss()
    }

    private func limitText(config: GroupBlockConfig, mode: GroupMode) -> String {
        let seconds: Int?
        switch mode {
        case .perMember:
            seconds = config.perMemberLimitSeconds
        case .pool:
            seconds = config.poolSeconds
        }

        guard let seconds else {
            return "Not set"
        }

        return "\(max(1, seconds / 60)) min / day"
    }

    private func blockSetupLimitSeconds(for detail: GroupDetail) -> Int {
        switch detail.group.mode {
        case .perMember:
            return detail.config.perMemberLimitSeconds ?? 0
        case .pool:
            return detail.config.poolSeconds ?? 0
        }
    }

    private func minutesText(_ seconds: Int) -> String {
        "\(max(0, seconds / 60)) min"
    }

    private func viewerIsConfigured(in detail: GroupDetail) -> Bool {
        if let currentMember = detail.members.first(where: { $0.userID.caseInsensitiveCompare(model.profile.id) == .orderedSame }) {
            return currentMember.configured
        }

        return detail.group.configuredAt != nil
    }
}

struct GroupShareInviteView: View {
    let invite: PeekedGroupInvite
    let isAccepting: Bool
    let onAccept: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 18)

                Image(systemName: "person.3.fill")
                    .font(.system(size: 70, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 116, height: 116)
                    .background(Color.blue.opacity(0.12), in: Circle())

                VStack(spacing: 8) {
                    Text(invite.groupName)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("\(invite.ownerDisplayName) invited you to join a \(modeText(invite.mode)) group.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 18)

                Button(action: onAccept) {
                    HStack(spacing: 10) {
                        if isAccepting {
                            ProgressView()
                                .tint(.white)
                        }

                        Text(isAccepting ? "Joining" : "Join")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isAccepting)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Group Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not Now", action: onCancel)
                        .disabled(isAccepting)
                }
            }
        }
    }

    private func modeText(_ mode: GroupMode) -> String {
        switch mode {
        case .perMember:
            return "daily limit"
        case .pool:
            return "shared pool"
        }
    }
}

private struct GroupSummaryRow: View {
    let group: FriendGroupSummary

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.blue)
                .frame(width: 34, height: 34)
                .background(Color.blue.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(group.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    GroupModeBadge(mode: group.mode)
                }

                HStack(spacing: 8) {
                    Label("\(group.memberCount)", systemImage: "person.2")
                    Text(statusText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        group.configuredAt == nil ? "Set up pending" : "Configured"
    }
}

private struct GroupMemberRow: View {
    let member: GroupMemberInfo
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: member.configured ? "checkmark.circle.fill" : "clock")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(member.configured ? Color.green : Color.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if member.role == .owner {
                        Text("Owner")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(member.configured ? "Configured" : "Set up pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if canRemove {
                Button(role: .destructive, action: onRemove) {
                    Text("Remove")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

private struct GroupModeBadge: View {
    let mode: GroupMode

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    private var title: String {
        switch mode {
        case .perMember:
            return "Daily limit"
        case .pool:
            return "Shared pool"
        }
    }

    private var color: Color {
        switch mode {
        case .perMember:
            return .blue
        case .pool:
            return .purple
        }
    }
}

private struct GroupInfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            Text(value.isEmpty ? "None" : value)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AskGroupTimeSheet: View {
    let socialGroupID: String
    var onDone: () -> Void

    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var minutes = 15
    @State private var note = ""
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                AppSection("Request") {
                    AppCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Ask your group for more time")
                                .font(.title2.weight(.bold))

                            Stepper("\(minutes) min", value: $minutes, in: 5...120, step: 5)

                            TextField("Why? (optional)", text: $note)
                                .textInputAutocapitalization(.sentences)

                            Button {
                                AppHaptics.buttonTap()
                                Task {
                                    await sendRequest()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if isSending {
                                        ProgressView()
                                            .tint(.white)
                                    }

                                    Text(isSending ? "Sending" : "Send request")
                                }
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(isSending)
                        }
                        .appCardRow()
                    }
                }
            }
            .navigationTitle("More Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSending)
                }
            }
        }
    }

    private func sendRequest() async {
        guard !isSending else {
            return
        }

        isSending = true
        if await model.requestGroupTime(
            socialGroupID: socialGroupID,
            seconds: TimeInterval(minutes * 60),
            message: note,
            photoJPEGData: nil
        ) {
            onDone()
        }
        isSending = false
    }
}

private struct GroupBlockSetupSheet: View {
    let groupID: String
    let appNames: [String]
    let limitSeconds: Int
    var mode: GroupMode = .perMember
    var onDone: () -> Void

    @EnvironmentObject private var model: AppModel
    @State private var selection = FamilyActivitySelection()
    @State private var isShowingPicker = false
    @State private var isStarting = false
    @State private var hasLoadedExistingSelection = false

    private var selectedCount: Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    private var canStart: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return !isStarting // FamilyActivityPicker has no apps to select in the simulator
        #else
        return selectedCount >= 1 && !isStarting
        #endif
    }

    var body: some View {
        NavigationStack {
            AppScreenScroll {
                AppSection("Block Setup") {
                    AppCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Set up your block")
                                .font(.title2.weight(.bold))

                            Text("Your group restricts: \(appNames.joined(separator: ", "))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if mode == .pool {
                                Text("This is a shared daily budget for the whole group. Your device also keeps a local backstop limit for the apps you choose.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                AppHaptics.buttonTap()
                                isShowingPicker = true
                            } label: {
                                Text("Choose apps to block")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)

                            Text("\(selectedCount) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Button {
                                AppHaptics.buttonTap()
                                Task {
                                    await startBlocking()
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if isStarting {
                                        ProgressView()
                                            .tint(.white)
                                    }

                                    Text(isStarting ? "Starting" : "Start blocking")
                                }
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(!canStart)
                        }
                        .appCardRow()
                    }
                }
            }
            .navigationTitle("Set up your block")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $isShowingPicker) {
            NavigationStack {
                FamilyActivityPicker(selection: $selection)
                    .navigationTitle("Blocked Apps")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingPicker = false }
                        }
                    }
            }
        }
        .onAppear(perform: loadExistingSelection)
    }

    private func loadExistingSelection() {
        guard !hasLoadedExistingSelection else {
            return
        }

        hasLoadedExistingSelection = true
        let blockGroupID = "group.\(groupID)"
        guard let group = model.blockingState.groups.first(where: { $0.id == blockGroupID }),
              let existingSelection = try? BlockingSelectionCodec.decode(group.selectionData) else {
            return
        }

        selection = existingSelection
    }

    private func startBlocking() async {
        guard canStart else {
            return
        }

        isStarting = true
        let didStart: Bool
        switch mode {
        case .perMember:
            didStart = await model.adoptGroupBlock(
                groupID: groupID,
                limitSeconds: limitSeconds,
                selection: selection
            )
        case .pool:
            didStart = await model.adoptGroupPoolBlock(
                groupID: groupID,
                poolSeconds: limitSeconds,
                selection: selection
            )
        }
        if didStart {
            onDone()
        }
        isStarting = false
    }
}
