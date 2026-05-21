import FamilyControls
import SwiftUI

struct BlockingSettingsView: View {
    @EnvironmentObject private var model: AppModel
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

            AppSection("Recent Requests") {
                AppCard {
                    let requests = recentRequests
                    if requests.isEmpty {
                        Text("No extra-time requests yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .appCardRow()
                    } else {
                        ForEach(Array(requests.prefix(6).enumerated()), id: \.element.id) { index, request in
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
        .navigationTitle("Blocking")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
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

    private var recentRequests: [BlockingRequestListItem] {
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
        let friend = model.blockingState.friendRequests.map { request in
            BlockingRequestListItem(
                id: "friend-\(request.id)",
                groupID: request.groupID,
                duration: request.requestedSeconds,
                status: request.status,
                createdAt: request.createdAt,
                kind: "Friend approval",
                message: request.message.isEmpty ? nil : request.message
            )
        }
        return (legacy + friend).sorted { $0.createdAt > $1.createdAt }
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

private struct PasswordProtectedAction: Identifiable {
    enum Kind {
        case edit
        case toggleEnabled
        case delete
    }

    let id = UUID()
    let kind: Kind
    let groupID: String
}

private struct PasswordPromptView: View {
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
                AppSection("Password") {
                    AppCard {
                        if let group {
                            if group.requiresPasswordSetup {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("\(group.name) needs a password before it can be changed.")
                                        .font(.subheadline)
                                    Button {
                                        onSetPassword(group)
                                    } label: {
                                        Label("Set Password", systemImage: "key")
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tint)
                                }
                                .appCardRow()
                            } else {
                                VStack(alignment: .leading, spacing: 14) {
                                    SecureField("Group password", text: $password)
                                        .textContentType(.password)

                                    Button {
                                        if model.verifyPassword(for: group, password: password) {
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
                                        SecureField("New password", text: $newPassword)
                                            .textContentType(.newPassword)
                                        Button {
                                            if model.completePasswordReset(for: group, newPassword: newPassword),
                                               let updatedGroup = model.blockingState.groups.first(where: { $0.id == group.id }) {
                                                onUnlocked(action.kind, updatedGroup)
                                            }
                                        } label: {
                                            Label("Reset Password", systemImage: "key.fill")
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundStyle(.tint)
                                    }
                                }
                                .appCardRow()
                            } else {
                                Button {
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
                        dismiss()
                    }
                }
            }
        }
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
                AppSection("Password") {
                    AppCard {
                        SecureField("Group password", text: $draft.password)
                            .textContentType(.newPassword)
                            .appCardRow()

                        AppCardDivider()

                        SecureField("Confirm password", text: $draft.confirmPassword)
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
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
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
        Button(action: action) {
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
        }
        .padding(.horizontal, 24)
        .background(Color.white.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
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
        }
        .padding(.horizontal, 24)
        .background(Color.white.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
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

            Text("Daily time available")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Daily time limit")
        .accessibilityValue("\(minutes) minutes")
    }
}
