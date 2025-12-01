import SwiftUI
import UIKit
import Combine
import Lottie

struct DashboardView: View {
    let name: String
    var partnerName: String?
    var userIdentifier: String?
    var pairingCode: String?
    var profileImageURL: URL?
    var partnerProfileImageURL: URL?
    var onLogout: (() -> Void)?
    var onDeleteAccount: (() -> Void)?
    var onJoinPartner: ((String) -> Void)?
    var onLeavePartner: (() -> Void)?
    var onUploadPhoto: ((Data) async -> Void)?
    var isProfileSyncing: Bool = false
    @Binding var isLightsOut: Bool
    var primaryActionTitle: String = "enter our space"
    var onPrimaryAction: (() -> Void)?
    var onSelectTab: ((DashboardNavTab) -> Void)?
    var loadPetStatus: (() async throws -> SupabasePetStatus)? = nil
    var performPetAction: ((PetActionType) async throws -> SupabasePetStatus)? = nil
    var loadActivityFeed: (() async throws -> [SupabaseActivityItem])? = nil
    var onPetAlert: ((String, String) -> Void)? = nil
    var onRenamePet: ((String) async throws -> Void)? = nil
    var userEmail: String?
    var onRefreshPairing: (() -> Void)? = nil
    @State private var activeTab: DashboardNavTab = .home
    @State private var keyboardHeight: CGFloat = 0
    @State private var isPetSheetPresented = false
    @State private var petStatus: SupabasePetStatus?
    @State private var isPetStatusLoading = false
    @State private var isPerformingPetAction = false
    @State private var activePetAction: PetActionType?
    @State private var pendingRewardNotice: PetRewardNotice?
    @State private var rewardNotice: PetRewardNotice?
    @State private var lastStreakCelebrateDate: Date?
    @State private var displayHearts: Int = 0
    @State private var displayStreak: Int = 0
    @State private var heartsTimer: Timer?
    @State private var streakTimer: Timer?
    @State private var statusRefreshTimer: AnyCancellable?
    @State private var activityItems: [SupabaseActivityItem] = []
    @State private var isActivityLoading = false
    @State private var activityRefreshTimer: AnyCancellable?
    @State private var showSettings = false

    var body: some View {
        GeometryReader { geo in
            let keyboardLift = keyboardHeight
            let size = geo.size
            let layoutSize = CGSize(width: size.width,
                                    height: size.height + keyboardLift)
            let scaleX = Layout.scaleX(for: layoutSize)
            let scaleY = Layout.scaleY(for: layoutSize)
            let theme = isLightsOut ? Palette.darkTheme : Palette.lightTheme
            let effectiveBottomInset = max(0, geo.safeAreaInsets.bottom - keyboardLift)
            let clampedBottomInset = min(max(effectiveBottomInset, 0),
                                         DashboardLayout.navMaxSafeInset)
            let stableInsets = EdgeInsets(top: geo.safeAreaInsets.top,
                                          leading: geo.safeAreaInsets.leading,
                                          bottom: clampedBottomInset,
                                          trailing: geo.safeAreaInsets.trailing)
            let petDisplayName = petStatus?.petName ?? "Bubba"
            let waterCooldownRemaining = cooldownRemaining(from: petStatus?.lastWateredAt,
                                                          interval: PetCareScreen.waterCooldown)
            let playCooldownRemaining = cooldownRemaining(from: petStatus?.lastPlayedAt,
                                                         interval: PetCareScreen.playCooldown)
            let waterReady = waterCooldownRemaining == nil
            let playReady = playCooldownRemaining == nil

            ZStack {
                if activeTab == .home {
                    CozyDecorLayer(size: layoutSize,
                                   theme: theme,
                                   isLightsOut: isLightsOut,
                                   allowInteractions: true,
                                   lightAction: nil,
                                   waterAction: {
                                        triggerPetShortcut(.water)
                                   },
                                   playAction: {
                                        triggerPetShortcut(.play)
                                   },
                                   waterEnabled: waterReady,
                                   playEnabled: playReady,
                                   decorPlacement: DashboardDecor.placement,
                                   heroAction: {
                                        openPetSheet()
                                   },
                                   heroAllowsInteraction: true)
                } else {
                    backgroundGradient(isDark: isLightsOut)
                        .ignoresSafeArea()
                        .frame(width: layoutSize.width, height: layoutSize.height)
                }

                if activeTab == .home {
                    LightButton(theme: theme,
                                baseWidth: size.width,
                                offsetScaleX: scaleX,
                                offsetScaleY: scaleY,
                                action: {
                                    hapticSoft()
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        isLightsOut.toggle()
                                    }
                                })
                }

                if activeTab == .home {
                    CoupleStatusBadges(theme: theme,
                                       isLightsOut: isLightsOut,
                                       hearts: displayHearts,
                                       streak: displayStreak,
                                       scaleX: scaleX)
                    .position(x: layoutSize.width * 0.5 + DashboardLayout.badgesXOffset * scaleX,
                              y: DashboardLayout.badgesYPosition(for: layoutSize,
                                                                 topInset: geo.safeAreaInsets.top))
                }

                if activeTab == .shortcuts {
                    ShortcutsTabView(theme: theme,
                                     isLightsOut: isLightsOut,
                                     dogName: petDisplayName,
                                     onWater: { triggerPetShortcut(.water) },
                                     onPlay: { triggerPetShortcut(.play) })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if activeTab == .profile {
                    ProfileView(theme: theme,
                                isLightsOut: isLightsOut,
                                safeAreaInsets: stableInsets,
                                extraBottomPadding: DashboardLayout.profileContentPadding,
                                keyboardHeight: keyboardHeight,
                                profileImageURL: profileImageURL,
                                partnerProfileImageURL: partnerProfileImageURL,
                                userName: name,
                                partnerName: partnerName,
                                pairingCode: pairingCode,
                                userIdentifier: userIdentifier,
                                isSyncingProfile: isProfileSyncing,
                                onJoinPartner: onJoinPartner,
                                onLeavePartner: onLeavePartner,
                                onLogout: onLogout,
                                onDeleteAccount: onDeleteAccount,
                                onSettings: { showSettings = true },
                                onRefreshPairing: onRefreshPairing,
                                onUploadPhoto: onUploadPhoto)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            onRefreshPairing?()
                        }
                }

                if activeTab == .activity {
                    ActivityFeedView(theme: theme,
                                     isLightsOut: isLightsOut,
                                     safeAreaInsets: stableInsets,
                                     items: activityItems,
                                     isLoading: isActivityLoading,
                                     userId: userIdentifier,
                                     userName: name,
                                     partnerName: partnerName,
                                     userPhotoURL: profileImageURL,
                                     partnerPhotoURL: partnerProfileImageURL,
                                     onRefresh: { refreshActivity(force: true) })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                GlassyNavBar(theme: theme,
                         isLightsOut: isLightsOut,

                         active: $activeTab,

                         width: DashboardLayout.navWidth(for: layoutSize)) { tab in

                onSelectTab?(tab)

                }
                .position(x: layoutSize.width * 0.5 + DashboardLayout.navXOffset * scaleX,
                      y: DashboardLayout.navY(for: layoutSize, safeBottom: clampedBottomInset))

                .zIndex(1)

                if let rewardNotice {
                    RewardCelebrationView(notice: rewardNotice,
                                          theme: theme,
                                         isLightsOut: isLightsOut) {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                            self.rewardNotice = nil
                        }
                    }
                    .zIndex(2)
                    .id(rewardNotice.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let activePetAction, !isPetSheetPresented {
                    PetActionProgressOverlay(action: activePetAction,
                                             theme: theme,
                                             isLightsOut: isLightsOut,
                                             petName: petStatus?.petName ?? "Bubba")
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .ignoresSafeArea(edges: [.top, .bottom])
            .ignoresSafeArea(.keyboard)
            .animation(.spring(response: 0.5, dampingFraction: 0.9), value: activeTab)
            .fullScreenCover(isPresented: $isPetSheetPresented) {
                ZStack {
                    PetLayoutTab(theme: theme,
                                 status: petStatus,
                                 isLightsOut: isLightsOut,
                                 onClose: { isPetSheetPresented = false },
                                 onRefresh: { refreshPetStatus(force: true) },
                                 onWater: { handlePetAction(.water) },
                                 onPlay: { handlePetAction(.play) },
                                 onRenamePet: onRenamePet,
                                 onRenameCompleted: { refreshPetStatus(force: true) })
                    .background(
                        backgroundGradient(isDark: isLightsOut)
                            .ignoresSafeArea()
                    )

                if let activePetAction {
                    PetActionProgressOverlay(action: activePetAction,
                                             theme: theme,
                                             isLightsOut: isLightsOut,
                                             petName: petStatus?.petName ?? "Bubba")
                            .transition(.opacity)
                            .zIndex(1)
                    }

                    if let rewardNotice {
                        RewardCelebrationView(notice: rewardNotice,
                                              theme: theme,
                                              isLightsOut: isLightsOut) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                                self.rewardNotice = nil
                            }
                        }
                        .id(rewardNotice.id)
                        .zIndex(2)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .fullScreenCover(isPresented: $showSettings) {
                SettingsView(theme: theme,
                             isLightsOut: isLightsOut,
                             userName: name,
                             userEmail: userEmail,
                             partnerName: partnerName,
                             onLogout: {
                                 showSettings = false
                                 onLogout?()
                             },
                             onDeleteAccount: {
                                 showSettings = false
                                 onDeleteAccount?()
                             },
                             onClose: { showSettings = false })
                    .background(backgroundGradient(isDark: isLightsOut).ignoresSafeArea())
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            keyboardHeight = Self.keyboardHeight(from: notification)
        }
        .onAppear {
            refreshPetStatus()
            startStatusTimer()
            startActivityTimer()
        }
        .onDisappear {
            statusRefreshTimer?.cancel()
            statusRefreshTimer = nil
            activityRefreshTimer?.cancel()
            activityRefreshTimer = nil
        }
        .onChange(of: activeTab) { _, newValue in
            if newValue == .activity {
                refreshActivity(force: activityItems.isEmpty)
            }
        }
    }

    private static func keyboardHeight(from notification: Notification) -> CGFloat {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return 0
        }
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return 0
        }
        let converted = window.convert(frame, from: nil)
        let overlap = max(0, window.bounds.maxY - converted.origin.y)
        return overlap
    }

    private func openPetSheet() {
        guard loadPetStatus != nil else { return }
        isPetSheetPresented = true
        refreshPetStatus(force: true)
    }

    private func refreshPetStatus(force: Bool = false) {
        guard let loader = loadPetStatus else { return }
        if isPetStatusLoading && !force { return }
        isPetStatusLoading = true
        Task {
            do {
                let status = try await loader()
                await MainActor.run {
                    self.petStatus = status
                    self.isPetStatusLoading = false
                    self.animateCounters(to: status)
                }
            } catch {
                await MainActor.run {
                    self.isPetStatusLoading = false
                    self.onPetAlert?("Couldn't refresh Bubba", "Please try again in a moment.")
                    if self.petStatus == nil {
                        self.isPetSheetPresented = false
                    }
                }
            }
        }
    }

    private func refreshActivity(force: Bool = false) {
        guard let loader = loadActivityFeed else { return }
        if isActivityLoading && !force { return }
        isActivityLoading = true
        Task {
            do {
                let items = try await loader()
                await MainActor.run {
                    self.activityItems = items
                    self.isActivityLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isActivityLoading = false
                    if self.activeTab == .activity {
                        self.onPetAlert?("Couldn't load activity", "Please try again in a moment.")
                    }
                }
            }
        }
    }

    private func triggerPetShortcut(_ action: PetActionType) {
        guard performPetAction != nil else {
            openPetSheet()
            return
        }
        guard !isPerformingPetAction else { return }
        if !isPetSheetPresented {
            isPetSheetPresented = true
            refreshPetStatus(force: true)
        }
        // Give the sheet a moment to appear, then perform the action (same feel as tapping Bubba)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            handlePetAction(action)
        }
    }

    private func handlePetAction(_ action: PetActionType) {
        guard let performer = performPetAction else { return }
        guard !isPerformingPetAction else { return }
        isPerformingPetAction = true
        activePetAction = action
        Task {
            do {
                let previousHearts = petStatus?.hearts ?? 0
                let previousStreak = petStatus?.streakCount ?? 0
                let status = try await performer(action)
                let stamped = SupabasePetStatus(
                    userId: status.userId,
                    petName: status.petName,
                    mood: status.mood,
                    hydrationLevel: status.hydrationLevel,
                    playfulnessLevel: status.playfulnessLevel,
                    hearts: status.hearts,
                    streakCount: status.streakCount,
                    lastActiveDate: status.lastActiveDate,
                    lastWateredAt: status.lastWateredAt,
                    lastPlayedAt: status.lastPlayedAt,
                    adoptedAt: status.adoptedAt,
                    updatedAt: Date()
                )
                await MainActor.run {
                    self.petStatus = stamped
                    self.isPerformingPetAction = false
                    self.animateCounters(to: stamped)
                    let heartsEarned = max(0, stamped.hearts - previousHearts)
                    let streakBumped = stamped.streakCount > previousStreak
                    let shouldCelebrateStreak = streakBumped && shouldCelebrateCurrentStreak()
                    let willShowReward = heartsEarned > 0 || shouldCelebrateStreak
                    if willShowReward {
                        hapticSuccess()
                        self.pendingRewardNotice = PetRewardNotice(
                            heartsEarned: heartsEarned,
                            totalHearts: stamped.hearts,
                            streakCount: stamped.streakCount,
                            streakBumped: shouldCelebrateStreak,
                            action: action
                        )
                        if shouldCelebrateStreak {
                            lastStreakCelebrateDate = Date()
                        }
                    }
                    self.refreshActivity(force: true)
                }
            } catch {
                await MainActor.run {
                    self.isPerformingPetAction = false
                    self.onPetAlert?("Couldn't send that action", self.petActionFailureMessage(for: error))
                    self.activePetAction = nil
                }
            }
            let overlayHold: TimeInterval = 9.5
            DispatchQueue.main.asyncAfter(deadline: .now() + overlayHold) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.activePetAction = nil
                    self.showPendingRewardIfNeeded()
                }
            }
        }
    }

