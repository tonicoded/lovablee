import SwiftUI
import PhotosUI

struct Anniversary: Identifiable, Codable {
    let id: UUID
    let name: String
    let date: Date

    var daysAgo: Int {
        Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
    }

    init(id: UUID = UUID(), name: String, date: Date) {
        self.id = id
        self.name = name
        self.date = date
    }
}

struct ProfileView: View {
    let theme: PaletteTheme
    let isLightsOut: Bool
    let safeAreaInsets: EdgeInsets
    let extraBottomPadding: CGFloat
    let keyboardHeight: CGFloat
    let profileImageURL: URL?
    let partnerProfileImageURL: URL?
    let userName: String
    let partnerName: String?
    let pairingCode: String?
    let userIdentifier: String?
    let isSyncingProfile: Bool
    let onJoinPartner: ((String) -> Void)?
    let onLeavePartner: (() -> Void)?
    let onLogout: (() -> Void)?
    let onDeleteAccount: (() -> Void)?
    let onSettings: (() -> Void)?
    let onRefreshPairing: (() -> Void)?
    let onUploadPhoto: ((Data) async -> Void)?
    let onLoadAnniversaries: (() async throws -> (togetherSince: Date?, customAnniversaries: [Anniversary]))?
    let onSetTogetherSince: ((Date) async throws -> Void)?
    let onAddCustomAnniversary: ((String, Date) async throws -> Anniversary)?
    let onDeleteCustomAnniversary: ((UUID) async throws -> Void)?

    @State private var partnerCode: String = ""
    @FocusState private var partnerFieldFocused: Bool
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var togetherSinceDate: Date?
    @State private var customAnniversaries: [Anniversary] = []
    @State private var showAddAnniversary = false
    @State private var isLoadingAnniversaries = false

