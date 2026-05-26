import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isShowingShareSheet = false
    @State private var isEditingDisplayName = false
    @State private var draftDisplayName = ""
    @State private var selectedProfilePhotoItem: PhotosPickerItem?
    @State private var profilePhotoCropItem: ProfilePhotoCropItem?
    @State private var selectedCollectionPhoto: AcceptedRequestPhotoItem?

    private let photoBoardColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                profileHeader
                appearanceSection

                AppSection("Sharing") {
                    AppCard {
                        Button {
                            AppHaptics.buttonTap()
                            isShowingShareSheet = true
                        } label: {
                            Label("Invite Friends", systemImage: "square.and.arrow.up")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }

                AppSection("Readiness") {
                    AppCard {
                        LabeledContent("Screen Time", value: model.screenTimeAuthorization)
                            .appCardRow()
                        AppCardDivider()
                        LabeledContent("Report", value: model.screenTimeReportStatus)
                            .appCardRow()
                        AppCardDivider()
                        if !model.hasScreenTimeAuthorization {
                            Button {
                                AppHaptics.buttonTap()
                                Task {
                                    await model.requestScreenTimeAuthorization()
                                }
                            } label: {
                                Label("Request Screen Time Access", systemImage: "hourglass.badge.plus")
                                    .appCardRow()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            AppCardDivider()
                        }
                        Button {
                            AppHaptics.buttonTap()
                            Task {
                                await model.refreshAndPublish()
                            }
                        } label: {
                            Label("Refresh Screen Time", systemImage: "arrow.clockwise")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        AppCardDivider()
                        LabeledContent("iCloud", value: model.cloudAvailability.label)
                            .appCardRow()
                        AppCardDivider()
                        LabeledContent("Widget cache", value: "\(model.friendSummaries.count) friends")
                            .appCardRow()
                    }
                }

                #if DEBUG && targetEnvironment(simulator)
                AppSection("Simulator Demo") {
                    AppCard {
                        Button {
                            AppHaptics.buttonTap()
                            model.seedDemoScreenTime()
                        } label: {
                            Label("Add Demo Screen Time", systemImage: "iphone.gen3")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)

                        AppCardDivider()

                        Button {
                            AppHaptics.buttonTap()
                            model.seedDemoFriends()
                        } label: {
                            Label("Add Demo Friends", systemImage: "person.2.badge.plus")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)

                        AppCardDivider()

                        Button(role: .destructive) {
                            AppHaptics.buttonTap()
                            model.clearDemoFriends()
                        } label: {
                            Label("Clear Demo Friends", systemImage: "trash")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)

                        AppCardDivider()

                        Button {
                            AppHaptics.buttonTap()
                            model.resetOnboarding()
                        } label: {
                            Label("Replay Onboarding", systemImage: "arrow.counterclockwise")
                                .appCardRow()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }
                #endif

                photoCollectionSection
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $isShowingShareSheet) {
                CloudShareSheet(store: model.snapshotStore, profile: model.profile)
            }
            .sheet(isPresented: $isEditingDisplayName) {
                EditDisplayNameSheet(displayName: $draftDisplayName) { newDisplayName in
                    model.updateProfile(displayName: newDisplayName)
                    isEditingDisplayName = false
                }
                .presentationDetents([.height(310)])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $profilePhotoCropItem) { item in
                ProfilePhotoCropView(image: item.image) { croppedImageData in
                    model.updateProfile(avatarImageData: croppedImageData)
                    profilePhotoCropItem = nil
                }
            }
            .sheet(item: $selectedCollectionPhoto) { item in
                AcceptedRequestPhotoDetailView(item: item)
                    .presentationDetents([.large])
            }
            .onChange(of: selectedProfilePhotoItem) { _, item in
                loadSelectedProfilePhoto(item)
            }
        }
    }

    private var profileHeader: some View {
        let profile = model.profile

        return VStack(spacing: 13) {
            PhotosPicker(selection: $selectedProfilePhotoItem, matching: .images, photoLibrary: .shared()) {
                ProfileAvatar(
                    imageData: profile.avatarImageData,
                    colorHex: profile.avatarColorHex,
                    initials: profile.displayName.initials,
                    size: 96
                )
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.accentColor, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2)
                        }
                        .offset(x: 3, y: 3)
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                AppHaptics.buttonTap()
            })
            .accessibilityLabel("Change profile icon")

            Button {
                AppHaptics.buttonTap()
                draftDisplayName = profile.displayName
                isEditingDisplayName = true
            } label: {
                HStack(spacing: 7) {
                    Text(profile.displayName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Image(systemName: "pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit display name")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var photoCollectionSection: some View {
        AppSection("Photo Collection") {
            AppCard {
                if acceptedPhotoItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No accepted photos yet", systemImage: "photo.on.rectangle.angled")
                            .font(.subheadline.weight(.semibold))
                        Text("Photos from friend requests appear here after you approve them.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .appCardRow()
                } else {
                    LazyVGrid(columns: photoBoardColumns, spacing: 10) {
                        ForEach(acceptedPhotoItems) { item in
                            Button {
                                AppHaptics.buttonTap()
                                selectedCollectionPhoto = item
                            } label: {
                                AcceptedRequestPhotoTile(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .appCardRow(verticalPadding: 12)
                }
            }
        }
    }

    private var appearanceSection: some View {
        AppSection("Appearance") {
            AppCard {
                Picker(
                    "Appearance",
                    selection: Binding(
                        get: { model.appearanceMode },
                        set: { mode in
                            AppHaptics.selectionChanged()
                            model.setAppearanceMode(mode)
                        }
                    )
                ) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.systemImage)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .appCardRow(verticalPadding: 12)
            }
        }
    }

    private var acceptedPhotoItems: [AcceptedRequestPhotoItem] {
        model.blockingState.friendRequests
            .compactMap { request in
                guard request.isReceived(byAny: currentFriendIdentityIDs),
                      request.approvedByFriendID.map(currentFriendIdentityIDs.contains) == true,
                      let photoData = model.friendRequestPhotoData(for: request) else {
                    return nil
                }

                return AcceptedRequestPhotoItem(
                    id: request.id,
                    photoData: photoData,
                    senderName: senderName(for: request),
                    groupName: groupName(for: request.groupID),
                    requestedSeconds: request.requestedSeconds,
                    approvedAt: request.resolvedAt ?? request.createdAt
                )
            }
            .sorted { $0.approvedAt > $1.approvedAt }
    }

    private var currentFriendIdentityIDs: Set<String> {
        [model.profile.id, "profile-\(model.profile.id)"]
    }

    private func senderName(for request: BlockFriendRequest) -> String {
        if let displayName = request.requesterDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }

        if let requesterID = request.requesterID,
           let friend = model.friendSummaries.first(where: { $0.id == requesterID }) {
            return friend.displayName
        }

        return "Friend"
    }

    private func groupName(for groupID: String) -> String {
        model.blockingState.groups.first { $0.id == groupID }?.name ?? "Restricted app"
    }

    private func loadSelectedProfilePhoto(_ item: PhotosPickerItem?) {
        guard let item else {
            return
        }

        Task {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                await MainActor.run {
                    selectedProfilePhotoItem = nil
                }
                return
            }

            #if canImport(UIKit)
            guard let image = UIImage(data: data) else {
                await MainActor.run {
                    selectedProfilePhotoItem = nil
                }
                return
            }

            await MainActor.run {
                profilePhotoCropItem = ProfilePhotoCropItem(image: image)
                selectedProfilePhotoItem = nil
            }
            #else
            await MainActor.run {
                selectedProfilePhotoItem = nil
            }
            #endif
        }
    }
}

private struct AcceptedRequestPhotoItem: Identifiable {
    let id: String
    let photoData: Data
    let senderName: String
    let groupName: String
    let requestedSeconds: TimeInterval
    let approvedAt: Date
}

private struct AcceptedRequestPhotoTile: View {
    let item: AcceptedRequestPhotoItem

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                AcceptedRequestPhotoImage(photoData: item.photoData)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.58)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(item.senderName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
        .accessibilityLabel("\(item.senderName) accepted request photo")
    }
}

private struct AcceptedRequestPhotoDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: AcceptedRequestPhotoItem

    var body: some View {
        NavigationStack {
            AppScreenScroll(backgroundStyle: .white) {
                AcceptedRequestPhotoImage(photoData: item.photoData)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.78, contentMode: .fill)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 22, x: 0, y: 12)

                AppCard {
                    LabeledContent("From", value: item.senderName)
                        .appCardRow()
                    AppCardDivider()
                    LabeledContent("Request", value: item.groupName)
                        .appCardRow()
                    AppCardDivider()
                    LabeledContent("Time", value: UsageFormatting.duration(item.requestedSeconds))
                        .appCardRow()
                    AppCardDivider()
                    LabeledContent("Accepted", value: item.approvedAt.formatted(date: .abbreviated, time: .shortened))
                        .appCardRow()
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
        }
    }
}

private struct AcceptedRequestPhotoImage: View {
    let photoData: Data

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let image = UIImage(data: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
        .clipped()
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.18, blue: 0.28),
                    Color(red: 0.24, green: 0.36, blue: 0.52)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "photo")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
    }
}

private struct EditDisplayNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var displayName: String
    let onSave: (String) -> Void
    @FocusState private var isNameFocused: Bool

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            nameInput
            saveButton
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("Edit Name")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .onAppear {
            isNameFocused = true
        }
    }

    private var nameInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            nameField
        }
    }

    private var nameField: some View {
        HStack(spacing: 10) {
            TextField("Display name", text: $displayName)
                .font(.title3.weight(.semibold))
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.done)
                .focused($isNameFocused)
                .onSubmit(save)

            clearButton
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(nameFieldBackground)
        .overlay(nameFieldBorder)
    }

    @ViewBuilder
    private var clearButton: some View {
        if !displayName.isEmpty {
            Button {
                AppHaptics.buttonTap()
                displayName = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear name")
        }
    }

    private var nameFieldBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var nameFieldBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(isNameFocused ? 0.22 : 0.08), lineWidth: 1)
    }

    private var saveButton: some View {
        Button {
            AppHaptics.buttonTap()
            save()
        } label: {
            Text("Save")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(saveButtonBackground)
                .foregroundStyle(saveButtonTextColor)
        }
        .buttonStyle(.plain)
        .disabled(trimmedDisplayName.isEmpty)
    }

    private var saveButtonBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(trimmedDisplayName.isEmpty ? Color.gray.opacity(0.24) : Color.accentColor)
    }

    private var saveButtonTextColor: Color {
        trimmedDisplayName.isEmpty ? .secondary : .white
    }

    private func save() {
        let value = trimmedDisplayName
        guard !value.isEmpty else {
            return
        }

        onSave(value)
        dismiss()
    }
}