    private func showPendingRewardIfNeeded() {
        guard let pending = pendingRewardNotice else { return }
        pendingRewardNotice = nil
        withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
            self.rewardNotice = pending
        }
    }

    private func animateCounters(to status: SupabasePetStatus) {
        animateCount(from: displayHearts, to: status.hearts) { value in
            displayHearts = value
        }
        animateCount(from: displayStreak, to: status.streakCount) { value in
            displayStreak = value
        }
    }

    private func startStatusTimer() {
        guard statusRefreshTimer == nil else { return }
        statusRefreshTimer = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                refreshPetStatus(force: true)
            }
    }

    private func startActivityTimer() {
        guard activityRefreshTimer == nil else { return }
        activityRefreshTimer = Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if activeTab == .activity {
                    refreshActivity(force: true)
                }
            }
    }

    private func animateCount(from current: Int, to target: Int, assign: @escaping (Int) -> Void) {
        if target <= current {
            assign(target)
            return
        }
        let totalSteps = min(60, max(8, target - current))
        let stepDelay = 0.03
        let increment = max(1, (target - current) / totalSteps)
        var value = current
        Timer.scheduledTimer(withTimeInterval: stepDelay, repeats: true) { timer in
            value += increment
            if value >= target {
                assign(target)
                timer.invalidate()
            } else {
                assign(value)
            }
        }
    }

    private func cooldownRemaining(from date: Date?, interval: TimeInterval) -> TimeInterval? {
        guard let date else { return nil }
        let remaining = interval - Date().timeIntervalSince(date)
        return remaining > 0 ? remaining : nil
    }

    private func shouldCelebrateCurrentStreak() -> Bool {
        guard let last = lastStreakCelebrateDate else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    private func petActionFailureMessage(for error: Error) -> String {
        let lowercased = error.localizedDescription.lowercased()
        guard lowercased.contains("pet_action_cooldown") else {
            return error.localizedDescription
        }
        let name = (petStatus?.petName ?? "Bubba")
        if lowercased.contains("water") {
            return "\(name) still has fresh water. Try again a bit later."
        }
        if lowercased.contains("play") {
            return "\(name) needs a short break before the next play session."
        }
        return "Give it a little more time and try again."
    }
}

// MARK: - Pet Layout Tab (user-tweakable positioning)

private enum PetLayout {
    // Core canvas sizing
    static let canvasWidth: CGFloat = 380

    // Controls (offsets from safe-area edges)
    static let closeXOffset: CGFloat = 24
    static let closeYOffset: CGFloat = 10
    static let refreshXOffset: CGFloat = 24
    static let refreshYOffset: CGFloat = 10

    // Title + name
    static let titleX: CGFloat = canvasWidth / 2
    static let titleY: CGFloat = 80
    static let subtitleX: CGFloat = canvasWidth / 2
    static let subtitleY: CGFloat = 120

    // Pet image
    static let petX: CGFloat = canvasWidth / 2
    static let petY: CGFloat = 220
    static let petSize: CGFloat = 200

    // Mood + description
    static let moodX: CGFloat = canvasWidth / 2
    static let moodY: CGFloat = 320
    static let descX: CGFloat = canvasWidth / 2
    static let descY: CGFloat = 350
    static let descWidth: CGFloat = canvasWidth - 60

    // Gauges
    static let gaugesX: CGFloat = canvasWidth / 2
    static let gaugesY: CGFloat = 430
    static let gaugeWidth: CGFloat = canvasWidth - 80

    // Info pills
    static let infoY: CGFloat = 650
    static let infoSpacing: CGFloat = 10

    // Actions
    static let actionsX: CGFloat = canvasWidth / 2
    static let actionsY: CGFloat = 570
    static let actionWidth: CGFloat = 150
    static let actionHeight: CGFloat = 100
    static let actionSpacing: CGFloat = 26
}

private struct PetLayoutTab: View {
    let theme: PaletteTheme
    let status: SupabasePetStatus?
    let isLightsOut: Bool
    let onClose: () -> Void
    let onRefresh: () -> Void
    let onWater: () -> Void
    let onPlay: () -> Void
    let onRenamePet: ((String) async throws -> Void)?
    let onRenameCompleted: (() -> Void)?

    private var petName: String { status?.petName ?? "Bubba" }
    private var mood: String { status?.mood ?? "Joyful" }
    private var hydration: Int { status?.hydrationLevel ?? 88 }
    private var play: Int { status?.playfulnessLevel ?? 72 }
    private var waterCooldownText: String? {
        formattedCooldown(from: status?.lastWateredAt, interval: 1 * 60 * 60)
    }
    private var playCooldownText: String? {
        formattedCooldown(from: status?.lastPlayedAt, interval: 15 * 60)
    }
    private var adoptedText: String { relativeOrFallback(date: status?.adoptedAt, fallback: "recently") }
    private var updatedText: String { relativeOrFallback(date: status?.updatedAt, fallback: "just now") }
    private var controlBackground: Color {
        isLightsOut ? Color.white.opacity(0.16) : Color.white.opacity(0.9)
    }

    @State private var isRenamingPet = false
    @State private var renameDraft = ""
    @State private var renameError: String?
    @State private var renameInProgress = false
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundGradient(isDark: isLightsOut)
                    .ignoresSafeArea()