    private enum ScrollTarget: String {
        case joinCard
    }

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        avatarRow
                        pairingSection
                        partnerStatusSection
                        if partnerName != nil {
                            anniversarySection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, safeAreaInsets.top + 30)
                    .padding(.bottom,
                             safeAreaInsets.bottom +
                             extraBottomPadding +
                             (partnerName == nil ? keyboardHeight : 0))
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: partnerFieldFocused) { _, isFocused in
                    guard isFocused else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(ScrollTarget.joinCard.rawValue, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .transition(.opacity)
        .onChange(of: pairingCode ?? "") { _, _ in
            partnerCode = ""
        }
        .onChange(of: partnerName) { _, name in
            if name != nil {
                partnerFieldFocused = false
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem, let onUploadPhoto else { return }
            Task {
                do {
                    isUploadingPhoto = true
                    if let data = try await newItem.loadTransferable(type: Data.self) {
                        await onUploadPhoto(data)
                    }
                } catch {
                    // ignore load failures
                }
                await MainActor.run {
                    self.selectedPhotoItem = nil
                    self.isUploadingPhoto = false
                }
            }
        }
        .task(id: partnerName) {
            // Load anniversaries when view appears or when partner changes
            guard partnerName != nil, let onLoadAnniversaries else { return }
            isLoadingAnniversaries = true
            do {
                let result = try await onLoadAnniversaries()
                await MainActor.run {
                    togetherSinceDate = result.togetherSince
                    customAnniversaries = result.customAnniversaries
                    isLoadingAnniversaries = false
                }
            } catch {
                print("Failed to load anniversaries: \(error)")
                await MainActor.run {
                    isLoadingAnniversaries = false
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("about us")
                    .font(.system(.largeTitle, weight: .semibold))
                    .foregroundStyle(primaryTextColor)
                Text("your cozy hub for the two of you")
                    .font(.system(.subheadline))
                    .foregroundStyle(secondaryTextColor)
            }
            Spacer()
            if onSettings != nil {
                Button {
                    hapticLight()
                    onSettings?()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(primaryTextColor)
                        .padding(12)
                        .background(
                            Circle()
                                .fill(menuBackgroundColor)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var avatarRow: some View {
        HStack(spacing: 26) {
            PhotosPicker(selection: $selectedPhotoItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                AvatarCard(title: userName,
                           subtitle: "you",
                           systemImage: "heart.fill",
                           theme: theme,
                           isLightsOut: isLightsOut,
                           imageURL: profileImageURL,
                           showEditIndicator: onUploadPhoto != nil,
                           isUploading: isUploadingPhoto)
            }
            .disabled(onUploadPhoto == nil)

            Image(systemName: "heart")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(primaryTextColor.opacity(0.6))

            AvatarCard(title: partnerName ?? "add partner",
                       subtitle: partnerName == nil ? "invite" : "partner",
                       systemImage: partnerName == nil ? "plus" : "heart",
                       theme: theme,
                       isLightsOut: isLightsOut,
                       isMuted: partnerName == nil,
                       imageURL: partnerProfileImageURL)
        }
    }

    @ViewBuilder
    private var pairingSection: some View {
        if let code = pairingCode, !code.isEmpty {
            PairingCodeCard(theme: theme,
                            isLightsOut: isLightsOut,
                            code: code,
                            userIdentifier: userIdentifier)
        } else if isSyncingProfile {
            PairingInfoCard(theme: theme,
                            isLightsOut: isLightsOut,
                            title: "we're crafting your space id",
                            message: "this usually takes just a few seconds. hang tight!",
                            showRefresh: onRefreshPairing != nil,
                            onRefresh: onRefreshPairing)
        } else {
            PairingInfoCard(theme: theme,
                            isLightsOut: isLightsOut,
                            title: "authenticating…",
                            message: "make sure you finish signing in so we can generate your pairing code.",
                            showRefresh: onRefreshPairing != nil,
                            onRefresh: onRefreshPairing)
        }
    }

    @ViewBuilder
    private var partnerStatusSection: some View {
        if let partnerName, !partnerName.isEmpty {
            PartnerStatusCard(theme: theme,
                              isLightsOut: isLightsOut,
                              partnerName: partnerName,
                              onLeave: onLeavePartner)
        } else {
            JoinPartnerCard(theme: theme,
                            isLightsOut: isLightsOut,
                            partnerCode: $partnerCode,
                            isSyncing: isSyncingProfile,
                            focusBinding: $partnerFieldFocused,
                            onJoin: { code in
                                onJoinPartner?(code)
                            })
            .id(ScrollTarget.joinCard.rawValue)
        }
    }

    private var anniversarySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("anniversaries")
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(primaryTextColor)

                Spacer()

                Button(action: { showAddAnniversary = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(isLightsOut ? Color.white.opacity(0.8) : theme.buttonFill)
                }
            }

            // Together Since Card
            if let togetherSince = togetherSinceDate {
                let daysTogether = Calendar.current.dateComponents([.day], from: togetherSince, to: Date()).day ?? 0
                AnniversaryCard(
                    title: "together since",
                    daysAgo: daysTogether,
                    date: togetherSince,
                    theme: theme,
                    isLightsOut: isLightsOut,
                    isPrimary: true
                )
            } else {
                Button(action: { showAddAnniversary = true }) {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 20))
                        Text("Set your 'together since' date")
                            .font(.system(.body, weight: .medium))
                    }
                    .foregroundStyle(isLightsOut ? Color.white.opacity(0.7) : theme.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isLightsOut ? Color.white.opacity(0.1) : Color.white.opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(isLightsOut ? Color.white.opacity(0.2) : theme.buttonFill.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            // Custom Anniversaries
            ForEach(customAnniversaries) { anniversary in
                AnniversaryCard(
                    title: anniversary.name,
                    daysAgo: anniversary.daysAgo,
                    date: anniversary.date,
                    theme: theme,
                    isLightsOut: isLightsOut,
                    isPrimary: false,
                    onDelete: {
                        guard let onDeleteCustomAnniversary else {
                            customAnniversaries.removeAll { $0.id == anniversary.id }
                            return
                        }
                        Task {
                            do {
                                try await onDeleteCustomAnniversary(anniversary.id)
                                await MainActor.run {
                                    customAnniversaries.removeAll { $0.id == anniversary.id }
                                }
                            } catch {
                                print("Failed to delete anniversary: \(error)")
                            }
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showAddAnniversary) {
            AddAnniversarySheet(
                togetherSinceDate: $togetherSinceDate,
                customAnniversaries: $customAnniversaries,
                theme: theme,
                isLightsOut: isLightsOut,
                onSetTogetherSince: onSetTogetherSince,
                onAddCustomAnniversary: onAddCustomAnniversary
            )
        }
    }

    private var backgroundGradient: LinearGradient {
        if isLightsOut {
            return LinearGradient(colors: [
                Color(red: 0.15, green: 0.11, blue: 0.09),
                Color(red: 0.28, green: 0.18, blue: 0.15),
                Color(red: 0.41, green: 0.27, blue: 0.2)
            ], startPoint: .top, endPoint: .bottom)
        } else {
            return LinearGradient(colors: [
                Color(red: 0.99, green: 0.94, blue: 0.86),
                Color(red: 0.98, green: 0.89, blue: 0.78),
                Color(red: 0.96, green: 0.81, blue: 0.66)
            ], startPoint: .top, endPoint: .bottom)
        }
    }

    private var primaryTextColor: Color {
        isLightsOut ? Color.white : theme.textPrimary
    }

    private var secondaryTextColor: Color {
        isLightsOut ? Color.white.opacity(0.8) : theme.textMuted
    }

    private var menuBackgroundColor: Color {
        isLightsOut ? Color.white.opacity(0.15) : theme.buttonFill.opacity(0.25)
    }
}

private struct AvatarCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let theme: PaletteTheme
    let isLightsOut: Bool
    var isMuted: Bool = false
    var imageURL: URL?
    var showEditIndicator: Bool = false
    var isUploading: Bool = false

    var body: some View {
        let textColor = isLightsOut ? Color.white : theme.textPrimary
        let subtitleColor = isLightsOut ? Color.white.opacity(0.7) : theme.textMuted
        let iconColor = isLightsOut ? Color.white : theme.buttonFill
        let circleFill = isLightsOut ? Color.white.opacity(isMuted ? 0.12 : 0.25) :
            theme.buttonFill.opacity(isMuted ? 0.15 : 0.22)

        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Image(systemName: systemImage)
                                .resizable()
                                .scaledToFit()
                                .padding(22)
                                .foregroundStyle(iconColor)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                    )
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .padding(28)
                        .background(
                            Circle()
                                .fill(circleFill)
                        )
                }

                if showEditIndicator {
                    Circle()
                        .fill(Color.black.opacity(0.65))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: isUploading ? "hourglass" : "camera.fill")
                                .foregroundStyle(Color.white)
                                .font(.system(size: 14, weight: .bold))
                        )
                        .offset(x: 6, y: 6)
                }

                if isUploading {
                    Circle()
                        .fill(Color.black.opacity(0.45))
                        .frame(width: 96, height: 96)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Color.white)
                }
            }
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Text(subtitle.uppercased())
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(subtitleColor)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PairingCodeCard: View {
    let theme: PaletteTheme
    let isLightsOut: Bool
    let code: String
    let userIdentifier: String?
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("space id")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            HStack {
                Text(code)
                    .font(.system(.title, design: .monospaced).weight(.bold))
                    .foregroundStyle(theme.textPrimary)
                    .minimumScaleFactor(0.5)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    didCopy = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        didCopy = false
                    }
                    hapticSoft()
                } label: {
                    Label(didCopy ? "copied" : "copy",
                          systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.system(.footnote, weight: .semibold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 14)
                        .background(
                            Capsule().fill(theme.buttonFill.opacity(isLightsOut ? 0.3 : 0.25))
                        )
                }
                .buttonStyle(.plain)
            }

            if let id = userIdentifier {
                Text("user id: \(id)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
                    .textSelection(.enabled)
            }

            Text("share this id so your partner can join your space anytime.")
                .font(.system(.footnote))
                .foregroundStyle(theme.textMuted)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(isLightsOut ? 0.2 : 0.95))
        )
    }
}

private struct PairingInfoCard: View {
    let theme: PaletteTheme
    let isLightsOut: Bool
    let title: String
    let message: String
    let showRefresh: Bool
    let onRefresh: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text(message)
                .font(.system(.subheadline))
                .foregroundStyle(theme.textMuted)
            if showRefresh, let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Text("check again")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundColor(theme.buttonFill)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(isLightsOut ? 0.18 : 0.85))
        )
    }
}