#if canImport(UIKit)
private struct ProfilePhotoCropItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ProfilePhotoCropView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onSave: (Data) -> Void

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var activeCropSide: CGFloat = 360

    private let maxZoom: CGFloat = 4
    private let outputSide: CGFloat = 512

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer(minLength: 14)

                GeometryReader { proxy in
                    let cropSide = min(max(proxy.size.width - 48, 220), 360)
                    cropper(cropSide: cropSide)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onAppear {
                            activeCropSide = cropSide
                        }
                        .onChange(of: cropSide) { _, newValue in
                            activeCropSide = newValue
                            offset = clampedOffset(offset, cropSide: newValue, zoom: zoom)
                            lastOffset = offset
                        }
                }
                .frame(height: 390)

                Button {
                    AppHaptics.buttonTap()
                    if let data = croppedImageData(cropSide: activeCropSide) {
                        onSave(data)
                        dismiss()
                    }
                } label: {
                    Text("Use Photo")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .navigationTitle("Crop Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func cropper(cropSide: CGFloat) -> some View {
        let drag = DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, cropSide: cropSide, zoom: zoom)
            }
            .onEnded { _ in
                offset = clampedOffset(offset, cropSide: cropSide, zoom: zoom)
                lastOffset = offset
            }

        let magnification = MagnificationGesture()
            .onChanged { value in
                zoom = min(max(lastZoom * value, 1), maxZoom)
                offset = clampedOffset(offset, cropSide: cropSide, zoom: zoom)
            }
            .onEnded { _ in
                zoom = min(max(zoom, 1), maxZoom)
                offset = clampedOffset(offset, cropSide: cropSide, zoom: zoom)
                lastZoom = zoom
                lastOffset = offset
            }

        return ZStack {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cropSide, height: cropSide)
                    .scaleEffect(zoom)
                    .offset(offset)
            }
            .frame(width: cropSide, height: cropSide)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
        }
        .contentShape(Circle())
        .gesture(drag.simultaneously(with: magnification))
    }

    private func croppedImageData(cropSide: CGFloat) -> Data? {
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: outputSide, height: outputSide),
            format: rendererFormat
        )
        let sourceImage = image
        let outputImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: outputSide, height: outputSide))

            let displaySize = displayedImageSize(cropSide: cropSide, zoom: zoom)
            let outputScale = outputSide / cropSide
            let outputDisplaySize = CGSize(
                width: displaySize.width * outputScale,
                height: displaySize.height * outputScale
            )
            let drawRect = CGRect(
                x: outputSide / 2 - outputDisplaySize.width / 2 + offset.width * outputScale,
                y: outputSide / 2 - outputDisplaySize.height / 2 + offset.height * outputScale,
                width: outputDisplaySize.width,
                height: outputDisplaySize.height
            )
            sourceImage.draw(in: drawRect)
        }

        return outputImage.jpegData(compressionQuality: 0.86)
    }

    private func clampedOffset(_ proposed: CGSize, cropSide: CGFloat, zoom: CGFloat) -> CGSize {
        let displaySize = displayedImageSize(cropSide: cropSide, zoom: zoom)
        let maxX = max((displaySize.width - cropSide) / 2, 0)
        let maxY = max((displaySize.height - cropSide) / 2, 0)

        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func displayedImageSize(cropSide: CGFloat, zoom: CGFloat) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: cropSide, height: cropSide)
        }

        let baseScale = max(cropSide / image.size.width, cropSide / image.size.height)
        return CGSize(
            width: image.size.width * baseScale * zoom,
            height: image.size.height * baseScale * zoom
        )
    }
}
#endif