                ZStack {
                    CanvasContent(
                        theme: theme,
                        petName: petName,
                        mood: mood,
                        hydration: hydration,
                        play: play,
                        isLightsOut: isLightsOut,
                        buttonBackground: controlBackground,
                        adoptedText: adoptedText,
                        updatedText: updatedText,
                        waterCooldownText: waterCooldownText,
                        playCooldownText: playCooldownText,
                        onWater: onWater,
                        onPlay: onPlay
                    )
                    .frame(width: PetLayout.canvasWidth, alignment: .center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if onRenamePet != nil {
                        Button {
                            beginRename()
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color(red: 0.56, green: 0.28, blue: 0.14))
                                .background(Circle().fill(Color.white.opacity(isLightsOut ? 0.12 : 0.9)))
                                .shadow(color: Color.black.opacity(0.25), radius: 6, y: 4)
                        }
                        .buttonStyle(.plain)
                        .position(x: PetLayout.subtitleX + 90, y: PetLayout.subtitleY - 10)
                        .zIndex(6)
                    }
                    if onRenamePet != nil && isRenamingPet {
                        renameSheet
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(controlBackground))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                }
                .padding(.leading, PetLayout.closeXOffset)
                .padding(.top, geo.safeAreaInsets.top + PetLayout.closeYOffset)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(theme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(controlBackground))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                }
                .padding(.trailing, PetLayout.refreshXOffset)
                .padding(.top, geo.safeAreaInsets.top + PetLayout.refreshYOffset)
            }
        }
    }

    private struct CanvasContent: View {
        let theme: PaletteTheme
        let petName: String
        let mood: String
        let hydration: Int
        let play: Int
        let isLightsOut: Bool
        let buttonBackground: Color
        let adoptedText: String
        let updatedText: String
        let waterCooldownText: String?
        let playCooldownText: String?
        let onWater: () -> Void
        let onPlay: () -> Void

        var body: some View {
            ZStack {
                Text("Our pet")
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(theme.textMuted)
                    .position(x: PetLayout.titleX, y: PetLayout.titleY)

                Text(petName.lowercased())
                    .font(.system(.largeTitle, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                    .position(x: PetLayout.subtitleX, y: PetLayout.subtitleY)

                Image("bubbaopen")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: PetLayout.petSize, height: PetLayout.petSize)
                    .position(x: PetLayout.petX, y: PetLayout.petY)

                Text(mood)
                    .font(.system(.headline, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .position(x: PetLayout.moodX, y: PetLayout.moodY)

                Text("\(petName.lowercased()) is feeling cozy.")
                    .font(.system(.subheadline))
                    .foregroundColor(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(width: PetLayout.descWidth)
                    .position(x: PetLayout.descX, y: PetLayout.descY)

                infoPills
                    .position(x: PetLayout.canvasWidth / 2, y: PetLayout.infoY)

                gauges
                    .frame(width: PetLayout.gaugeWidth)
                    .position(x: PetLayout.gaugesX, y: PetLayout.gaugesY)

                actions
                    .frame(width: PetLayout.canvasWidth)
                    .position(x: PetLayout.actionsX, y: PetLayout.actionsY)
            }
        }

        private var gauges: some View {
            VStack(spacing: 14) {
                Label("hydration \(hydration)%", systemImage: "drop.fill")
                    .foregroundColor(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ProgressView(value: Float(hydration) / 100)
                    .tint(Color(red: 0.3, green: 0.65, blue: 1.0))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Label("playfulness \(play)%", systemImage: "sparkles")
                    .foregroundColor(theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ProgressView(value: Float(play) / 100)
                    .tint(Color(red: 0.97, green: 0.5, blue: 0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        private var infoPills: some View {
            HStack(spacing: PetLayout.infoSpacing) {
                pill(text: "Adopted \(adoptedText)")
                pill(text: "Last update \(updatedText)")
            }
        }

        private func pill(text: String) -> some View {
            Text(text)
                .font(.system(.caption, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(buttonBackground)
                        .shadow(color: Color.black.opacity(isLightsOut ? 0.25 : 0.08), radius: 6, y: 4)
                )
        }

        private var actions: some View {
            HStack(spacing: PetLayout.actionSpacing) {
                Button(action: {
                    hapticExtreme()
                    onWater()
                }) {
                    VStack {
                        Image(systemName: "drop.fill")
                            .font(.system(size: 24))
                        Text("Water")
                            .font(.system(.subheadline, weight: .semibold))
                        if let waterCooldownText {
                            Text(waterCooldownText)
                                .font(.caption2)
                                .foregroundColor(theme.textMuted)
                        }
                    }
                    .foregroundColor(theme.textPrimary)
                    .frame(width: PetLayout.actionWidth, height: PetLayout.actionHeight)
                    .background(RoundedRectangle(cornerRadius: 20).fill(buttonBackground))
                    .shadow(color: Color.black.opacity(isLightsOut ? 0.25 : 0.08), radius: 8, y: 6)
                }
                .disabled(waterCooldownText != nil)
                .opacity(waterCooldownText != nil ? 0.6 : 1)

                Button(action: {
                    hapticExtreme()
                    onPlay()
                }) {
                    VStack {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 24))
                        Text("Play")
                            .font(.system(.subheadline, weight: .semibold))
                        if let playCooldownText {
                            Text(playCooldownText)
                                .font(.caption2)
                                .foregroundColor(theme.textMuted)
                        }
                    }
                    .foregroundColor(theme.textPrimary)
                    .frame(width: PetLayout.actionWidth, height: PetLayout.actionHeight)
                    .background(RoundedRectangle(cornerRadius: 20).fill(buttonBackground))
                    .shadow(color: Color.black.opacity(isLightsOut ? 0.25 : 0.08), radius: 8, y: 6)
                }
                .disabled(playCooldownText != nil)
                .opacity(playCooldownText != nil ? 0.6 : 1)
            }
        }

    }

    private func relativeOrFallback(date: Date?, fallback: String) -> String {
        guard let date else { return fallback }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formattedCooldown(from date: Date?, interval: TimeInterval) -> String? {
        guard let date else { return nil }
        let remaining = interval - Date().timeIntervalSince(date)
        guard remaining > 0 else { return nil }
        let minutes = Int(ceil(remaining / 60))
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 { return "\(hours)h" }
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m"
    }

    private var renameSheet: some View {
        let sanitized = sanitizedPetName(from: renameDraft)
        return ZStack {
            Color.black.opacity(isLightsOut ? 0.55 : 0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isRenamingPet = false
                    renameError = nil
                }

            VStack(spacing: 14) {
                Text("Name your pet")
                    .font(.system(.headline, weight: .semibold))
                    .foregroundColor(theme.textPrimary)

                TextField("bubba", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: 260)
                    .focused($isRenameFieldFocused)

                if let error = renameError {
                    Text(error)
                        .font(.system(.caption, weight: .medium))
                        .foregroundColor(.red)
                }

                HStack(spacing: 16) {
                    Button {
                        isRenamingPet = false
                        renameError = nil
                    } label: {
                        Text("Cancel")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundColor(theme.textMuted)
                            .frame(width: 112, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(theme.textMuted.opacity(0.4), lineWidth: 1.2)
                            )
                    }

                    Button {
                        commitRename()
                    } label: {
                        HStack(spacing: 6) {
                            if renameInProgress {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            }
                            Text("Save")
                                .font(.system(.subheadline, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 112, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Palette.buttonFill)
                                .shadow(color: Palette.sunShadow.opacity(0.38), radius: 12, y: 6)
                        )
                    }
                    .disabled(renameInProgress || sanitized.isEmpty)
                }
            }
            .padding(26)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(controlBackground)
                    .shadow(color: Color.black.opacity(0.35), radius: 18, y: 10)
            )
            .frame(maxWidth: 320)
        }
        .onAppear {
            renameDraft = petName
            renameError = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isRenameFieldFocused = true
            }
        }
    }

    private func commitRename() {
        let sanitized = sanitizedPetName(from: renameDraft)
        guard !sanitized.isEmpty else {
            renameError = "Give your pet a name."
            return
        }
        guard sanitized != petName else {
            isRenamingPet = false
            return
        }
        guard let handler = onRenamePet else {
            isRenamingPet = false
            return
        }
        renameInProgress = true
        Task {
            do {
                try await handler(sanitized)
                await MainActor.run {
                    renameInProgress = false
                    isRenamingPet = false
                    renameError = nil
                    isRenameFieldFocused = false
                    onRenameCompleted?()
                }
            } catch {
                await MainActor.run {
                    renameInProgress = false
                    renameError = error.localizedDescription
                }
            }
        }
    }

    private func beginRename() {
        guard onRenamePet != nil else { return }
        renameDraft = petName
        renameError = nil
        isRenamingPet = true
    }

    private func sanitizedPetName(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.components(separatedBy: .newlines).joined(separator: " ")
        let limited = String(cleaned.prefix(24))
        return limited
    }
}

enum DashboardNavTab: String, CaseIterable {
    case home, shortcuts, profile, activity

    var label: String {
        switch self {
        case .home: return "home"
        case .shortcuts: return "shortcuts"
        case .profile: return "profile"
        case .activity: return "activity"
        }
    }

    var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .shortcuts: return "sparkles"
        case .profile: return "person.crop.circle"
        case .activity: return "heart.text.square"
        }
    }
}

private struct GlassyNavBar: View {
    let theme: PaletteTheme
    let isLightsOut: Bool
    @Binding var active: DashboardNavTab
    let width: CGFloat
    let onSelect: (DashboardNavTab) -> Void

    var body: some View {
        let activeColor = isLightsOut ? Color.white : theme.textPrimary
        let inactiveColor = isLightsOut ? Color.white.opacity(0.7) : theme.textMuted.opacity(0.8)
        let navBackground = isLightsOut ? Color.white.opacity(0.18) : Color.white.opacity(0.82)

        HStack(spacing: 12) {
            ForEach(DashboardNavTab.allCases, id: \.rawValue) { tab in
                Button {
                    hapticLight()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        active = tab
                    }
                    onSelect(tab)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.label)
                            .font(.system(.caption2, weight: .semibold))
                    }
                    .foregroundStyle(active == tab ? activeColor : inactiveColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                active == tab ?
                                    theme.buttonFill.opacity(isLightsOut ? 0.95 : 0.8) :
                                    navBackground.opacity(isLightsOut ? 0.4 : 0.7)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(navBackground)
                .shadow(color: Color.black.opacity(isLightsOut ? 0.45 : 0.2), radius: 18, y: 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(isLightsOut ? 0.12 : 0.2), lineWidth: 1)
                )
        )
    }
}


private enum DashboardLayout {
    // Slightly narrower nav so bottom props (water/toys) stay tappable
    static let navWidthFactor: CGFloat = 0.8
    static let navXOffset: CGFloat = 0      // shift nav left/right
    static let navBasePadding: CGFloat = 28
    static let navMaxWidth: CGFloat = 480
    static let navMaxSafeInset: CGFloat = 48
    static let profileContentPadding: CGFloat = 220
    static let badgesXOffset: CGFloat = Layout.badgesXOffset
    static let badgesY: CGFloat = 23
    static let heartsBadgeXOffset: CGFloat = Layout.heartsBadgeXOffset
    static let streakBadgeXOffset: CGFloat = Layout.streakBadgeXOffset
    static let badgeWidth: CGFloat = Layout.badgeWidth
    static let badgeSpacing: CGFloat = 18
    static let rewardOverlayPadding: CGFloat = 18

    static func navYOffset(for size: CGSize) -> CGFloat {
        if size.width >= 700 { return 40 }
        if size.height <= 740 { return 20 }
        return 80
    }

    static func navY(for size: CGSize, safeBottom: CGFloat) -> CGFloat {
        let baseline = size.height - max(safeBottom, navBasePadding)
        return baseline + navYOffset(for: size)
    }

    static func navWidth(for size: CGSize) -> CGFloat {
        let target = size.width * navWidthFactor
        return min(target, navMaxWidth)
    }

    static func badgesYPosition(for size: CGSize, topInset: CGFloat) -> CGFloat {
        let scaleY = Layout.scaleY(for: size)
        return topInset + badgesY * scaleY
    }
}

private enum DashboardDecor {
    static let floorWidthFactor: CGFloat = 1.12
    static let floorYOffset: CGFloat = -30

    static let plantWidth: CGFloat = Layout.plantWidth
    static let plantXOffset: CGFloat = Layout.plantXOffset - 10   // example: move plant right
    static let plantOffsetFromFloor: CGFloat = Layout.plantOffsetFromFloor - 10  // lower slightly

    static let loveboxWidth: CGFloat = Layout.loveboxWidth
    static let loveboxXOffset: CGFloat = Layout.loveboxXOffset - 0 // shift left
    static let loveboxY: CGFloat = Layout.loveboxY + 150             // drop lower

    static let tvWidth: CGFloat = Layout.tvWidth
    static let tvXOffset: CGFloat = Layout.tvXOffset
    static let tvY: CGFloat = Layout.tvY

    static let waterWidth: CGFloat = Layout.waterWidth
    static let waterXOffset: CGFloat = Layout.waterXOffset + 10      // pull inwards
    static let waterOffsetFromFloor: CGFloat = Layout.waterOffsetFromFloor

    static let galleryWidth: CGFloat = Layout.galleryWidth
    static let galleryXOffset: CGFloat = Layout.galleryXOffset
    static let galleryY: CGFloat = 360

    static let toysWidth: CGFloat = Layout.toysWidth
    static let toysXOffset: CGFloat = Layout.toysXOffset + 6
    static let toysOffsetFromFloor: CGFloat = Layout.toysOffsetFromFloor

    static let sofaWidth: CGFloat = Layout.sofaWidth
    static let sofaXOffset: CGFloat = Layout.sofaXOffset
    static let sofaOffsetFromFloor: CGFloat = Layout.sofaOffsetFromFloor

    static let windowWidth: CGFloat = Layout.windowWidth
    static let windowXOffset: CGFloat = Layout.windowXOffset
    static let windowY: CGFloat = Layout.windowY + 130               // raise window

    static let heroXOffset: CGFloat = Layout.heroXOffset - 6
    static let heroOffsetFromFloor: CGFloat = Layout.heroOffsetFromFloor * 0.92

    static var placement: DecorPlacement {
        DecorPlacement.dashboard(
            floorWidthFactor: floorWidthFactor,
            floorYOffset: floorYOffset,
            plantWidth: plantWidth,
            plantXOffset: plantXOffset,
            plantOffsetFromFloor: plantOffsetFromFloor,
            loveboxWidth: loveboxWidth,
            loveboxXOffset: loveboxXOffset,
            loveboxY: loveboxY,
            tvWidth: tvWidth,
            tvXOffset: tvXOffset,
            tvY: tvY,
            waterWidth: waterWidth,
            waterXOffset: waterXOffset,
            waterOffsetFromFloor: waterOffsetFromFloor,
            galleryWidth: galleryWidth,
            galleryXOffset: galleryXOffset,
            galleryY: galleryY,
            toysWidth: toysWidth,
            toysXOffset: toysXOffset,
            toysOffsetFromFloor: toysOffsetFromFloor,
            sofaWidth: sofaWidth,
            sofaXOffset: sofaXOffset,
            sofaOffsetFromFloor: sofaOffsetFromFloor,
            windowWidth: windowWidth,
            windowXOffset: windowXOffset,
            windowY: windowY,
            heroXOffset: heroXOffset,
            heroOffsetFromFloor: heroOffsetFromFloor
        )
    }
}

private struct CoupleStatusBadges: View {
    let theme: PaletteTheme
    let isLightsOut: Bool
    let hearts: Int
    let streak: Int
    let scaleX: CGFloat

    var body: some View {
        ZStack {
            CoupleBadge(iconName: "heart.fill",
                        value: hearts,
                        iconColor: Color(red: 0.96, green: 0.45, blue: 0.38),
                        theme: theme,
                        isLightsOut: isLightsOut)
            .offset(x: DashboardLayout.heartsBadgeXOffset * scaleX)

            CoupleBadge(iconName: "flame.fill",
                        value: streak,
                        iconColor: Color(red: 0.98, green: 0.64, blue: 0.33),
                        theme: theme,
                        isLightsOut: isLightsOut)
            .offset(x: DashboardLayout.streakBadgeXOffset * scaleX)
        }
        .frame(width: DashboardLayout.badgeWidth * 2 + DashboardLayout.badgeSpacing)
    }

    private struct CoupleBadge: View {
        let iconName: String
        let value: Int
        let iconColor: Color
        let theme: PaletteTheme
        let isLightsOut: Bool

        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(iconColor)
                    .shadow(color: iconColor.opacity(0.25), radius: 6, x: 0, y: 2)
                Text("\(value)")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 16)
            .frame(width: DashboardLayout.badgeWidth, alignment: .center)
            .background(badgeBackground)
            .clipShape(Capsule(style: .continuous))
            .shadow(color: theme.shadowColor.opacity(isLightsOut ? 0.35 : 0.18), radius: 12, y: 7)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(isLightsOut ? 0.16 : 0.22), lineWidth: 1)
            )
        }

        private var badgeBackground: some View {
            let top = Palette.cream.opacity(isLightsOut ? 0.18 : 0.9)
            let bottom = Palette.peach.opacity(isLightsOut ? 0.2 : 0.95)
            return LinearGradient(colors: [top, bottom],
                                  startPoint: .topLeading,
                                  endPoint: .bottomTrailing)
        }
    }
}

private struct ShortcutsTabView: View {
    let theme: PaletteTheme
    let isLightsOut: Bool
    let dogName: String
    let onWater: () -> Void
    let onPlay: () -> Void

    private struct ShortcutItem: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        let tint: Color
        let action: () -> Void
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(colors: [
            isLightsOut ? Color.black.opacity(0.6) : Color(red: 0.98, green: 0.96, blue: 0.94),
            isLightsOut ? Color(red: 0.12, green: 0.08, blue: 0.07) : Color(red: 0.99, green: 0.92, blue: 0.83)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var shortcutItems: [ShortcutItem] {
        [
            ShortcutItem(icon: "drop.fill",
                         title: "Give \(dogName) water",
                         subtitle: "Hydration boost",
                         tint: Color(red: 0.34, green: 0.63, blue: 0.95),
                         action: onWater),
            ShortcutItem(icon: "gamecontroller.fill",
                         title: "Play with \(dogName)",
                         subtitle: "Sparkly energy",
                         tint: Color(red: 0.98, green: 0.52, blue: 0.64),
                         action: onPlay)
        ]
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Shortcuts")
                        .font(.system(.largeTitle, weight: .bold))
                        .foregroundColor(theme.textPrimary)

                    Text("Tap to send love or care to \(dogName)")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundColor(theme.textMuted)

                    VStack(spacing: 12) {
                        ForEach(shortcutItems) { item in
                            ShortcutRow(item: item, theme: theme, isLightsOut: isLightsOut)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 48)
                .padding(.bottom, 32)
            }
        }
    }

    private struct ShortcutRow: View {
        let item: ShortcutItem
        let theme: PaletteTheme
        let isLightsOut: Bool

        var body: some View {
            Button {
                item.action()
            } label: {
                HStack {
                    ZStack {
                        Circle()
                            .fill(item.tint.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: item.icon)
                            .foregroundColor(item.tint)
                            .font(.system(size: 18, weight: .semibold))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(.body, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                        Text(item.subtitle)
                            .font(.system(.caption, weight: .semibold))
                            .foregroundColor(theme.textMuted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(theme.textMuted)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(isLightsOut ? 0.1 : 0.9))
                        .shadow(color: Color.black.opacity(isLightsOut ? 0.4 : 0.08),
                                radius: 10, y: 6)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ActivityFeedView: View {
    let theme: PaletteTheme
    let isLightsOut: Bool
    let safeAreaInsets: EdgeInsets
    let items: [SupabaseActivityItem]
    let isLoading: Bool
    let userId: String?
    let userName: String
    let partnerName: String?
    let userPhotoURL: URL?
    let partnerPhotoURL: URL?
    let onRefresh: () -> Void

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notifications")
                            .font(.system(.largeTitle, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                        Text("See what your partner is up to")
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundColor(theme.textMuted)
                    }
                    Spacer()
                    Button(action: {
                        hapticLight()
                        onRefresh()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Refresh")
                                .font(.system(.footnote, weight: .semibold))
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            Capsule(style: .continuous)
                                .fill(theme.buttonFill.opacity(isLightsOut ? 0.75 : 0.9))
                        )
                        .foregroundColor(theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, safeAreaInsets.top + 6)

                if isLoading && items.isEmpty {
                    HStack {
                        ProgressView()
                            .tint(theme.textPrimary)
                        Text("Loading activity…")
                            .foregroundColor(theme.textPrimary)
                            .font(.system(.body, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 30)
                } else if items.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(items) { item in
                                ActivityRow(item: item,
                                            theme: theme,
                                            isLightsOut: isLightsOut,
                                            title: description(for: item),
                                            timestamp: relativeDate(for: item.createdAt),
                                            avatar: avatar(for: item),
                                            accent: accent(for: item))
                            }
                            if isLoading {
                                ProgressView()
                                    .tint(theme.textPrimary)
                                    .padding(.vertical, 12)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, safeAreaInsets.bottom + 28)
        }
    }

    private var background: some View {
        let top = isLightsOut ? Color.black.opacity(0.6) : Palette.cream.opacity(0.9)
        let bottom = isLightsOut ? Color.black.opacity(0.85) : Palette.peach.opacity(0.3)
        return LinearGradient(colors: [top, bottom],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("bubbaopen")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .opacity(isLightsOut ? 0.9 : 1)
            Text("You're all caught up")
                .font(.system(.title3, weight: .bold))
                .foregroundColor(theme.textPrimary)
            Text("Recent activities from your partner will land here.")
                .font(.system(.body, weight: .medium))
                .foregroundColor(theme.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func description(for item: SupabaseActivityItem) -> String {
        let actor = item.actorId == userId ? userName : (item.actorName ?? partnerName ?? "Your partner")
        let pet = item.petName ?? "your pet"
        switch item.actionType {
        case "water":
            return "\(actor) watered \(pet)"
        case "play":
            return "\(actor) played with \(pet)"
        default:
            return "\(actor) cared for \(pet)"
        }
    }

    private func avatar(for item: SupabaseActivityItem) -> URL? {
        if item.actorId == userId {
            return userPhotoURL
        }
        return partnerPhotoURL
    }

    private func accent(for item: SupabaseActivityItem) -> Color {
        switch item.actionType {
        case "water": return Color(red: 0.47, green: 0.74, blue: 0.98)
        case "play": return Color(red: 0.99, green: 0.74, blue: 0.42)
        default: return theme.buttonFill
        }
    }

    private func relativeDate(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private struct ActivityRow: View {
        let item: SupabaseActivityItem
        let theme: PaletteTheme
        let isLightsOut: Bool
        let title: String
        let timestamp: String
        let avatar: URL?
        let accent: Color

        var body: some View {
            HStack(spacing: 14) {
                avatarView
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(2)
                    Text(timestamp)
                        .font(.system(.footnote, weight: .medium))
                        .foregroundColor(theme.textMuted)
                }
                Spacer()
                Circle()
                    .fill(accent.opacity(isLightsOut ? 0.7 : 0.9))
                    .frame(width: 12, height: 12)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isLightsOut ? 0.08 : 0.92))
                    .shadow(color: Color.black.opacity(isLightsOut ? 0.35 : 0.1), radius: 10, y: 8)
            )
        }

        private var avatarView: some View {
            ZStack {
                Circle()
                    .fill(theme.buttonFill.opacity(isLightsOut ? 0.65 : 0.85))
                    .frame(width: 44, height: 44)
                if let avatar {
                    AsyncImage(url: avatar) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                        case .failure:
                            fallbackIcon
                        case .empty:
                            ProgressView()
                                .tint(theme.textPrimary)
                        @unknown default:
                            fallbackIcon
                        }
                    }
                } else {
                    fallbackIcon
                }
            }
        }

        private var fallbackIcon: some View {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(theme.textPrimary)
        }
    }
}

private struct SettingsView: View {
    let theme: PaletteTheme
    let isLightsOut: Bool
    let userName: String
    let userEmail: String?
    let partnerName: String?
    let onLogout: (() -> Void)?
    let onDeleteAccount: (() -> Void)?
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                    accountCard
                    supportCard
                    dangerCard
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 80)
            }
        }
    }

    private var background: LinearGradient {
        LinearGradient(colors: [
            isLightsOut ? Color(red: 0.05, green: 0.04, blue: 0.05) : Color(red: 0.99, green: 0.95, blue: 0.9),
            isLightsOut ? Color(red: 0.11, green: 0.08, blue: 0.07) : Color.white
        ], startPoint: .top, endPoint: .bottom)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("settings")
                    .font(.system(.largeTitle, weight: .bold))
                    .foregroundColor(theme.textPrimary)
                Text("everything you need to manage your space")
                    .font(.system(.subheadline))
                    .foregroundColor(theme.textMuted)
            }
            Spacer()
            Button {
                onClose()
            } label: {
                Text("Done")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(isLightsOut ? 0.12 : 0.95))
                            .shadow(color: Color.black.opacity(isLightsOut ? 0.35 : 0.08), radius: 10, y: 4)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var accountCard: some View {
        SectionCard(title: "Account", theme: theme, isLightsOut: isLightsOut) {
            SettingRow(title: "Name", subtitle: userName, systemImage: "person.fill", theme: theme)
            SettingRow(title: "Email", subtitle: userEmail ?? "private", systemImage: "envelope.fill", theme: theme)
            if let partner = partnerName {
                SettingRow(title: "Partner", subtitle: partner, systemImage: "heart.fill", theme: theme)
            }
        }
    }

    private var supportCard: some View {
        SectionCard(title: "Support", theme: theme, isLightsOut: isLightsOut) {
            LinkRow(title: "Terms of Service", systemImage: "doc.text", url: URL(string: "https://lovablee.app/terms"), theme: theme, openURL: openURL)
            LinkRow(title: "Privacy Policy", systemImage: "hand.raised.fill", url: URL(string: "https://lovablee.app/privacy"), theme: theme, openURL: openURL)
            LinkRow(title: "Contact Support", systemImage: "envelope.fill", url: URL(string: "mailto:support@lovablee.app"), theme: theme, openURL: openURL)
        }
    }

    private var dangerCard: some View {
        SectionCard(title: "Danger zone", theme: theme, isLightsOut: isLightsOut) {
            Button(action: {
                onLogout?()
            }) {
                SettingRow(title: "Log out", subtitle: nil, systemImage: "rectangle.portrait.and.arrow.right", theme: theme, iconColor: .red, textColor: .red)
            }
            Button(action: {
                onDeleteAccount?()
            }) {
                SettingRow(title: "Delete account", subtitle: nil, systemImage: "trash", theme: theme, iconColor: .red, textColor: .red)
            }
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let theme: PaletteTheme
    let isLightsOut: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(.caption, weight: .semibold))
                .foregroundColor(theme.textMuted.opacity(0.8))
            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(isLightsOut ? Color.white.opacity(0.08) : Color.white)
                    .shadow(color: Color.black.opacity(isLightsOut ? 0.45 : 0.12), radius: 12, y: 6)
            )
        }
    }
}

private struct SettingRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let theme: PaletteTheme
    let iconColor: Color?
    let textColor: Color?

    init(title: String,
         subtitle: String? = nil,
         systemImage: String,
         theme: PaletteTheme,
         isLightsOut: Bool = false,
         iconColor: Color? = nil,
         textColor: Color? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.theme = theme
        self.iconColor = iconColor
        self.textColor = textColor
    }

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(iconColor ?? theme.textPrimary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundColor(textColor ?? theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.caption))
                        .foregroundColor(theme.textMuted)
                }
            }
            Spacer()
        }
        .padding()
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

private struct LinkRow: View {
    let title: String
    let systemImage: String
    let url: URL?
    let theme: PaletteTheme
    let openURL: OpenURLAction

    var body: some View {
        Button {
            if let url {
                openURL(url)
            }
        } label: {
            HStack {
                Image(systemName: systemImage)
                    .foregroundColor(theme.textPrimary)
                    .frame(width: 28)
                Text(title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundColor(theme.textMuted)
            }
            .padding()
        }
        .buttonStyle(.plain)
        .background(divider)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0))
    }
}