private struct JoinPartnerCard: View {
    let theme: PaletteTheme
    let isLightsOut: Bool
    @Binding var partnerCode: String
    let isSyncing: Bool
    let focusBinding: FocusState<Bool>.Binding
    let onJoin: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("join your partner")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("Have their space id? enter it here and we’ll link you together.")
                .font(.system(.subheadline))
                .foregroundStyle(theme.textMuted)

            let trimmedCode = partnerCode.trimmingCharacters(in: .whitespacesAndNewlines)
            HStack(spacing: 12) {
                TextField("enter code", text: $partnerCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, weight: .semibold))
                    .focused(focusBinding)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(isLightsOut ? 0.15 : 0.9))
                    )

                Button {
                    guard !trimmedCode.isEmpty else { return }
                    hapticSoft()
                    onJoin(trimmedCode)
                } label: {
                    if isSyncing {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(Color.white)
                            .frame(width: 46, height: 46)
                    } else {
                        Text("join")
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(width: 70, height: 46)
                    }
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(theme.buttonFill.opacity(0.9))
                )
                .disabled(isSyncing || trimmedCode.isEmpty)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(isLightsOut ? 0.18 : 0.95))
        )
    }
}

private struct PartnerStatusCard: View {
    let theme: PaletteTheme
    let isLightsOut: Bool
    let partnerName: String
    let onLeave: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("partner linked")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
            Text("\(partnerName) is connected to your space.")
                .font(.system(.subheadline))
                .foregroundStyle(theme.textMuted)