private struct RewardCelebrationView: View {
    let notice: PetRewardNotice
    let theme: PaletteTheme
    let isLightsOut: Bool
    let onDismiss: () -> Void

    @State private var displayedHearts = 0
    @State private var displayedTotalHearts = 0
    @State private var displayedStreak = 0
    @State private var heartPulse = false

    private var rewardCardFill: Color {
        isLightsOut ? Color(red: 0.12, green: 0.11, blue: 0.1) : Color.white
    }

    private var rewardCardStroke: Color {
        isLightsOut ? Color(red: 0.35, green: 0.25, blue: 0.2) : Color(red: 0.98, green: 0.86, blue: 0.74)
    }

    private var streakBackground: Color {
        isLightsOut ? Color(red: 0.32, green: 0.23, blue: 0.18) : Color(red: 1.0, green: 0.75, blue: 0.42)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(isLightsOut ? 0.7 : 0.4)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 18) {
                Spacer()
                rewardCard
                if notice.streakBumped {
                    streakCard
                }
                continueButton
            }
            .padding(DashboardLayout.rewardOverlayPadding)
        }
        .onAppear(perform: startAnimations)
    }

    private var rewardCard: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(rewardCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(rewardCardStroke.opacity(0.4), lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(isLightsOut ? 0.5 : 0.18), radius: 20, y: 10)
            .scaleEffect(heartPulse ? 1.04 : 1)
            .overlay(
                VStack(spacing: 10) {
                    Text("You earned")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundColor(theme.textMuted)
                    HStack(spacing: 6) {
                        Text("+\(displayedHearts)")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Color(red: 0.95, green: 0.46, blue: 0.38))
                    }
                    Text("Total · \(displayedTotalHearts) hearts")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundColor(theme.textMuted)
                }
                .padding(.vertical, 28)
                .padding(.horizontal, 32)
            )
    }

    private var streakCard: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: Color(red: 1.0, green: 0.6, blue: 0.35).opacity(0.6), radius: 12, y: 4)
                Text("\(displayedStreak) day streak")
                    .font(.system(.title3, weight: .bold))
                    .foregroundColor(.white)
            }
            Text(streakSubtitle)
                .font(.system(.subheadline, weight: .medium))
                .foregroundColor(Color.white.opacity(0.95))
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(streakBackground)
                .shadow(color: Color.black.opacity(isLightsOut ? 0.45 : 0.18), radius: 16, y: 8)
        )
    }

    private var streakSubtitle: String {
        if notice.streakBumped {
            return "Streak unlocked! Keep the cozy care going."
        }
        return "You're on a \(notice.streakCount) day streak. Keep it lit!"
    }

    private var continueButton: some View {
        Button(action: onDismiss) {
            Text("Continue")
                .font(.system(.headline, weight: .bold))
                .foregroundColor(theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(Palette.buttonFill)
                        .shadow(color: Palette.sunShadow.opacity(0.4), radius: 14, y: 8)
                )
        }
        .padding(.horizontal, 12)
    }

    private var previousStreak: Int {
        if notice.streakBumped {
            return max(1, notice.streakCount - 1)
        }
        return notice.streakCount
    }

    private func startAnimations() {
        displayedHearts = 0
        displayedTotalHearts = max(0, notice.totalHearts - notice.heartsEarned)
        displayedStreak = previousStreak
        heartPulse = true

        if notice.heartsEarned == 0 {
            displayedTotalHearts = notice.totalHearts
        }

        let stepDelay = 0.07
        for index in 0..<notice.heartsEarned {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * stepDelay) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    displayedHearts = min(notice.heartsEarned, displayedHearts + 1)
                    displayedTotalHearts = min(notice.totalHearts, displayedTotalHearts + 1)
                }
            }
        }

        if notice.streakBumped {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(notice.heartsEarned) * stepDelay + 0.25) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                    displayedStreak = notice.streakCount
                }
            }
        } else {
            displayedStreak = notice.streakCount
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.7)) {
                heartPulse = false
            }
        }
    }
}

private struct PetRewardNotice: Identifiable {
    let id = UUID()
    let heartsEarned: Int
    let totalHearts: Int
    let streakCount: Int
    let streakBumped: Bool
    let action: PetActionType
}

// MARK: - Pet Care Overlay

private struct PetCareScreen: View {
    let status: SupabasePetStatus?
    let isLoading: Bool
    let isPerformingAction: Bool
    let isLightsOut: Bool
    let onDismiss: () -> Void
    let onRefresh: () -> Void
    let onGiveWater: () -> Void
    let onPlay: () -> Void

    static let waterCooldown: TimeInterval = 1 * 60 * 60
    static let playCooldown: TimeInterval = 15 * 60
    private static let overlayMinimumDuration: TimeInterval = 10

    private var petName: String { status?.petName ?? "Bubba" }
    private var normalizedPetName: String { petName.lowercased() }
    private var moodText: String { (status?.mood ?? "Sleepy").lowercased() }
    private var hydrationLevel: Int { max(0, min(status?.hydrationLevel ?? 60, 100)) }
    private var playfulnessLevel: Int { max(0, min(status?.playfulnessLevel ?? 55, 100)) }
    private var theme: PaletteTheme { isLightsOut ? Palette.darkTheme : Palette.lightTheme }
    private var backgroundColor: Color {
        isLightsOut ? Color(red: 0.11, green: 0.1, blue: 0.1) : Palette.cream
    }
    private var overlayGradient: LinearGradient {
        if isLightsOut {
            return LinearGradient(colors: [
                Color.black.opacity(0.65),
                Color(red: 0.2, green: 0.17, blue: 0.15).opacity(0.9)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return LinearGradient(colors: [
            Palette.peach.opacity(0.3),
            Palette.sunGlow.opacity(0.35),
            Palette.cream.opacity(0.2)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    private var cardBackground: Color {
        isLightsOut ? Color.white.opacity(0.12) : Color.white.opacity(0.95)
    }
    private var dividerColor: Color {
        isLightsOut ? Color.white.opacity(0.2) : Color.black.opacity(0.06)
    }
    @State private var activeAction: PetActionType?
    @State private var overlayStart: Date?
    private var waterCooldownRemaining: TimeInterval? {
        cooldownRemaining(since: status?.lastWateredAt, interval: Self.waterCooldown)
    }
    private var playCooldownRemaining: TimeInterval? {
        cooldownRemaining(since: status?.lastPlayedAt, interval: Self.playCooldown)
    }

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 16
            ZStack {
                cozyBackground

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {
                        header
                        heroSection
                        gaugesCard
                        actionSection

                        if isPerformingAction {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(theme.textPrimary)
                                Text("sending love to \(normalizedPetName)…")
                                    .font(.system(.subheadline, weight: .semibold))
                                    .foregroundColor(theme.textPrimary)
                            }
                        }

                        infoCard
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, horizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 32 + proxy.safeAreaInsets.top)
                    .padding(.bottom, max(20, proxy.safeAreaInsets.bottom + 12))
                }
            }
            .overlay(alignment: .top) {
                if isLoading {
                    ProgressView("loading \(normalizedPetName)…")
                        .font(.system(.subheadline, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 26)
                        .background(
                            Capsule()
                                .fill(cardBackground)
                                .shadow(color: .black.opacity(isLightsOut ? 0.4 : 0.12), radius: 12, y: 6)
                        )
                        .padding(.top, 40)
                }
            }
        }
        .ignoresSafeArea()
        .overlay {
                if let activeAction {
                    PetActionProgressOverlay(action: activeAction,
                                             theme: theme,
                                             isLightsOut: isLightsOut,
                                             petName: petName)
                    .transition(.opacity)
            }
        }
        .onChange(of: isPerformingAction) { _, newValue in
            if !newValue {
                scheduleOverlayDismiss()
            }
        }
    }

    private var cozyBackground: some View {
        ZStack {
            backgroundColor
                .overlay(overlayGradient.opacity(isLightsOut ? 0.8 : 0.55))
            CozyAura(
                primary: Palette.sunGlow,
                secondary: Palette.peach,
                accent: theme.textPrimary,
                isLightsOut: isLightsOut
            )
            FloatingHearts(accent: theme.textPrimary.opacity(isLightsOut ? 0.15 : 0.25))
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Button {
                hapticLight()
                onDismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    )
                    .offset(y: 16)
            }

            Spacer()

            Button {
                hapticSoft()
                onRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Palette.textPrimary)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    )
                    .offset(y: 16)
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            Text("Our pet")
                .font(.system(.title2, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            Text(normalizedPetName)
                .font(.system(.largeTitle, weight: .bold))
                .foregroundColor(theme.textPrimary)

            Image("bubbaopen")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 140, height: 140)

            Text(moodText.capitalized)
                .font(.system(.headline, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            Text(moodDescription)
                .font(.system(.subheadline))
                .foregroundColor(theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }

    private var gaugesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("vitals")
                .font(.system(.caption, weight: .bold))
                .foregroundColor(theme.textMuted.opacity(0.9))
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            HStack(spacing: 16) {
                vitalityGauge(
                    label: "hydration",
                    value: hydrationLevel,
                    accent: LinearGradient(colors: [
                        Color(red: 0.4, green: 0.73, blue: 0.96),
                        Color(red: 0.62, green: 0.87, blue: 1.0)
                    ], startPoint: .leading, endPoint: .trailing),
                    icon: "drop.fill"
                )

                vitalityGauge(
                    label: "playfulness",
                    value: playfulnessLevel,
                    accent: LinearGradient(colors: [
                        Color(red: 0.99, green: 0.61, blue: 0.73),
                        Color(red: 0.98, green: 0.74, blue: 0.86)
                    ], startPoint: .leading, endPoint: .trailing),
                    icon: "sparkles"
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(cardBackground)
                .shadow(color: .black.opacity(isLightsOut ? 0.45 : 0.12), radius: 22, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(isLightsOut ? 0.2 : 0.35), lineWidth: 1)
                )
        )
    }

    private func vitalityGauge(label: String,
                               value: Int,
                               accent: LinearGradient,
                               icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(label, systemImage: icon)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                Spacer()
                Text("\(value)%")
                    .font(.system(.headline, weight: .bold))
                    .foregroundColor(theme.textPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(isLightsOut ? 0.08 : 0.2))
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent)
                        .frame(width: max(0, CGFloat(value) / 100 * geo.size.width),
                               height: 12)
                        .shadow(color: Color.black.opacity(isLightsOut ? 0.3 : 0.12), radius: 10, y: 6)
                }
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionSection: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width
            let spacing = min(18, max(12, availableWidth * 0.035))
            let columnWidth = max(120, (availableWidth - spacing) / 2)
            let waterDiameter = min(150, columnWidth * 0.9)
            let playDiameter = min(130, columnWidth * 0.82)
            let waterIconSize = min(90, waterDiameter * 0.62)
            let playIconSize = min(72, playDiameter * 0.55)
            let isStatusReady = status != nil && !isLoading
            let waterDisabled = !isStatusReady || isPerformingAction || waterCooldownRemaining != nil
            let playDisabled = !isStatusReady || isPerformingAction || playCooldownRemaining != nil

            VStack(alignment: .leading, spacing: 18) {
                Text("acts of care")
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(theme.textMuted.opacity(0.9))
                    .textCase(.uppercase)
                    .padding(.horizontal, 4)

                HStack(spacing: spacing) {
                    actionButton(
                        icon: "water",
                        title: "Water boost",
                        detail: "fresh sip & calm energy",
                        iconSize: waterIconSize,
                        diameter: waterDiameter,
                        isDisabled: waterDisabled,
                        cooldownText: cooldownText(for: waterCooldownRemaining),
                        accent: Color(red: 0.4, green: 0.73, blue: 0.96),
                        action: { triggerAction(.water) }
                    )
                    .frame(width: columnWidth)

                    actionButton(
                        icon: "toys",
                        title: "Play break",
                        detail: "wiggles + sparkly joy",
                        iconSize: playIconSize,
                        diameter: playDiameter,
                        isDisabled: playDisabled,
                        cooldownText: cooldownText(for: playCooldownRemaining),
                        accent: Color(red: 0.99, green: 0.61, blue: 0.73),
                        action: { triggerAction(.play) }
                    )
                    .frame(width: columnWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 220)
    }

    private func triggerAction(_ type: PetActionType) {
        guard !isPerformingAction else { return }
        activeAction = type
        overlayStart = Date()
        hapticExtreme()
        switch type {
        case .water:
            onGiveWater()
        case .play:
            onPlay()
        }
    }

    private func scheduleOverlayDismiss() {
        guard activeAction != nil else { return }
        let elapsed = Date().timeIntervalSince(overlayStart ?? Date())
        let delay = max(0, Self.overlayMinimumDuration - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.activeAction = nil
                self.overlayStart = nil
            }
        }
    }

    private func actionButton(icon: String,
                              title: String,
                              detail: String,
                              iconSize: CGFloat,
                              diameter: CGFloat,
                              isDisabled: Bool,
                              cooldownText: String?,
                              accent: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ActionOrb(icon: icon,
                      title: title,
                      detail: detail,
                      accent: accent,
                      diameter: diameter,
                      iconSize: iconSize,
                      isDisabled: isDisabled,
                      cooldownText: cooldownText,
                      isLightsOut: isLightsOut,
                      textColor: theme.textPrimary,
                      mutedColor: theme.textMuted)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
    }

    private struct ActionOrb: View {
        let icon: String
        let title: String
        let detail: String
        let accent: Color
        let diameter: CGFloat
        let iconSize: CGFloat
        let isDisabled: Bool
        let cooldownText: String?
        let isLightsOut: Bool
        let textColor: Color
        let mutedColor: Color

        @State private var pulse = false

        var body: some View {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(isLightsOut ? 0.25 : 0.35))
                        .frame(width: diameter * 0.92, height: diameter * 0.92)
                        .blur(radius: 12)

                    Circle()
                        .stroke(accent.opacity(isDisabled ? 0.18 : 0.55), lineWidth: 8)
                        .frame(width: diameter * (pulse ? 1.08 : 0.94),
                               height: diameter * (pulse ? 1.08 : 0.94))
                        .opacity(isDisabled ? 0.4 : 1)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)

                    Circle()
                        .stroke(lineWidth: 2)
                        .foregroundStyle(
                            LinearGradient(colors: [
                                accent.opacity(isLightsOut ? 0.6 : 0.9),
                                accent.opacity(isLightsOut ? 0.15 : 0.35)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: diameter * 0.9, height: diameter * 0.9)

                    Image(icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Color.white.opacity(isLightsOut ? 0.18 : 0.95))
                                .shadow(color: .black.opacity(isLightsOut ? 0.35 : 0.12), radius: 12, y: 6)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(accent.opacity(isDisabled ? 0.08 : 0.35), lineWidth: 2)
                        )
                }
                .frame(width: diameter, height: diameter)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundColor(textColor)
                    Text(detail)
                        .font(.system(.footnote))
                        .foregroundColor(mutedColor.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let cooldownText {
                        Text(cooldownText)
                            .font(.caption2)
                            .foregroundColor(mutedColor.opacity(0.9))
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .onAppear {
                pulse = true
            }
        }
    }


    private var infoCard: some View {
        VStack(spacing: 18) {
            PetInfoRow(label: "mood", value: moodText, theme: theme)
            Divider().overlay(dividerColor)
            PetInfoRow(label: "adopted", value: adoptedText, theme: theme)
            Divider().overlay(dividerColor)
            PetInfoRow(label: "last update", value: updatedText, theme: theme)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardBackground)
                .shadow(color: .black.opacity(isLightsOut ? 0.3 : 0.12), radius: 18, y: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(isLightsOut ? 0.18 : 0.3), lineWidth: 1)
                )
        )
    }

    private var moodDescription: String {
        if hydrationLevel < 30 {
            return "\(normalizedPetName) could use a little sip."
        }
        if playfulnessLevel < 30 {
            return "\(normalizedPetName) is hoping for play time."
        }
        if hydrationLevel > 80 && playfulnessLevel > 80 {
            return "\(normalizedPetName) feels extra cozy right now."
        }
        return "\(normalizedPetName) is feeling content."
    }

    private var adoptedText: String {
        actionSubtitle(prefix: "since", date: status?.adoptedAt, fallback: "recently adopted")
    }

    private var updatedText: String {
        actionSubtitle(prefix: "synced", date: status?.updatedAt, fallback: "just now")
    }

    private func actionSubtitle(prefix: String, date: Date?, fallback: String) -> String {
        guard let relative = relativeString(for: date) else { return fallback }
        return "\(prefix) \(relative)"
    }

    private func relativeString(for date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func cooldownRemaining(since date: Date?, interval: TimeInterval) -> TimeInterval? {
        guard let date else { return nil }
        let elapsed = Date().timeIntervalSince(date)
        let remaining = interval - elapsed
        return remaining > 0 ? remaining : nil
    }

    private func cooldownText(for remaining: TimeInterval?) -> String? {
        guard let remaining else { return nil }
        let formatted = formattedCooldown(remaining)
        return "ready in \(formatted)"
    }

    private func formattedCooldown(_ seconds: TimeInterval) -> String {
        let minutes = Int(ceil(seconds / 60))
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(mins)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(max(1, Int(seconds)))s"
    }
}

private struct PetActionButton: View {
    let iconName: String
    let title: String
    let subtitle: String
    let footer: String
    let accent: Color
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            hapticSoft()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(iconName)
                        .resizable()
                        .renderingMode(.original)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(accent.opacity(0.2))
                        )
                    Spacer()
                    Image(systemName: "chevron.right")
                    .foregroundColor(Palette.textMuted.opacity(0.5))
                }

                Text(title)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)