            Button {
                hapticSoft()
                onLeave?()
            } label: {
                Text("leave partner")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.red.opacity(isLightsOut ? 0.6 : 0.8))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white.opacity(isLightsOut ? 0.2 : 0.95))
        )
    }
}

// MARK: - Anniversary Components

private struct AnniversaryCard: View {
    let title: String
    let daysAgo: Int
    let date: Date
    let theme: PaletteTheme
    let isLightsOut: Bool
    let isPrimary: Bool
    var onDelete: (() -> Void)? = nil

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private var circleColor: Color {
        if isPrimary {
            return isLightsOut ? Color.pink.opacity(0.3) : Color.pink.opacity(0.2)
        } else {
            return isLightsOut ? Color.white.opacity(0.2) : Color.purple.opacity(0.15)
        }
    }

    private var iconColor: Color {
        if isPrimary {
            return isLightsOut ? Color.pink.opacity(0.9) : Color.pink
        } else {
            return isLightsOut ? Color.white.opacity(0.8) : Color.purple
        }
    }

    private var accentColor: Color {
        if isPrimary {
            return isLightsOut ? Color.pink.opacity(0.9) : Color.pink
        } else {
            return isLightsOut ? Color.white.opacity(0.7) : theme.textMuted
        }
    }

    private var borderColor: Color {
        if isPrimary {
            return isLightsOut ? Color.pink.opacity(0.3) : Color.pink.opacity(0.2)
        } else {
            return isLightsOut ? Color.white.opacity(0.2) : Color.gray.opacity(0.2)
        }
    }

    private var daysLabel: String {
        if isPrimary {
            return "\(max(0, daysAgo)) days together"
        }
        if daysAgo >= 0 {
            return "\(daysAgo) days ago"
        }
        return "in \(abs(daysAgo)) days"
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 56, height: 56)