                Text(subtitle)
                    .font(.system(.subheadline))
                    .foregroundColor(Palette.textMuted)

                Text(footer.uppercased())
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(accent)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.65 : 1)
    }
}

private struct PetActionProgressOverlay: View {
    let action: PetActionType
    let theme: PaletteTheme
    let isLightsOut: Bool
    let petName: String

    @State private var progress: Double = 0
    @State private var progressTimer: Timer?
    @State private var pulse = false
    @State private var spin = false
    @State private var ripple = false

    private var accent: Color {
        action == .water
        ? Color(red: 0.4, green: 0.73, blue: 0.96)
        : Color(red: 0.99, green: 0.61, blue: 0.73)
    }

    private var title: String {
        action == .water ? "Watering" : "Playtime boost"
    }

    private var referenceName: String {
        let trimmed = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Bubba" : trimmed
    }

    private var subtitle: String {
        let base = referenceName
        return action == .water
            ? "\(base) is sipping up the love."
            : "\(base) is getting extra wiggles."
    }

    private var cardBackground: Color {
        isLightsOut ? Color(red: 0.14, green: 0.11, blue: 0.1) : Color.white
    }

    private var lottieName: String {
        switch action {
        case .water: return "water"
        case .play: return "paws"
        }
    }

    private enum ActionLayout {
        // Water layout
        static let waterSize: CGFloat = 220
        static let waterScale: CGFloat = 0.18
        static let waterOffsetX: CGFloat = -80
        static let waterOffsetY: CGFloat = -70

        // Play layout (paws.json)
        static let playSize: CGFloat = 250
        static let playScale: CGFloat = 0.45
        static let playOffsetX: CGFloat = 0
        static let playOffsetY: CGFloat = -90

        // Hero placement
        static let heroSize: CGFloat = 200
        static let heroOffsetX: CGFloat = 0
        static let heroOffsetY: CGFloat = 35
    }

    private struct LottieConfig {
        let name: String
        let size: CGFloat
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
    }

    private var lottieConfig: LottieConfig {
        switch action {
        case .water:
            return LottieConfig(name: "water",
                                size: ActionLayout.waterSize,
                                scale: ActionLayout.waterScale,
                                offsetX: ActionLayout.waterOffsetX,
                                offsetY: ActionLayout.waterOffsetY)
        case .play:
            return LottieConfig(name: "paws",
                                size: ActionLayout.playSize,
                                scale: ActionLayout.playScale,
                                offsetX: ActionLayout.playOffsetX,
                                offsetY: ActionLayout.playOffsetY)
        }
    }

    private var phaseLine: String {
        let base = referenceName
        switch progress {
        case ..<0.33:
            return "settling in with a deep inhale..."
        case ..<0.66:
            return "sending love across both devices..."
        default:
            return "locking in the cozy vibe for \(base)."
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [
                accent.opacity(isLightsOut ? 0.4 : 0.2),
                Palette.sunGlow.opacity(isLightsOut ? 0.25 : 0.4),
                Color.black.opacity(isLightsOut ? 0.6 : 0.2)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            .overlay(
                CozyAura(
                    primary: accent,
                    secondary: Palette.sunGlow,
                    accent: theme.textPrimary,
                    isLightsOut: isLightsOut
                )
            )

            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(.title2, weight: .black))
                        .foregroundColor(theme.textPrimary)
                    Text(subtitle)
                        .font(.system(.subheadline))
                        .foregroundColor(theme.textMuted)
                        .multilineTextAlignment(.center)
                }

                progressStack
                animationStack
                Text(phaseLine)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundColor(theme.textPrimary.opacity(0.9))
                    .padding(.horizontal, 10)
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 28)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(isLightsOut ? 0.5 : 0.1), radius: 30, y: 20)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(accent.opacity(isLightsOut ? 0.3 : 0.4), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 24)
        }
        .onAppear {
            hapticSoft()
            startProgress()
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse.toggle()
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                spin.toggle()
            }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                ripple.toggle()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                hapticLight()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                hapticSoft()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.5) {
                hapticSuccess()
            }
        }
        .onDisappear {
            progressTimer?.invalidate()
            progressTimer = nil
            progress = 0
        }
    }

    private var progressStack: some View {
        VStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(accent)
                .padding(.horizontal)
            HStack {
                Text("cozying up")
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(theme.textMuted.opacity(0.8))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(theme.textPrimary)
            }
            .padding(.horizontal, 18)
        }
    }

    @ViewBuilder
    private var animationStack: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(isLightsOut ? 0.18 : 0.16))
                .frame(width: 260, height: 260)
                .blur(radius: 18)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            accent.opacity(0.85),
                            Palette.sunGlow.opacity(0.6),
                            accent.opacity(0.4)
                        ],
                        center: .center
                    ),
                    lineWidth: 8
                )
                .frame(width: 240, height: 240)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(.linear(duration: 8).repeatForever(autoreverses: false), value: spin)

            Circle()
                .stroke(accent.opacity(0.3), lineWidth: 2)
                .frame(width: 200, height: 200)
                .blur(radius: 6)
                .scaleEffect(pulse ? 1.06 : 0.94)

            Circle()
                .stroke(accent.opacity(0.22), lineWidth: 3)
                .frame(width: ripple ? 230 : 150, height: ripple ? 230 : 150)
                .opacity(ripple ? 0.1 : 0.35)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: ripple)

            LottieView(name: lottieConfig.name, loopMode: .loop)
                .frame(width: lottieConfig.size, height: lottieConfig.size)
                .scaleEffect(lottieConfig.scale, anchor: .center)
                .offset(x: lottieConfig.offsetX, y: lottieConfig.offsetY)

            Image("bubbaopen")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: ActionLayout.heroSize, height: ActionLayout.heroSize)
                .offset(x: ActionLayout.heroOffsetX, y: ActionLayout.heroOffsetY)
        }
        .frame(height: 260)
    }

    private var waterAnimation: some View {
        VStack(spacing: 10) {
            Image("water")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 90, height: 90)
                .offset(y: pulse ? 10 : -10)
                .opacity(0.92)
                .shadow(color: accent.opacity(0.4), radius: 12, y: 6)

            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 26))
                    .foregroundColor(accent.opacity(0.9))
                    .offset(y: pulse ? -6 : 4)
                Image(systemName: "heart.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Palette.sunGlow.opacity(0.9))
                    .offset(y: pulse ? 6 : -4)
            }
            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(colors: [
                        accent.opacity(0.35),
                        Color.white.opacity(0.0)
                    ], startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: 120, height: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(accent.opacity(0.7))
                        .frame(width: 60, height: 8)
                        .offset(x: pulse ? 20 : -20)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                )
        }
    }

    private var playAnimation: some View {
        VStack(spacing: 8) {
            Image("toys")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 98, height: 98)
                .scaleEffect(pulse ? 1.08 : 0.94)
                .shadow(color: accent.opacity(0.35), radius: 12, y: 8)

            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundColor(accent)
                Image(systemName: "heart.fill")
                    .foregroundColor(Color(red: 1, green: 0.78, blue: 0.58))
            }
            .font(.system(size: 20))
            .opacity(pulse ? 1 : 0.5)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(colors: [
                        accent.opacity(0.4),
                        Color.white.opacity(0.0)
                    ], startPoint: .trailing, endPoint: .leading)
                )
                .frame(width: 120, height: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(accent.opacity(0.8))
                        .frame(width: 60, height: 8)
                        .offset(x: pulse ? -20 : 20)
                        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
                )
        }
        .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulse)
    }

    private func startProgress() {
        progress = 0
        progressTimer?.invalidate()
        let total: TimeInterval = 10
        let step: TimeInterval = 0.2
        var elapsed: TimeInterval = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { timer in
            elapsed += step
            let fraction = min(1, elapsed / total)
            progress = fraction
            if fraction >= 1 {
                timer.invalidate()
                progressTimer = nil
            }
        }
    }

    private func relativeOrFallback(date: Date?, fallback: String) -> String {
        guard let date else { return fallback }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CozyAura: View {
    let primary: Color
    let secondary: Color
    let accent: Color
    let isLightsOut: Bool

    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(primary.opacity(isLightsOut ? 0.25 : 0.18))
                .frame(width: 520, height: 520)
                .blur(radius: 140)
                .offset(x: breathe ? -60 : 40, y: breathe ? -80 : 20)

            Circle()
                .fill(secondary.opacity(isLightsOut ? 0.18 : 0.22))
                .frame(width: 400, height: 400)
                .blur(radius: 120)
                .offset(x: breathe ? 70 : -40, y: breathe ? 60 : -30)

            Circle()
                .fill(accent.opacity(isLightsOut ? 0.12 : 0.18))
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(x: breathe ? -30 : 30, y: breathe ? 50 : -40)
        }
        .animation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true), value: breathe)
        .onAppear { breathe.toggle() }
        .allowsHitTesting(false)
    }
}

    private struct FloatingHearts: View {
        let accent: Color
        @State private var float = false

    var body: some View {
        ZStack {
            heart(offset: CGSize(width: -70, height: float ? -30 : 20), scale: 0.8, opacity: 0.28)
            heart(offset: CGSize(width: 80, height: float ? 10 : -40), scale: 0.9, opacity: 0.24)
            heart(offset: CGSize(width: -10, height: float ? 30 : -30), scale: 1.05, opacity: 0.3)
        }
        .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: float)
        .onAppear { float.toggle() }
        .allowsHitTesting(false)
    }

    private func heart(offset: CGSize, scale: CGFloat, opacity: Double) -> some View {
        Image(systemName: "heart.fill")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 26, height: 26)
            .foregroundColor(accent)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(offset)
    }
}