                Image(systemName: isPrimary ? "heart.fill" : "star.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(isLightsOut ? Color.white : theme.textPrimary)

                Text(daysLabel)
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(accentColor)

                Text(formattedDate)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(isLightsOut ? Color.white.opacity(0.6) : theme.textMuted.opacity(0.8))
            }

            Spacer()

            if let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(isLightsOut ? Color.white.opacity(0.6) : theme.textMuted)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isLightsOut ? Color.white.opacity(0.1) : Color.white.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(borderColor, lineWidth: 1.5)
                )
        )
    }
}

private struct AddAnniversarySheet: View {
    @Binding var togetherSinceDate: Date?
    @Binding var customAnniversaries: [Anniversary]
    let theme: PaletteTheme
    let isLightsOut: Bool
    let onSetTogetherSince: ((Date) async throws -> Void)?
    let onAddCustomAnniversary: ((String, Date) async throws -> Anniversary)?

    @Environment(\.dismiss) var dismiss
    @State private var anniversaryName: String = ""
    @State private var selectedDate: Date = Date()
    @State private var isSettingTogetherSince: Bool = true
    @State private var isSaving = false

    var body: some View {
        NavigationView {
            ZStack {
                (isLightsOut ? Color.black : Color(red: 0.996, green: 0.909, blue: 0.749))
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 24) {
                    // Type Picker
                    Picker("Type", selection: $isSettingTogetherSince) {
                        Text("Together Since").tag(true)
                        Text("Custom Anniversary").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)

                    // Name Field (only for custom)
                    if !isSettingTogetherSince {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(isLightsOut ? Color.white.opacity(0.8) : theme.textMuted)

                            TextField("First date, first kiss, etc.", text: $anniversaryName)
                                .padding(16)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isLightsOut ? Color.white.opacity(0.1) : Color.white)
                                )
                                .foregroundStyle(isLightsOut ? Color.white : theme.textPrimary)
                        }
                        .padding(.horizontal, 24)
                    }

                    // Date Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Date")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(isLightsOut ? Color.white.opacity(0.8) : theme.textMuted)

                        DatePicker("", selection: $selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isLightsOut ? Color.white.opacity(0.1) : Color.white)
                            )
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Save Button
                    Button(action: saveAnniversary) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        } else {
                            Text("Save")
                                .font(.system(.headline, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isLightsOut ? Color.pink.opacity(0.8) : Color.pink)
                    )
                    .disabled(isSaving || (isSettingTogetherSince == false && anniversaryName.isEmpty))
                    .opacity((isSaving || (isSettingTogetherSince == false && anniversaryName.isEmpty)) ? 0.5 : 1)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Add Anniversary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(isLightsOut ? Color.white : theme.buttonFill)
                }
            }
        }
    }

    private func saveAnniversary() {
        isSaving = true

        if isSettingTogetherSince {
            // Setting together since date
            if let onSetTogetherSince {
                Task {
                    do {
                        try await onSetTogetherSince(selectedDate)
                        await MainActor.run {
                            togetherSinceDate = selectedDate
                            isSaving = false
                            dismiss()
                        }
                    } catch {
                        print("Failed to set together since date: \(error)")
                        await MainActor.run {
                            isSaving = false
                        }
                    }
                }
            } else {
                togetherSinceDate = selectedDate
                isSaving = false
                dismiss()
            }
        } else if !anniversaryName.isEmpty {
            // Adding custom anniversary
            if let onAddCustomAnniversary {
                Task {
                    do {
                        let newAnniversary = try await onAddCustomAnniversary(anniversaryName, selectedDate)
                        await MainActor.run {
                            customAnniversaries.append(newAnniversary)
                            isSaving = false
                            dismiss()
                        }
                    } catch {
                        print("Failed to add custom anniversary: \(error)")
                        await MainActor.run {
                            isSaving = false
                        }
                    }
                }
            } else {
                let newAnniversary = Anniversary(name: anniversaryName, date: selectedDate)
                customAnniversaries.append(newAnniversary)
                isSaving = false
                dismiss()
            }
        } else {
            isSaving = false
        }
    }
}