// removed chip helpers; keeping layout simple and centered

private struct PetInfoRow: View {
    let label: String
    let value: String
    let theme: PaletteTheme

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(.system(.caption, weight: .semibold))
                .foregroundColor(theme.textMuted.opacity(0.7))
            Spacer()
            Text(value.lowercased())
                .font(.system(.body, weight: .semibold))
                .foregroundColor(theme.textPrimary)
        }
    }
}

private struct PetGaugeCard: View {
    let label: String
    let level: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(label.uppercased())
                    .font(.system(.caption, weight: .semibold))
                    .foregroundColor(Palette.textMuted.opacity(0.7))
                Spacer()
                Text("\(level)%")
                    .font(.system(.headline, weight: .bold))
                    .foregroundColor(Palette.textPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent)
                        .frame(width: max(0, CGFloat(level) / 100 * geo.size.width),
                               height: 12)
                }
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Shared gradient for new pet layout
private func backgroundGradient(isDark: Bool) -> LinearGradient {
    if isDark {
        return LinearGradient(colors: [
            Color(red: 0.08, green: 0.07, blue: 0.08),
            Color(red: 0.12, green: 0.1, blue: 0.12)
        ], startPoint: .top, endPoint: .bottom)
    }
    return LinearGradient(colors: [
        Palette.cream,
        Palette.peach.opacity(0.35)
    ], startPoint: .top, endPoint: .bottom)
}

// MARK: - Lottie wrapper
private struct LottieView: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .loop

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: name)
        view.loopMode = loopMode
        view.play()
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        uiView.animation = LottieAnimation.named(name)
        uiView.loopMode = loopMode
        uiView.play()
    }
}
#Preview("Dashboard") {
    DashboardView(name: "bubba",
                  isLightsOut: .constant(false))
}

#Preview("Pet care light") {
    PetLayoutTab(theme: Palette.lightTheme,
                 status: .preview,
                 isLightsOut: false,
                 onClose: {},
                 onRefresh: {},
                 onWater: {},
                 onPlay: {},
                 onRenamePet: nil,
                 onRenameCompleted: nil)
}

#Preview("Pet care dark") {
    PetLayoutTab(theme: Palette.darkTheme,
                 status: .preview,
                 isLightsOut: true,
                 onClose: {},
                 onRefresh: {},
                 onWater: {},
                 onPlay: {},
                 onRenamePet: nil,
                 onRenameCompleted: nil)
}

#Preview("Pet care cooldown") {
    PetLayoutTab(theme: Palette.lightTheme,
                 status: .cooldownPreview,
                 isLightsOut: false,
                 onClose: {},
                 onRefresh: {},
                 onWater: {},
                 onPlay: {},
                 onRenamePet: nil,
                 onRenameCompleted: nil)
}

#Preview("Pet action overlay - water") {
    PetActionProgressOverlay(action: .water,
                             theme: Palette.lightTheme,
                             isLightsOut: false,
                             petName: "Bubba")
}

#Preview("Pet action overlay - play dark") {
    PetActionProgressOverlay(action: .play,
                             theme: Palette.darkTheme,
                             isLightsOut: true,
                             petName: "Bubba")
}
