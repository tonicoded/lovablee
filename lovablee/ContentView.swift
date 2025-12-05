import SwiftUI
import UIKit
import PencilKit
import Combine
import AuthenticationServices
import CryptoKit
import Security
import WidgetKit

private enum AppFlowStage {
    case onboarding
    case nameEntry
    case preferences
    case auth
    case notifications
    case dashboard
}

private struct DashboardAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct ContentView: View {
    @EnvironmentObject private var pushManager: PushNotificationManager
    private let sessionStore = SupabaseSessionStore()
    @State private var stage: AppFlowStage = .onboarding
    @State private var isLightsOut = false
    @State private var profileName: String = ""
    @State private var supabaseSession: SupabaseSession?
    @State private var userRecord: SupabaseUserRegistrationResult?
    @State private var appleIdentifier: String?
    @State private var isPerformingAccountAction = false
    @State private var showDeleteConfirmation = false
    @State private var dashboardAlert: DashboardAlert?
    @State private var hasSyncedUserRecord = false
    @State private var lastSyncedToken: String?
    @State private var userSyncTask: Task<Void, Never>?
    @State private var isSyncingUserRecord = false
    @State private var hasAttemptedSessionRestore = false
    @State private var profileRefreshTask: Task<Void, Never>?
    @State private var profilePhotoVersion = UUID().uuidString
    @State private var partnerPhotoVersion = UUID().uuidString
    @State private var unopenedGift: PurchasedGift?
    @State private var showGiftReceivedModal = false
    private let subscriptionManager = SubscriptionManager.shared
    @State private var coupleIsPremium = false
    @State private var couplePremiumUntil: Date?
    var body: some View {
        ZStack {
            switch stage {
            case .onboarding:
                OnboardingView(isLightsOut: $isLightsOut,
                               onFinish: { stage = .nameEntry })
            case .nameEntry:
                NameEntryView(name: $profileName,
                              isLightsOut: $isLightsOut,
                              onBack: { stage = .onboarding },
                              onContinue: { stage = .preferences })
            case .preferences:
                PreferenceSelectionView(isLightsOut: $isLightsOut,
                                        onBack: { stage = .nameEntry },
                                        onContinue: { stage = .auth })
            case .auth:
                AuthFlowView(displayName: profileName,
                             isLightsOut: $isLightsOut,
                             onBack: { stage = .preferences },
                             onFinished: { session, identifier in
                                 supabaseSession = session
                                 appleIdentifier = identifier
                                 self.sessionStore.save(session: session,
                                                        appleIdentifier: identifier,
                                                        displayName: profileName)

                                 // Clear old widget session first to ensure clean state
                                 WidgetDataStore.shared.clearSession()
                                 print("🧹 Cleared old widget session")

                                 // Save session for widget (only if we have a refresh token)
                                 if let refreshToken = session.refreshToken, !refreshToken.isEmpty {
                                     let expiresAt = Date().addingTimeInterval(TimeInterval(session.expiresIn ?? 3600))
                                     print("📝 Refresh token length: \(refreshToken.count) chars")
                                     print("📝 Refresh token preview: \(refreshToken.prefix(20))...\(refreshToken.suffix(20))")
                                     WidgetDataStore.shared.saveSession(
                                         accessToken: session.accessToken,
                                         refreshToken: refreshToken,
                                         userId: session.user.id,
                                         expiresAt: expiresAt
                                     )
                                     print("✅ Saved session for widget with refresh token")
                                 } else {
                                     print("❌ No refresh token available - widget won't be able to refresh session")
                                 }

                                 stage = .notifications
                                 synchronizeUserRecordIfNeeded()
                             })
            case .notifications:
                NotificationPermissionView(name: profileName,
                                            isLightsOut: $isLightsOut,
                                            onFinish: { stage = .dashboard })
            case .dashboard:
                DashboardView(name: profileName,
                              partnerName: userRecord?.partnerDisplayName,
                              userIdentifier: supabaseSession?.user.id,
                              pairingCode: userRecord?.pairingCode,
                              profileImageURL: profilePhotoURL,
                              partnerProfileImageURL: partnerProfilePhotoURL,
                              onLogout: { handleLogoutTapped() },
                              onDeleteAccount: {
                                  if !isPerformingAccountAction {
                                      showDeleteConfirmation = true
                                  }
                              },
                              onJoinPartner: { code in
                                  joinPartner(with: code)
                              },
                              onLeavePartner: { leavePartner() },
                              onUploadPhoto: { data in
                                  await uploadProfilePhoto(data)
                              },
                              isProfileSyncing: isSyncingUserRecord,
                              isLightsOut: $isLightsOut,
                              primaryActionTitle: "enter our space",
                              onPrimaryAction: nil,
                              onSelectTab: { tab in
                                  if tab == .profile {
                                      ensureLatestUserRecordIfMissing(force: true)
                                      partnerPhotoVersion = UUID().uuidString
                                  }
                              },
                              loadPetStatus: {
                                  try await loadPetStatusFromServer()
                              },
                              performPetAction: { action in
                                  try await performPetAction(action)
                              },
                              loadActivityFeed: {
                                  try await loadActivityFromServer()
                              },
                              onPetAlert: { title, message in
                                  dashboardAlert = DashboardAlert(title: title, message: message)
                              },
                              onRenamePet: { name in
                                  try await renamePet(to: name)
                              },
                              onSendLoveNote: { message in
                                  _ = try await sendLoveNote(message: message)
                              },
                              loadLoveNotes: {
                                  try await loadLoveNotesFromServer()
                              },
                              onSaveDoodle: { image in
                                  _ = try await saveDoodle(image: image)
                              },
                              loadDoodles: {
                                  try await loadDoodlesFromServer()
                              },
                              onPublishLiveDoodle: { image in
                                  try await publishLiveDoodle(image: image)
                              },
                              onFetchLiveDoodle: {
                                  try await fetchLatestLiveDoodle()
                              },
                              onGetCoupleKey: {
                                  try await fetchCoupleKey()
                              },
                              supabaseURL: SupabaseAuthService.shared.publicProjectURL,
                              supabaseAnonKey: SupabaseAuthService.shared.publicAnonKey,
                              supabaseAccessToken: supabaseSession?.accessToken,
                              onSyncPremium: { expires in
                                  try await updatePremiumStatus(until: expires)
                                  try? await refreshCouplePremium()
                              },
                              onRefreshCouplePremium: {
                                  try? await refreshCouplePremium()
                              },
                              isCouplePremium: coupleIsPremium,
                              couplePremiumUntil: couplePremiumUntil,
                              onSendGift: { giftType, message in
                                  _ = try await sendGift(giftType: giftType, message: message)
                              },
                              loadGifts: {
                                  try await loadGiftsFromServer()
                              },
                              userEmail: userRecord?.email,
                              onRefreshPairing: { ensureLatestUserRecordIfMissing(force: true) },
                              onLoadAnniversaries: {
                                  try await loadAnniversaries()
                              },
                              onSetTogetherSince: { date in
                                  try await setTogetherSince(date: date)
                              },
                              onAddCustomAnniversary: { name, date in
                                  try await addCustomAnniversary(name: name, date: date)
                              },
                              onDeleteCustomAnniversary: { id in
                                  try await deleteCustomAnniversary(id: id)
                              },
                              onLoadMoods: { date in
                                  try await loadDailyMoods(for: date)
                              },
                              onSetMood: { option, date in
                                  try await setMood(option: option, for: date)
                              })
                .onAppear {
                    ensureLatestUserRecordIfMissing()
                    startProfileAutoRefresh()
                    checkForUnopenedGifts()
                    // Sync widget with latest doodle
                    Task {
                        await WidgetSyncService.shared.syncWidgetWithLatestDoodle()
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
        }
        .onAppear {
            attemptSessionRestoreIfNeeded()
        }
        .preferredColorScheme(.light)
        .fullScreenCover(item: $unopenedGift) { gift in
            ReceivedGiftModal(gift: gift)
                .onDisappear {
                    Task {
                        do {
                            try await markGiftAsOpened(giftId: gift.id)
                            print("🎁 Marked gift \(gift.id) as opened")
                        } catch {
                            print("❌ Failed to mark gift as opened: \(error)")
                        }
                    }
                }
        }
        .confirmationDialog("Delete account?",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete my space", role: .destructive) {
                performDeleteAccount()
            }
            Button("Cancel", role: .cancel) {
                showDeleteConfirmation = false
            }
        } message: {
            Text("This removes your pairing code, partner link, and notification token from lovablee.")
        }
        .onChange(of: stage) { _, newStage in
            if newStage == .dashboard {
                ensureLatestUserRecordIfMissing(force: true)
                checkForUnopenedGifts()
                startProfileAutoRefresh()
                Task { try? await refreshCouplePremium() }
                // Force widget sync when entering dashboard
                Task {
                    await WidgetSyncService.shared.syncWidgetWithLatestDoodle()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
            if newStage != .dashboard {
                stopProfileAutoRefresh()
            }
        }
        .alert(item: $dashboardAlert) { alert in
            Alert(title: Text(alert.title),
                  message: Text(alert.message),
                  dismissButton: .default(Text("OK")))
        }
        .onChange(of: pushManager.deviceToken) { _, _ in
            synchronizeUserRecordIfNeeded()
        }
    }

    private var profilePhotoURL: URL? {
        guard let id = supabaseSession?.user.id else { return nil }
        return SupabaseAuthService.shared.profileImageURL(for: id, version: profilePhotoVersion)
    }

    private var partnerProfilePhotoURL: URL? {
        guard let partnerId = userRecord?.partnerId else { return nil }
        return SupabaseAuthService.shared.profileImageURL(for: partnerId, version: partnerPhotoVersion)
    }

    private func handleLogoutTapped() {
        guard !isPerformingAccountAction else { return }
        guard supabaseSession != nil else {
            sessionStore.clear()
            stage = .auth
            return
        }
        isPerformingAccountAction = true
        userSyncTask?.cancel()
        stopProfileAutoRefresh()
        Task {
            do {
                try await performWithFreshSession { session in
                    try await SupabaseAuthService.shared.signOut(session: session)
                }
            } catch {
                if let supabaseError = error as? SupabaseAuthError,
                   case .unauthorized = supabaseError {
                    await MainActor.run {
                        self.finishLogoutCleanup()
                    }
                    return
                }
                await MainActor.run {
                    self.dashboardAlert = DashboardAlert(title: "Couldn't log out",
                                                         message: friendlyErrorMessage(for: error, fallback: "We couldn't log you out right now. Please try again."))
                    self.isPerformingAccountAction = false
                }
                return
            }
            await MainActor.run {
                self.finishLogoutCleanup()
            }
        }
    }

    private func performDeleteAccount() {
        guard !isPerformingAccountAction else { return }
        showDeleteConfirmation = false
        guard supabaseSession != nil else {
            stage = .onboarding
            return
        }
        isPerformingAccountAction = true
        userSyncTask?.cancel()
        stopProfileAutoRefresh()
        Task {
            do {
                try await performWithFreshSession { session in
                    try await SupabaseAuthService.shared.deleteUserAccount(session: session)
                }
                try await performWithFreshSession { session in
                    try await SupabaseAuthService.shared.signOut(session: session)
                }
            } catch {
                if let supabaseError = error as? SupabaseAuthError,
                   case .unauthorized = supabaseError {
                    await MainActor.run {
                        self.forceLogoutToWelcome(reason: "Your session expired. Please sign in again.")
                        self.isPerformingAccountAction = false
                    }
                    return
                }
                await MainActor.run {
                    self.dashboardAlert = DashboardAlert(title: "Couldn't delete account",
                                                         message: friendlyErrorMessage(for: error, fallback: "We couldn't delete your account right now. Please try again later."))
                    self.isPerformingAccountAction = false
                }
                return
            }
            await MainActor.run {
                self.supabaseSession = nil
                self.userRecord = nil
                self.appleIdentifier = nil
                self.hasSyncedUserRecord = false
                self.lastSyncedToken = nil
                self.isSyncingUserRecord = false
                self.profileName = ""
                self.stage = .onboarding
                self.isPerformingAccountAction = false
                self.sessionStore.clear()
                self.partnerPhotoVersion = UUID().uuidString
            }
        }
    }

    private func attemptSessionRestoreIfNeeded() {
        guard !hasAttemptedSessionRestore else { return }
        hasAttemptedSessionRestore = true
        guard let stored = sessionStore.load() else { return }
        supabaseSession = stored.session
        appleIdentifier = stored.appleIdentifier
        profileName = stored.displayName
        userRecord = stored.userRecord
        stage = .dashboard
        ensureLatestUserRecordIfMissing(force: true)
        startProfileAutoRefresh()
    }

    private func synchronizeUserRecordIfNeeded() {
        guard supabaseSession != nil,
              let appleIdentifier = appleIdentifier else { return }
        let token = pushManager.deviceToken
        if hasSyncedUserRecord,
           lastSyncedToken == token,
           !(userRecord?.pairingCode?.isEmpty ?? true) {
            return
        }
        userSyncTask?.cancel()
        isSyncingUserRecord = true
        userSyncTask = Task {
            do {
                let record = try await performWithFreshSession { session in
                    try await SupabaseAuthService.shared.registerUser(session: session,
                                                                       appleIdentifier: appleIdentifier,
                                                                       email: session.user.email,
                                                                       displayName: profileName,
                                                                       apnsToken: token)
                }
                await MainActor.run {
                    self.updateState(with: record)
                    self.hasSyncedUserRecord = true
                    self.lastSyncedToken = token
                    self.isSyncingUserRecord = false
                    self.userSyncTask = nil
                }
                if record.pairingCode?.isEmpty ?? true {
                    await fetchLatestUserRecord(token: token)
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("❌ User registration error: \(error)")
                if let supabaseError = error as? SupabaseAuthError,
                   case .unauthorized = supabaseError {
                    await MainActor.run {
                        self.forceLogoutToWelcome(reason: "Your session expired. Please sign in again.")
                    }
                    return
                }
                await MainActor.run {
                    print("❌ Showing dashboard alert for registration error")
                    self.dashboardAlert = DashboardAlert(title: "Couldn't save your profile",
                                                         message: friendlyErrorMessage(for: error, fallback: "Something went wrong. Please try again."))
                    self.isSyncingUserRecord = false
                    self.userSyncTask = nil
                }
                // Retry once after a delay
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                await MainActor.run {
                    print("🔄 Retrying user registration...")
                    synchronizeUserRecordIfNeeded()
                }
            }
        }
    }

    private func ensureLatestUserRecordIfMissing(force: Bool = false) {
        guard supabaseSession != nil else { return }
        if !force,
           let record = userRecord,
           !(record.pairingCode?.isEmpty ?? true) {
            return
        }
        isSyncingUserRecord = true
        Task {
            await fetchLatestUserRecord(token: pushManager.deviceToken)
        }
    }

    private func loadPetStatusFromServer() async throws -> SupabasePetStatus {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.fetchPetStatus(session: session)
        }
    }

    private func performPetAction(_ action: PetActionType) async throws -> SupabasePetStatus {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.performPetAction(session: session,
                                                                  action: action)
        }
    }

    private func renamePet(to name: String) async throws {
        _ = try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.updatePetName(session: session, petName: name)
        }
    }

    private func sendLoveNote(message: String) async throws -> LoveNote {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.sendLoveNote(session: session, message: message)
        }
    }

    private func loadActivityFromServer() async throws -> [SupabaseActivityItem] {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.fetchCoupleActivity(session: session,
                                                                     limit: 10)
        }
    }

    private func loadLoveNotesFromServer() async throws -> [LoveNote] {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.getLoveNotes(session: session, limit: 10)
        }
    }

    private func saveDoodle(image: UIImage) async throws -> Doodle {
        return try await performWithFreshSession { session in
            print("📝 Processing canvas snapshot...")
            print("📝 Image size: \(image.size)")

            guard let pngData = image.pngData() else {
                print("❌ Failed to convert image to PNG data")
                throw SupabaseAuthError.unknown
            }
            print("📝 PNG data size: \(pngData.count) bytes")

            // Encode to base64
            let base64String = pngData.base64EncodedString()
            let content = "data:image/png;base64,\(base64String)"
            print("📝 Base64 content size: \(content.count) characters")

            print("📝 Saving to database with base64 content...")
            let doodle = try await SupabaseAuthService.shared.saveDoodle(session: session, content: content)
            print("📝 Database save successful!")

            // Update widget with saved doodle
            Task {
                await WidgetSyncService.shared.syncWidgetWithLatestDoodle()
            }

            return doodle
        }
    }

    private func loadDoodlesFromServer() async throws -> [Doodle] {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.getDoodles(session: session, limit: 50)
        }
    }

    private func publishLiveDoodle(image: UIImage) async throws {
        try await performWithFreshSession { session in
            guard let pngData = image.pngData() else { return }
            let base64 = pngData.base64EncodedString()
            let content = "data:image/png;base64,\(base64)"
            try await SupabaseAuthService.shared.publishLiveDoodle(
                session: session,
                senderName: profileName.isEmpty ? nil : profileName,
                contentBase64: content
            )
        }
    }

    private func fetchLatestLiveDoodle() async throws -> LiveDoodle? {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.fetchLatestLiveDoodle(
                session: session,
                excludeSenderId: session.user.id
            )
        }
    }

    private func fetchCoupleKey() async throws -> String? {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.getCoupleKey(session: session)
        }
    }

    private func sendGift(giftType: String, message: String) async throws -> PurchasedGift {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.sendGift(session: session, giftType: giftType, message: message)
        }
    }

    private func loadGiftsFromServer() async throws -> [PurchasedGift] {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.getGifts(session: session)
        }
    }

    private func markGiftAsOpened(giftId: UUID) async throws {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.markGiftAsOpened(session: session, giftId: giftId)
        }
    }

    private func loadAnniversaries() async throws -> (togetherSince: Date?, customAnniversaries: [Anniversary]) {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.loadAnniversaries(session: session)
        }
    }

    private func setTogetherSince(date: Date) async throws {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.setTogetherSince(session: session, date: date)
        }
    }

    private func updatePremiumStatus(until: Date?) async throws {
        try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.setPremiumStatus(
                session: session,
                premiumUntil: until,
                premiumSource: session.user.id
            )
        }
    }

    private func refreshCouplePremium() async throws {
        let status = try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.getCouplePremiumStatus(session: session)
        }
        await MainActor.run {
            coupleIsPremium = status.isPremium
            couplePremiumUntil = status.premiumUntil
        }
    }

    private func addCustomAnniversary(name: String, date: Date) async throws -> Anniversary {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.addCustomAnniversary(session: session, name: name, date: date)
        }
    }

    private func deleteCustomAnniversary(id: UUID) async throws {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.deleteCustomAnniversary(session: session, id: id)
        }
    }

    private func loadDailyMoods(for date: Date) async throws -> MoodPair {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.loadDailyMoods(session: session, date: date)
        }
    }

    private func setMood(option: MoodOption, for date: Date) async throws -> MoodEntry {
        return try await performWithFreshSession { session in
            try await SupabaseAuthService.shared.setMood(session: session, option: option, date: date)
        }
    }

    private func checkForUnopenedGifts() {
        guard supabaseSession != nil else { return }
        Task {
            do {
                let gifts = try await loadGiftsFromServer()
                let myUserId = supabaseSession?.user.id

                // Find the first unopened gift that was sent TO me
                if let receivedGift = gifts.first(where: {
                    $0.recipientId == myUserId && !$0.isOpened
                }) {
                    print("🎁 Found unopened gift from \(receivedGift.senderName): \(receivedGift.giftType)")
                    await MainActor.run {
                        unopenedGift = receivedGift
                    }
                } else {
                    print("🎁 No unopened gifts found")
                }
            } catch {
                print("❌ Error checking for unopened gifts: \(error)")
            }
        }
    }

    private func performWithFreshSession<T>(_ operation: @escaping (SupabaseSession) async throws -> T) async throws -> T {
        guard let session = supabaseSession else {
            throw SupabaseAuthError.unauthorized("No session available")
        }
        do {
            return try await operation(session)
        } catch let error as SupabaseAuthError {
            guard case .unauthorized = error else {
                throw error
            }
            // Try to refresh the session
            do {
                let refreshed = try await refreshSupabaseSession()
                return try await operation(refreshed)
            } catch {
                // Refresh failed (refresh token expired), force logout
                throw SupabaseAuthError.unauthorized("Session expired. Please sign in again.")
            }
        }
    }

    

    private func refreshSupabaseSession() async throws -> SupabaseSession {
        guard let currentSession = supabaseSession,
              let refreshToken = currentSession.refreshToken else {
            throw SupabaseAuthError.unauthorized("Session expired. Please sign in again.")
        }
        let newSession = try await SupabaseAuthService.shared.refreshSession(refreshToken: refreshToken)
        await MainActor.run {
            self.supabaseSession = newSession
            self.sessionStore.update(session: newSession)

            // Also update widget session
            if let refreshToken = newSession.refreshToken, !refreshToken.isEmpty {
                let expiresAt = Date().addingTimeInterval(TimeInterval(newSession.expiresIn ?? 3600))
                WidgetDataStore.shared.saveSession(
                    accessToken: newSession.accessToken,
                    refreshToken: refreshToken,
                    userId: newSession.user.id,
                    expiresAt: expiresAt
                )
                print("✅ Updated widget session after refresh")
            }
        }
        return newSession
    }

    private func fetchLatestUserRecord(token: String?) async {
        guard supabaseSession != nil else { return }
        do {
            if let latest = try await performWithFreshSession({ session in
                try await SupabaseAuthService.shared.fetchUserRecord(id: session.user.id,
                                                                     accessToken: session.accessToken)
            }) {
                await MainActor.run {
                    self.updateState(with: latest)
                    self.hasSyncedUserRecord = true
                    self.lastSyncedToken = token
                    self.isSyncingUserRecord = false
                }
                Task { try? await refreshCouplePremium() }
            } else {
                await MainActor.run {
                    self.forceLogoutToWelcome(reason: "We couldn't find your profile. Please sign in again.")
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            if let supabaseError = error as? SupabaseAuthError {
                switch supabaseError {
                case .unauthorized:
                    await MainActor.run {
                        self.forceLogoutToWelcome(reason: "Your session expired. Please sign in again.")
                    }
                    return
                case .server(let message) where message.lowercased().contains("auth error"):
                    await MainActor.run {
                        self.forceLogoutToWelcome(reason: "Your session expired. Please sign in again.")
                    }
                    return
                default:
                    break
                }
            }
            await MainActor.run {
                self.dashboardAlert = DashboardAlert(title: "Couldn't load your profile",
                                                     message: friendlyErrorMessage(for: error, fallback: "Something went wrong. Please try again."))
                self.isSyncingUserRecord = false
            }
        }
    }

    private func joinPartner(with code: String) {
        guard supabaseSession != nil else {
            dashboardAlert = DashboardAlert(title: "Not signed in",
                                            message: "Please finish signing in before joining a partner.")
            return
        }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userSyncTask?.cancel()
        isSyncingUserRecord = true
        userSyncTask = Task {
            do {
                let updated = try await performWithFreshSession { session in
                    try await SupabaseAuthService.shared.joinPartner(session: session,
                                                                     pairingCode: trimmed)
                }
                await MainActor.run {
                    self.updateState(with: updated)
                    self.isSyncingUserRecord = false
                    self.userSyncTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                if let supabaseError = error as? SupabaseAuthError,
                   case .unauthorized = supabaseError {
                    await MainActor.run {
                        self.forceLogoutToWelcome(reason: "Your session expired. Please sign in again.")
                    }
                    return
                }
                await MainActor.run {
                    self.dashboardAlert = DashboardAlert(title: "Couldn't join partner",
                                                         message: friendlyJoinPartnerMessage(for: error))
                    self.isSyncingUserRecord = false
                    self.userSyncTask = nil
                }
            }
        }
    }

    private func leavePartner() {
        guard supabaseSession != nil else { return }
        userSyncTask?.cancel()
        isSyncingUserRecord = true
        userSyncTask = Task {
            do {
                let updated = try await performWithFreshSession { session in
                    try await SupabaseAuthService.shared.leavePartner(session: session)
                }
                await MainActor.run {
                    self.updateState(with: updated)
                    self.isSyncingUserRecord = false
                    self.userSyncTask = nil
                }
            } catch {
                guard !Task.isCancelled else { return }
                if let supabaseError = error as? SupabaseAuthError,
                   case .unauthorized = supabaseError {
                    await MainActor.run {
                        self.forceLogoutToWelcome(reason: "Your session expired. Please sign in again.")
                    }
                    return
                }
                await MainActor.run {
                    self.dashboardAlert = DashboardAlert(title: "Couldn't leave partner",
                                                         message: friendlyErrorMessage(for: error, fallback: "Something went wrong. Please try again."))
                    self.isSyncingUserRecord = false
                    self.userSyncTask = nil
                }
            }
        }
    }

    private func startProfileAutoRefresh() {
        profileRefreshTask?.cancel()
        guard stage == .dashboard else { return }
        profileRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !Task.isCancelled else { break }
                let context = await MainActor.run { () -> (Bool, String?) in
                    (self.supabaseSession != nil, self.pushManager.deviceToken)
                }
                guard context.0 else { continue }
                await self.fetchLatestUserRecord(token: context.1)
            }
        }
    }

    private func stopProfileAutoRefresh() {
        profileRefreshTask?.cancel()
        profileRefreshTask = nil
    }

    private func uploadProfilePhoto(_ data: Data) async {
        guard supabaseSession != nil else { return }
        guard let prepared = normalizedImageData(from: data) else {
            await MainActor.run {
                self.dashboardAlert = DashboardAlert(title: "Couldn't upload photo",
                                                     message: "We couldn't read that image. Please try a different one.")
            }
            return
        }
        do {
            let version = try await performWithFreshSession { session in
                try await SupabaseAuthService.shared.uploadProfileImage(session: session,
                                                                        imageData: prepared)
            }
            await MainActor.run {
                self.profilePhotoVersion = version
            }
        } catch {
            if let supabaseError = error as? SupabaseAuthError,
               case .unauthorized = supabaseError {
                await MainActor.run {
                    self.forceLogoutToWelcome(reason: "Your session expired. Please sign in again.")
                }
                return
            }
            await MainActor.run {
                self.dashboardAlert = DashboardAlert(title: "Couldn't upload photo",
                                                     message: friendlyErrorMessage(for: error, fallback: "Something went wrong. Please try again."))
            }
        }
    }

    private func normalizedImageData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxDimension: CGFloat = 1024
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let resizedImage: UIImage
        if scale < 1 {
            let newSize = CGSize(width: image.size.width * scale,
                                 height: image.size.height * scale)
            UIGraphicsBeginImageContextWithOptions(newSize, true, 1)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
        } else {
            resizedImage = image
        }
        return resizedImage.jpegData(compressionQuality: 0.8)
    }

    @MainActor
    private func updateState(with record: SupabaseUserRegistrationResult) {
        self.userRecord = record
        if let name = record.displayName, !name.isEmpty {
            self.profileName = name
            self.sessionStore.updateDisplayName(name)
        }
        self.partnerPhotoVersion = UUID().uuidString
        self.sessionStore.update(userRecord: record)
        Task { try? await refreshCouplePremium() }
    }

    private func friendlyJoinPartnerMessage(for error: Error) -> String {
        guard let supabaseError = error as? SupabaseAuthError else {
            return friendlyErrorMessage(for: error, fallback: "We couldn't link you two right now. Please try again in a moment.")
        }
        switch supabaseError {
        case .server(let message):
            let lower = message.lowercased()
            if lower.contains("invalid_pairing_code") {
                return "That space ID isn't valid. Double-check the letters and try again."
            } else if lower.contains("cannot_join_self") {
                return "That's your own space ID — share it with your partner so they can join."
            } else {
                return "We couldn't link you two right now. Please try again in a moment."
            }
        case .unauthorized:
            return "You're signed out. Please open lovablee again to reconnect."
        case .emailInUse:
            return "That email is already registered. Please sign in instead."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .unknown:
            return "We couldn't link you two right now. Please try again in a moment."
        }
    }

    /// Convert any error to a user-friendly message
    private func friendlyErrorMessage(for error: Error, fallback: String) -> String {
        // Handle NetworkError specifically
        if let networkError = error as? NetworkError {
            return networkError.friendlyMessage
        }

        // Handle URLError (timeout, no connection, etc.)
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection. Please check your network and try again."
            case .timedOut:
                return "Request timed out. Please check your connection and try again."
            case .cannotFindHost, .cannotConnectToHost:
                return "Can't reach the server. Please try again later."
            case .userAuthenticationRequired:
                return "Your session expired. Please restart the app."
            default:
                return "Network error. Please check your connection and try again."
            }
        }

        // Handle SupabaseAuthError
        if let supabaseError = error as? SupabaseAuthError {
            switch supabaseError {
            case .unauthorized:
                return "Your session expired. Please restart the app."
            case .server:
                return "Server error. Please try again in a moment."
            case .emailInUse:
                return "That email is already registered. Please sign in instead."
            case .weakPassword:
                return "Password must be at least 6 characters."
            case .unknown:
                return fallback
            }
        }

        // Generic fallback
        return fallback
    }

    @MainActor
    private func finishLogoutCleanup() {
        self.supabaseSession = nil
        self.userRecord = nil
        self.appleIdentifier = nil
        self.hasSyncedUserRecord = false
        self.lastSyncedToken = nil
        self.isSyncingUserRecord = false
        self.stage = .auth
        self.isPerformingAccountAction = false
        self.sessionStore.clear()
        self.partnerPhotoVersion = UUID().uuidString
        WidgetDataStore.shared.clearSession()
    }

    @MainActor
    private func forceLogoutToWelcome(reason: String) {
        dashboardAlert = DashboardAlert(title: "Signed out",
                                        message: reason)
        supabaseSession = nil
        userRecord = nil
        appleIdentifier = nil
        hasSyncedUserRecord = false
        lastSyncedToken = nil
        isSyncingUserRecord = false
        stage = .auth
        sessionStore.clear()
        partnerPhotoVersion = UUID().uuidString
    }
}

struct OnboardingView: View {
    @Binding var isLightsOut: Bool
    @State private var currentPage = 0
    let onFinish: () -> Void

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "grow closer",
            subtitle: "build a cozy space just for the two of you"
        ),
        OnboardingPage(
            title: "care for each other",
            subtitle: "share moments, grow closer, and stay connected"
        ),
        OnboardingPage(
            title: "play together",
            subtitle: "doodle, mini games, and send love to each other"
        )
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let theme = isLightsOut ? Palette.darkTheme : Palette.lightTheme
            let scaleX = Layout.scaleX(for: size)
            let scaleY = Layout.scaleY(for: size)

            ZStack {
                CozyDecorLayer(size: size,
                               theme: theme,
                               isLightsOut: isLightsOut,
                               allowInteractions: true,
                               lightAction: {
                                   hapticSoft()
                                   withAnimation(.easeInOut(duration: 0.4)) {
                                        isLightsOut.toggle()
                                   }
                               },
                               decorPlacement: .onboarding)

                // Swipeable text only; dog and other elements stay put.
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingTextView(page: pages[index], size: size, theme: theme)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .zIndex(0)

                PageDots(currentIndex: currentPage, total: pages.count, theme: theme)
                    .position(x: size.width * 0.5 + Layout.dotsXOffset * scaleX,
                              y: Layout.dotsY * scaleY)

                Button {
                    if currentPage < pages.count - 1 {
                        hapticSoft()
                        withAnimation { currentPage += 1 }
                    } else {
                        hapticSoft()
                        onFinish()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "next" : "get started")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .background(
                    Capsule()
                        .fill(theme.buttonFill)
                        .shadow(color: theme.shadowColor.opacity(0.28), radius: 14, y: 7)
                )
                .frame(width: max(0, size.width - 64))
                .position(x: size.width * 0.5 + Layout.buttonXOffset * scaleX,
                          y: Layout.buttonY * scaleY)

                LightButton(theme: theme,
                            baseWidth: size.width,
                            offsetScaleX: scaleX,
                            offsetScaleY: scaleY,
                            action: {
                                hapticSoft()
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    isLightsOut.toggle()
                                }
                            })
                .zIndex(10)
            }
            .onChange(of: currentPage) { _, _ in hapticLight() }
            .ignoresSafeArea(.keyboard)
        }
    }
}

private struct NameEntryView: View {
    @Binding var name: String
    @FocusState private var isFocused: Bool
    @Binding var isLightsOut: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let theme = isLightsOut ? Palette.darkTheme : Palette.lightTheme
            ZStack {
                Rectangle()
                    .fill(Color(red: 0.996, green: 0.909, blue: 0.749))
                    .ignoresSafeArea()
                    .colorMultiply(isLightsOut ? Color(red: 0.55, green: 0.5, blue: 0.45) : .white)

                if isLightsOut {
                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    RadialGradient(colors: [Color.black.opacity(0.35), Color.clear],
                                   center: .center,
                                   startRadius: 10,
                                   endRadius: 420)
                        .ignoresSafeArea()
                        .blendMode(.multiply)
                        .allowsHitTesting(false)
                }

                // Responsive, proportional layout for name entry
                let fieldBackground = isLightsOut ?
                    Color.white.opacity(0.1) :
                    Color.white.opacity(0.75)
                let titleColor = isLightsOut ? Color.white.opacity(0.95) : theme.textPrimary
                ZStack {
                    // BACK BUTTON
                    Button {
                        hapticLight()
                        onBack()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("back")
                        }
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    }
                    .position(x: size.width * 0.15,
                              y: size.height * 0.08)

                    VStack(spacing: 32) {

                        Text("let's get started! what's your name?")
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(titleColor)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 24)

                        HStack(spacing: 10) {
                            Image(systemName: "person.fill")
                                .foregroundStyle(theme.textMuted.opacity(0.9))

                            TextField("your name",
                                      text: $name,
                                      prompt: Text("your name")
                                        .foregroundStyle(titleColor.opacity(0.92)))
                                .focused($isFocused)
                                .font(.system(.body))
                                .foregroundStyle(titleColor)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 14)
                        .background(
                            Capsule()
                                .fill(fieldBackground)
                                .shadow(color: Color.black.opacity(0.1), radius: 10, y: 5)
                        )
                        .padding(.horizontal, 24)

                        Button {
                            guard isValid else { return }
                            hapticSoft()
                            onContinue()
                        } label: {
                            Text("continue")
                                .font(.system(.headline, weight: .semibold))
                                .foregroundStyle(isValid ? theme.textPrimary : theme.textMuted.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .background(
                            Capsule()
                                .fill(isValid ? theme.buttonFill : theme.buttonFill.opacity(0.55))
                                .shadow(color: theme.shadowColor.opacity(0.25), radius: 12, y: 6)
                        )
                        .disabled(!isValid)
                        .padding(.horizontal, 24)
                    }
                    .position(x: size.width * 0.5,
                              y: size.height * 0.42)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isFocused = true
                }
            }
            .ignoresSafeArea(.keyboard)
        }
    }
}

private struct PreferenceSelectionView: View {
    @Binding var isLightsOut: Bool
    let onBack: () -> Void
    let onContinue: () -> Void

    @State private var selectedOptions = Set<UUID>()
    private let options: [PreferenceOption] = [
        PreferenceOption(title: "staying connected", iconName: "heart"),
        PreferenceOption(title: "learning more about each other", iconName: "person.2"),
        PreferenceOption(title: "growing as a couple", iconName: "leaf.fill"),
        PreferenceOption(title: "decorating our home", iconName: "house.fill"),
        PreferenceOption(title: "playing games together", iconName: "die.face.5")
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let theme = isLightsOut ? Palette.darkTheme : Palette.lightTheme
            let scaleX = Layout.scaleX(for: size)
            let scaleY = Layout.scaleY(for: size)

            ZStack {
                // Backgrounds
                Rectangle()
                    .fill(Color(red: 0.996, green: 0.909, blue: 0.749))
                    .colorMultiply(isLightsOut ? Color(red: 0.55, green: 0.5, blue: 0.45) : .white)
                    .ignoresSafeArea()

                if isLightsOut {
                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .ignoresSafeArea()
                    RadialGradient(colors: [Color.black.opacity(0.4), Color.clear],
                                   center: .center,
                                   startRadius: 10,
                                   endRadius: 420)
                        .ignoresSafeArea()
                        .blendMode(.multiply)
                }

                // Back Button
                Button {
                    hapticLight()
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }
                .position(x: size.width * 0.15,
                          y: size.height * 0.08)

                // Title
                Text("what are you looking forward to the most?")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(width: size.width * 0.8)
                    .position(x: size.width * 0.5,
                              y: size.height * 0.16)

                // Subtitle
                Text("select as many as you like!")
                    .font(.system(.body, weight: .medium))
                    .foregroundColor(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(width: size.width * 0.8)
                    .position(x: size.width * 0.5,
                              y: size.height * 0.205)

                VStack(spacing: 14) {
                    ForEach(options) { option in
                        let isSelected = selectedOptions.contains(option.id)
                        Button {
                            hapticSoft()
                            if isSelected { selectedOptions.remove(option.id) }
                            else { selectedOptions.insert(option.id) }
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: option.iconName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(isLightsOut ? .white.opacity(isSelected ? 1 : 0.75) : theme.textPrimary.opacity(isSelected ? 1 : 0.85))
                                    .frame(width: 28)

                                Text(option.title)
                                    .font(.system(.body, weight: .medium))
                                    .foregroundColor(theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)

                                Spacer()

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 18)
                            .background(
                                Capsule()
                                    .fill(isSelected ?
                                          (isLightsOut ? theme.buttonFill.opacity(0.7) : theme.buttonFill)
                                          :
                                          (isLightsOut ? Color.white.opacity(0.08) : Color.white.opacity(0.92)))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .position(x: size.width * 0.5,
                          y: size.height * 0.47)

            // Continue Button
            Button {
                guard !selectedOptions.isEmpty else { return }
                hapticSoft()
                onContinue()
            } label: {
                Text("continue")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .frame(width: size.width * 0.8)
                        .padding(.vertical, 18)
                        .background(
                            Capsule()
                                .fill(isLightsOut ? theme.buttonFill.opacity(0.85) : theme.buttonFill)
                                .shadow(color: theme.shadowColor.opacity(0.25), radius: 10, y: 6)
                        )
                }
                .disabled(selectedOptions.isEmpty)
                .opacity(selectedOptions.isEmpty ? 0.65 : 1)
                .position(x: size.width * 0.5,
                          y: size.height * 0.83)
            }
        }
    }
}

private struct PreferenceOption: Identifiable {
    let id = UUID()
    let title: String
    let iconName: String
}

private struct NotificationPermissionView: View {
    let name: String
    @Binding var isLightsOut: Bool
    let onFinish: () -> Void

    @EnvironmentObject private var pushManager: PushNotificationManager
    @State private var didAutoFinish = false

    private var isAuthorized: Bool {
        switch pushManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private var statusText: String {
        switch pushManager.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "notifications are on—expect cozy pings soon"
        case .denied:
            return "notifications are turned off in Settings"
        case .notDetermined:
            return "we'll only send heartfelt things when you say so"
        @unknown default:
            return "notification status unknown"
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let theme = isLightsOut ? Palette.darkTheme : Palette.lightTheme
            ZStack {
                Rectangle()
                    .fill(Color(red: 0.996, green: 0.909, blue: 0.749))
                    .ignoresSafeArea()
                    .colorMultiply(isLightsOut ? Color(red: 0.55, green: 0.5, blue: 0.45) : .white)

                if isLightsOut {
                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .ignoresSafeArea()
                }

                VStack(spacing: 24) {
                    Text("stay in the loop, \(name.isEmpty ? "lovebird" : name.lowercased())?")
                        .font(.system(.title3, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Text("we'll gently nudge you with live pings, doodles, and love notes when something sweet happens.")
                        .font(.system(.body))
                        .foregroundStyle(theme.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    VStack(spacing: 14) {
                        PermissionCard(icon: "sparkles",
                                       title: "live pings",
                                       detail: "tiny heads-ups when your person doodles or shares a note")
                        PermissionCard(icon: "heart.circle.fill",
                                       title: "love notes",
                                       detail: "gentle reminders that someone is thinking about you")
                        PermissionCard(icon: "hand.wave",
                                       title: "daily warmth",
                                       detail: "opt-in nudges to check in, if you’d like")
                    }
                    .padding(.horizontal, 16)

                    VStack(spacing: 12) {
                        Text(statusText)
                            .font(.system(.callout))
                            .foregroundStyle(theme.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        if !isAuthorized {
                        Button {
                            pushManager.beginRegistrationFlow()
                        } label: {
                            Text("yes, send the cozy stuff")
                                .font(.system(.headline, weight: .semibold))
                                    .foregroundStyle(theme.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                            }
                            .background(
                                Capsule()
                                    .fill(theme.buttonFill)
                                    .shadow(color: theme.shadowColor.opacity(0.2), radius: 10, y: 6)
                            )
                            .padding(.horizontal, 32)
                        }

                        Button {
                            onFinish()
                        } label: {
                            Text(isAuthorized ? "all set—enter our cozy space" : "maybe later")
                                .font(.system(.body, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity)
                        }
                        .background(
                            Capsule()
                                .stroke(theme.buttonFill.opacity(0.4), lineWidth: 1)
                        )
                        .padding(.horizontal, 40)
                    }

                    Spacer()
                }
                .frame(width: size.width)
            }
            .onAppear {
                handleStatus(pushManager.authorizationStatus)
            }
            .onChange(of: pushManager.authorizationStatus) { _, newValue in
                handleStatus(newValue)
            }
        }
    }

    private func handleStatus(_ status: UNAuthorizationStatus) {
        guard !didAutoFinish else { return }
        switch status {
        case .authorized, .provisional, .ephemeral:
            didAutoFinish = true
            onFinish()
        case .notDetermined, .denied:
            break
        @unknown default:
            break
        }
    }
}

private struct PermissionCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Palette.sunShadow)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.body, weight: .semibold))
                    .foregroundColor(Palette.textPrimary)
                Text(detail)
                    .font(.system(.subheadline))
                    .foregroundColor(Palette.textMuted)
            }
            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.85))
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
        )
    }
}

private struct AuthFlowView: View {
    enum AuthMode {
        case apple
        case email
    }

    let displayName: String
    @Binding var isLightsOut: Bool
    let onBack: () -> Void
    let onFinished: (SupabaseSession, String) -> Void

    @State private var authMode: AuthMode = .apple
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isSignUp: Bool = true
    @State private var isLoading = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var currentNonce: String?
    @State private var currentNonceHashed: String?
    @State private var session: SupabaseSession?
    @State private var appleIdentifier: String?
    @State private var didSignalSessionCompletion = false
    @FocusState private var focusedField: Field?

    enum Field {
        case email, password, confirmPassword
    }

    private let authService = SupabaseAuthService.shared

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let theme = isLightsOut ? Palette.darkTheme : Palette.lightTheme

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button {
                            hapticLight()
                            onBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(theme.textPrimary)
                                .padding(10)
                                .background(Circle().fill(theme.buttonFill.opacity(0.2)))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, geo.safeAreaInsets.top + 20)

                    // Main Content
                    VStack(spacing: 32) {
                        // Title Section
                        VStack(spacing: 12) {
                            Image(systemName: "heart.circle.fill")
                                .font(.system(size: 64, weight: .medium))
                                .foregroundStyle(theme.buttonFill)

                            Text("welcome to lovablee")
                                .font(.system(.largeTitle, weight: .bold))
                                .foregroundStyle(theme.textPrimary)

                            Text("your cozy space for two")
                                .font(.system(.body))
                                .foregroundStyle(theme.textMuted)
                        }
                        .padding(.top, 40)

                        // Auth Mode Toggle
                        Picker("Auth Mode", selection: $authMode) {
                            Text("Sign in with Apple").tag(AuthMode.apple)
                            Text("Email").tag(AuthMode.email)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 32)
                        .onChange(of: authMode) { _, _ in
                            // Clear errors when switching auth mode
                            errorMessage = nil
                            statusMessage = nil
                        }

                        // Auth Content
                        if authMode == .apple {
                            appleAuthView(theme: theme)
                        } else {
                            emailAuthView(theme: theme)
                        }

                        // Status Messages
                        if let message = statusMessage {
                            StatusToast(text: message,
                                        theme: theme,
                                        icon: "checkmark.seal.fill",
                                        color: Color.green.opacity(0.85))
                                .padding(.horizontal, 32)
                        } else if let error = errorMessage {
                            StatusToast(text: error,
                                        theme: theme,
                                        icon: "exclamationmark.triangle.fill",
                                        color: Color.red.opacity(0.85))
                                .padding(.horizontal, 32)
                        }
                    }

                    // Terms and Privacy
                    VStack(spacing: 6) {
                        Text("By continuing, you agree to lovablee's")
                            .font(.system(.footnote))
                            .foregroundStyle(theme.textMuted)
                        HStack(spacing: 4) {
                            Link("Terms of Service",
                                 destination: URL(string: "https://lovablee.app/terms")!)
                                .font(.system(.footnote, weight: .semibold))
                            Text("and")
                                .font(.system(.footnote))
                                .foregroundStyle(theme.textMuted)
                            Link("Privacy Policy",
                                 destination: URL(string: "https://lovablee.app/privacy")!)
                                .font(.system(.footnote, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 32)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 40)
                }
                .frame(maxWidth: .infinity)
            }
            .background(
                Rectangle()
                    .fill(Color(red: 0.996, green: 0.909, blue: 0.749))
                    .ignoresSafeArea()
                    .colorMultiply(isLightsOut ? Color(red: 0.55, green: 0.5, blue: 0.45) : .white)
            )
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private func appleAuthView(theme: PaletteTheme) -> some View {
        VStack(spacing: 20) {
            Text("Quick and secure sign in with your Apple ID")
                .font(.system(.callout))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            SignInWithAppleButton(.signIn) { request in
                let nonce = AppleNonce.random()
                currentNonce = nonce
                currentNonceHashed = nonce.sha256()
                request.requestedScopes = [.fullName, .email]
                request.nonce = currentNonceHashed
                // Clear any previous error messages
                errorMessage = nil
                statusMessage = nil
            } onCompletion: { result in
                handleAppleResult(result)
            }
            .frame(height: 56)
            .cornerRadius(16)
            .signInWithAppleButtonStyle(isLightsOut ? .white : .black)
            .overlay {
                if isLoading && authMode == .apple {
                    ZStack {
                        Color.black.opacity(0.1)
                        ProgressView().progressViewStyle(.circular)
                    }
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal, 32)
            .disabled(isLoading)
        }
    }

    @ViewBuilder
    private func emailAuthView(theme: PaletteTheme) -> some View {
        VStack(spacing: 24) {
            // Sign Up / Sign In Toggle
            HStack(spacing: 0) {
                Button {
                    hapticLight()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSignUp = true
                        errorMessage = nil
                    }
                } label: {
                    Text("Sign Up")
                        .font(.system(.body, weight: isSignUp ? .semibold : .regular))
                        .foregroundStyle(isSignUp ? theme.textPrimary : theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Button {
                    hapticLight()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSignUp = false
                        errorMessage = nil
                    }
                } label: {
                    Text("Sign In")
                        .font(.system(.body, weight: !isSignUp ? .semibold : .regular))
                        .foregroundStyle(!isSignUp ? theme.textPrimary : theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)

            // Email/Password Fields
            VStack(spacing: 16) {
                // Email Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(theme.textPrimary)

                    TextField("your@email.com", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .focused($focusedField, equals: .email)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isLightsOut ? Color.white.opacity(0.1) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(focusedField == .email ? theme.buttonFill : Color.clear, lineWidth: 2)
                        )
                }

                // Password Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(theme.textPrimary)

                    SecureField("••••••••", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                        .focused($focusedField, equals: .password)
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isLightsOut ? Color.white.opacity(0.1) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(focusedField == .password ? theme.buttonFill : Color.clear, lineWidth: 2)
                        )
                }

                // Confirm Password Field (only for sign up)
                if isSignUp {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(theme.textPrimary)

                        SecureField("••••••••", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .confirmPassword)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isLightsOut ? Color.white.opacity(0.1) : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(focusedField == .confirmPassword ? theme.buttonFill : Color.clear, lineWidth: 2)
                            )
                    }
                }
            }
            .padding(.horizontal, 32)

            // Submit Button
            Button {
                hapticSoft()
                handleEmailAuth()
            } label: {
                if isLoading && authMode == .email {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text(isSignUp ? "Create Account" : "Sign In")
                        .font(.system(.headline, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(theme.buttonFill)
            )
            .padding(.horizontal, 32)
            .disabled(isLoading || !isEmailFormValid)
            .opacity(isEmailFormValid ? 1.0 : 0.5)
        }
    }

    private var isEmailFormValid: Bool {
        let emailValid = !email.trimmingCharacters(in: .whitespaces).isEmpty &&
                        email.contains("@") && email.contains(".")
        let passwordValid = password.count >= 6

        if isSignUp {
            return emailValid && passwordValid && password == confirmPassword
        } else {
            return emailValid && passwordValid
        }
    }

    private func handleEmailAuth() {
        guard isEmailFormValid else { return }

        errorMessage = nil
        isLoading = true
        focusedField = nil

        Task {
            do {
                let session: SupabaseSession
                if isSignUp {
                    session = try await authService.signUpWithEmail(email: email.trimmingCharacters(in: .whitespaces),
                                                                    password: password)
                    await MainActor.run {
                        self.session = session
                        self.appleIdentifier = session.user.id
                        self.statusMessage = "Account created successfully!"
                        self.errorMessage = nil
                        self.isLoading = false
                        self.completeSessionIfNeeded()
                    }
                } else {
                    session = try await authService.signInWithEmail(email: email.trimmingCharacters(in: .whitespaces),
                                                                    password: password)
                    await MainActor.run {
                        self.session = session
                        self.appleIdentifier = session.user.id
                        self.statusMessage = "Signed in successfully!"
                        self.errorMessage = nil
                        self.isLoading = false
                        self.completeSessionIfNeeded()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = friendlyAuthMessage(for: error)
                    self.isLoading = false
                }
            }
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8),
                  let rawNonce = currentNonce else {
                errorMessage = "Unable to read Apple credential."
                return
            }
            let appleIdentifier = credential.user
            isLoading = true
            Task {
                do {
                    // Supabase expects the *raw* nonce, not the hashed one sent to Apple.
                    let session = try await authService.signInWithApple(idToken: token, nonce: rawNonce)
                    await MainActor.run {
                        self.session = session
                        self.appleIdentifier = appleIdentifier
                        self.statusMessage = "signed in as \(session.user.email ?? "your apple id")"
                        self.errorMessage = nil
                        self.isLoading = false
                        self.completeSessionIfNeeded()
                        self.currentNonce = nil
                        self.currentNonceHashed = nil
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = friendlyAuthMessage(for: error)
                        self.isLoading = false
                        self.currentNonce = nil
                        self.currentNonceHashed = nil
                    }
                }
            }
        case .failure(let error):
            if let message = appleErrorMessage(for: error) {
                errorMessage = message
            } else {
                errorMessage = nil
            }
            isLoading = false
            currentNonce = nil
            currentNonceHashed = nil
        }
    }

    private func appleErrorMessage(for error: Error) -> String? {
        guard let authError = error as? ASAuthorizationError else {
            return friendlyAuthMessage(for: error)
        }

        switch authError.code {
        case .canceled:
            return nil
        case .failed, .invalidResponse, .notHandled:
            return "Apple couldn't finish signing you in. Please try again in a moment."
        case .unknown:
            return "Apple reported an unknown issue. Please try again."
        @unknown default:
            return "We couldn't talk to Apple just now. Please try again."
        }
    }

    private func friendlyAuthMessage(for error: Error) -> String {
        print("❌ Auth error: \(error)")
        if let supabaseError = error as? SupabaseAuthError {
            let description = supabaseError.errorDescription ?? "We couldn't save your session. Please try again."
            print("❌ Supabase error description: \(description)")
            return description
        }

        if let netError = error as? NetworkError {
            switch netError {
            case .httpError(let code, let data) where code == 422:
                let body = String(data: data, encoding: .utf8)?.lowercased() ?? ""
                if body.contains("already registered") || body.contains("user already exists") {
                    return "That email is already registered. Please sign in instead."
                }
                if body.contains("password") {
                    return "Password must be at least 6 characters."
                }
                return netError.friendlyMessage
            default:
                return netError.friendlyMessage
            }
        }

        print("❌ Unknown error: \(error.localizedDescription)")
        return error.localizedDescription
    }

    @MainActor
    private func completeSessionIfNeeded() {
        guard let session = session,
              let appleIdentifier = appleIdentifier,
              !didSignalSessionCompletion else { return }
        didSignalSessionCompletion = true
        onFinished(session, appleIdentifier)
    }
}

private struct OnboardingTextView: View {
    let page: OnboardingPage
    let size: CGSize
    let theme: PaletteTheme

    var body: some View {
        let scaleX = Layout.scaleX(for: size)
        let scaleY = Layout.scaleY(for: size)

        ZStack {
            VStack(spacing: 8) {
                Text(page.title)
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .tracking(0.3)

                Text(page.subtitle)
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260 * scaleX)
            }
            .position(x: size.width * 0.5 + Layout.titleXOffset * scaleX,
                      y: Layout.titleY * scaleY)
        }
    }
}

private struct InteractiveHero: View {
    let imageName: String
    let dimmed: Bool
    let action: () -> Void
    let scale: CGFloat

    @State private var isPressed = false

    var body: some View {
        let heroSize = 260 * scale
        let hitInset = max(CGFloat(0), heroSize * 0.22)   // shrink tap area so transparent edges don't steal taps

        VStack(spacing: 0) {
            GIFImage(name: imageName)
                .frame(width: heroSize, height: heroSize)
                .scaleEffect(isPressed ? 0.97 : 1.0)

            Ellipse()
                .fill(
                    LinearGradient(colors: [
                        Palette.peach.opacity(dimmed ? 0.12 : 0.28),
                        Palette.cream.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom)
                )
                .frame(width: 220, height: 32)
                .blur(radius: 2.5)
        }
        .contentShape(Rectangle().inset(by: hitInset))
        .onTapGesture {
            guard !isPressed else { return }
            hapticSoft()
            action()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    isPressed = false
                }
            }
        }
    }
}

struct CozyDecorLayer: View {
    let size: CGSize
    let theme: PaletteTheme
    let isLightsOut: Bool
    let allowInteractions: Bool
    let lightAction: (() -> Void)?
    let waterAction: (() -> Void)?
    let playAction: (() -> Void)?
    let plantAction: (() -> Void)?
    let loveboxAction: (() -> Void)?
    let tvAction: (() -> Void)?
    let galleryAction: (() -> Void)?
    let windowAction: (() -> Void)?
    let giftAction: (() -> Void)?
    let waterEnabled: Bool
    let playEnabled: Bool
    let plantEnabled: Bool
    let decorPlacement: DecorPlacement
    let heroAction: (() -> Void)?
    let heroAllowsInteraction: Bool?
    let userName: String?
    let partnerName: String?
    let togetherSince: Date?

    init(size: CGSize,
         theme: PaletteTheme,
         isLightsOut: Bool,
        allowInteractions: Bool,
        lightAction: (() -> Void)?,
        waterAction: (() -> Void)? = nil,
        playAction: (() -> Void)? = nil,
        plantAction: (() -> Void)? = nil,
        loveboxAction: (() -> Void)? = nil,
        tvAction: (() -> Void)? = nil,
        galleryAction: (() -> Void)? = nil,
        windowAction: (() -> Void)? = nil,
        giftAction: (() -> Void)? = nil,
         waterEnabled: Bool = true,
         playEnabled: Bool = true,
         plantEnabled: Bool = true,
         decorPlacement: DecorPlacement = .onboarding,
         heroAction: (() -> Void)? = nil,
         heroAllowsInteraction: Bool? = nil,
         userName: String? = nil,
         partnerName: String? = nil,
         togetherSince: Date? = nil) {
            self.size = size
            self.theme = theme
            self.isLightsOut = isLightsOut
            self.allowInteractions = allowInteractions
            self.lightAction = lightAction
            self.waterAction = waterAction
            self.playAction = playAction
            self.plantAction = plantAction
            self.loveboxAction = loveboxAction
            self.tvAction = tvAction
            self.galleryAction = galleryAction
            self.windowAction = windowAction
            self.giftAction = giftAction
            self.decorPlacement = decorPlacement
            self.heroAction = heroAction
            self.heroAllowsInteraction = heroAllowsInteraction
            self.waterEnabled = waterEnabled
            self.playEnabled = playEnabled
            self.plantEnabled = plantEnabled
            self.userName = userName
            self.partnerName = partnerName
            self.togetherSince = togetherSince
        }

    var body: some View {
        let scaleX = Layout.scaleX(for: size)
        let scaleY = Layout.scaleY(for: size)
        // Apply automatic shrinking for small devices (like iPhone SE)
        let scale = min(scaleX, scaleY) * Layout.smallDeviceScale(for: size)
        let heroScale = Layout.heroScale(for: size)

        // Detect iPad / wider devices
        let isTablet = UIDevice.current.userInterfaceIdiom == .pad

        // Keep original phone behavior, adjust only for tablets
        let baseFloorY = Layout.floorY(for: size) + decorPlacement.floorYOffset
        let floorY: CGFloat = isTablet ? size.height * 0.84 : baseFloorY

        // Vertical lift only on phones; on tablets we keep things grounded
        let yLift: CGFloat = isTablet ? 0 : Layout.yLift(for: size)

        // Unified offsets for ground objects; use scale on phone, not on tablet
        let plantOffset = isTablet ? decorPlacement.plantOffsetFromFloor : decorPlacement.plantOffsetFromFloor * scale
        let waterOffset = isTablet ? decorPlacement.waterOffsetFromFloor : decorPlacement.waterOffsetFromFloor * scale
        let toysOffset  = isTablet ? decorPlacement.toysOffsetFromFloor  : decorPlacement.toysOffsetFromFloor * scale
        let heroOffset  = isTablet ?
            decorPlacement.heroOffsetFromFloor :
            decorPlacement.heroOffsetFromFloor * scale * Layout.heroOffsetBoost(for: size)
        let propDrop = Layout.smallPropDrop(for: size)
        let waterInteractable = allowInteractions && waterEnabled
        let playInteractable = allowInteractions && playEnabled
        let plantInteractable = allowInteractions && plantEnabled

        ZStack {
            Rectangle()
                .fill(Color(red: 0.996, green: 0.909, blue: 0.749)) // #fee7bf
                .ignoresSafeArea()
                .colorMultiply(isLightsOut ? Color(red: 0.5, green: 0.45, blue: 0.4) : .white)
                .overlay(
                    CozyAmbientBackground(isLightsOut: isLightsOut)
                        .blendMode(.screen)
                        .opacity(isLightsOut ? 0.55 : 0.35)
                )

            if isLightsOut {
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)

                RadialGradient(colors: [Color.black.opacity(0.45), Color.clear],
                               center: .center,
                               startRadius: 10,
                               endRadius: 420)
                    .ignoresSafeArea()
                    .blendMode(.multiply)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Floor behind everything else
            InteractiveProp(imageName: "floor",
                            width: size.width * decorPlacement.floorWidthFactor,
                            xOffset: 0,
                            y: floorY,
                            baseWidth: size.width,
                            theme: theme,
                            action: { hapticSoft() },
                            isEnabled: false)
            .allowsHitTesting(false)

            // Decorative props above floor
            InteractiveProp(imageName: "plant",
                            width: decorPlacement.plantWidth * scale,
                            xOffset: decorPlacement.plantXOffset * scaleX,
                            y: floorY - plantOffset - yLift + propDrop + (isTablet ? Layout.floorVisualPadding : 0),
                            baseWidth: size.width,
                            theme: theme,
                            action: {
                                if let plantAction {
                                    plantAction()
                                } else {
                                    hapticSoft()
                                }
                            },
                            isEnabled: plantInteractable)
            .allowsHitTesting(plantInteractable)
            .zIndex(1)

            InteractiveProp(imageName: "lovebox",
                            width: decorPlacement.loveboxWidth * scale,
                            xOffset: decorPlacement.loveboxXOffset * scaleX,
                            y: decorPlacement.loveboxY * scale,
                            baseWidth: size.width,
                            theme: theme,
                            action: { loveboxAction?() },
                            isEnabled: allowInteractions && loveboxAction != nil)

            InteractiveProp(imageName: "tv",
                            width: decorPlacement.tvWidth * scale,
                            xOffset: decorPlacement.tvXOffset * scaleX,
                            y: decorPlacement.tvY * scale + propDrop,
                            baseWidth: size.width,
                            theme: theme,
                            action: {
                                if let tvAction {
                                    tvAction()
                                } else {
                                    hapticSoft()
                                }
                            },
                            isEnabled: allowInteractions && tvAction != nil)
            .allowsHitTesting(allowInteractions && tvAction != nil)

            InteractiveProp(imageName: "water",
                            width: decorPlacement.waterWidth * scale,
                            xOffset: decorPlacement.waterXOffset * scaleX,
                            y: floorY - waterOffset - yLift + propDrop + (isTablet ? Layout.floorVisualPadding : 0),
                            baseWidth: size.width,
                            theme: theme,
                            action: {
                                if let waterAction {
                                    waterAction()
                                } else {
                                    hapticSoft()
                                }
                            },
                            isEnabled: waterInteractable)
            .allowsHitTesting(waterInteractable)
            .zIndex(2)

            InteractiveProp(imageName: "gallery",
                            width: decorPlacement.galleryWidth * scale,
                            xOffset: decorPlacement.galleryXOffset * scaleX,
                            y: decorPlacement.galleryY * scale,
                            baseWidth: size.width,
                            theme: theme,
                            action: { galleryAction?() },
                            isEnabled: allowInteractions && galleryAction != nil)

            InteractiveProp(imageName: "toys",
                            width: decorPlacement.toysWidth * scale,
                            xOffset: decorPlacement.toysXOffset * scaleX,
                            y: floorY - toysOffset + propDrop + (isTablet ? Layout.floorVisualPadding : 0),
                            baseWidth: size.width,
                            theme: theme,
                            action: {
                                if let playAction {
                                    playAction()
                                } else {
                                    hapticSoft()
                                }
                            },
                            isEnabled: playInteractable)
            .allowsHitTesting(playInteractable)
            .zIndex(3)

            InteractiveProp(imageName: "sofa",
                            width: decorPlacement.sofaWidth * scale,
                            xOffset: decorPlacement.sofaXOffset * scaleX,
                            y: floorY - decorPlacement.sofaOffsetFromFloor + (isTablet ? Layout.floorVisualPadding : 0),
                            baseWidth: size.width,
                            theme: theme,
                            action: { hapticSoft() },
                            isEnabled: false)
            .allowsHitTesting(false)

            InteractiveProp(imageName: "gift",
                            width: decorPlacement.giftWidth * scale,
                            xOffset: decorPlacement.giftXOffset * scaleX,
                            y: decorPlacement.giftY * scale,
                            baseWidth: size.width,
                            theme: theme,
                            action: { giftAction?() },
                            isEnabled: allowInteractions && giftAction != nil)
            .allowsHitTesting(allowInteractions && giftAction != nil)
            .zIndex(4)

            InteractiveProp(imageName: "window",
                            width: decorPlacement.windowWidth * scale,
                            xOffset: decorPlacement.windowXOffset * scaleX,
                            y: decorPlacement.windowY * scale,
                            baseWidth: size.width,
                            theme: theme,
                            action: {
                                hapticSoft()
                                windowAction?()
                            },
                            isEnabled: allowInteractions && windowAction != nil)
            .allowsHitTesting(allowInteractions && windowAction != nil)

            InteractiveHero(imageName: "bubba",
                            dimmed: isLightsOut,
                            action: {
                                heroAction?()
                            },
                            scale: heroScale)
                .position(x: size.width * 0.5 + decorPlacement.heroXOffset * scaleX,
                          y: floorY - heroOffset + (isTablet ? Layout.floorVisualPadding : 0))
            .zIndex(6)
            .allowsHitTesting(heroAllowsInteraction ?? allowInteractions)

            // Couple names and anniversary display
            if let userName = userName, let partnerName = partnerName {
                let userInitial = userName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()
                let partnerInitial = partnerName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()
                VStack(spacing: 6) {
                    // Couple names with heart
                    HStack(spacing: 6) {
                        Text(userInitial)
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(isLightsOut ? Color.white : theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Image(systemName: "heart.fill")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(Color.pink.opacity(isLightsOut ? 0.9 : 1.0))
                            .fixedSize()

                        Text(partnerInitial)
                            .font(.system(.title3, weight: .semibold))
                            .foregroundStyle(isLightsOut ? Color.white : theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: size.width * 0.8)

                    // Days together
                    if let togetherSince = togetherSince {
                        let daysTogether = Calendar.current.dateComponents([.day], from: togetherSince, to: Date()).day ?? 0
                        Text("\(daysTogether) days together")
                            .font(.system(.callout, weight: .medium))
                            .foregroundStyle(isLightsOut ? Color.white.opacity(0.8) : theme.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: size.width * 0.85)
                .position(x: size.width * 0.5, y: size.height * 0.56)
                .zIndex(100)
            }
        }
    }
}

struct PageDots: View {
    let currentIndex: Int
    let total: Int
    let theme: PaletteTheme

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? theme.dotActive : theme.dotInactive)
                    .frame(width: index == currentIndex ? 10 : 8, height: index == currentIndex ? 10 : 8)
            }
        }
        .padding(.bottom, 6)
    }
}

private struct InteractiveProp: View {
    let imageName: String
    let width: CGFloat
    let xOffset: CGFloat
    let y: CGFloat
    let baseWidth: CGFloat
    let theme: PaletteTheme
    let action: () -> Void
    let isEnabled: Bool

    @State private var isPressed = false

    init(imageName: String,
         width: CGFloat,
         xOffset: CGFloat,
         y: CGFloat,
         baseWidth: CGFloat,
         theme: PaletteTheme,
         action: @escaping () -> Void,
         isEnabled: Bool = true) {
        self.imageName = imageName
        self.width = width
        self.xOffset = xOffset
        self.y = y
        self.baseWidth = baseWidth
        self.theme = theme
        self.action = action
        self.isEnabled = isEnabled
    }

    var body: some View {
        Button(action: handleTap) {
            Image(imageName)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: width, height: width)
                .scaleEffect(isPressed ? 0.94 : 1.0)
                .shadow(color: theme.shadowColor.opacity(isPressed ? 0.18 : 0.26),
                        radius: isPressed ? 6 : 10,
                        y: isPressed ? 3 : 6)
        }
        .buttonStyle(.plain)
        .frame(width: width, height: width)
        .contentShape(Rectangle())
        .position(x: baseWidth * 0.5 + xOffset, y: y)
    }

    private func handleTap() {
        guard isEnabled else { return }
        hapticSoft()
        action()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
            isPressed = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isPressed = false
            }
        }
    }
}

private struct FeatureBadge: View {
    let title: String
    let icon: String
    let theme: PaletteTheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(.caption, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(theme.textPrimary)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            Capsule().fill(theme.buttonFill.opacity(0.18))
        )
    }
}

private struct FeatureHighlightGrid: View {
    let features: [AuthFeature]
    let theme: PaletteTheme

    private let columns = [
        GridItem(.adaptive(minimum: 90), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(features) { feature in
                FeatureBadge(title: feature.title, icon: feature.icon, theme: theme)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AuthFeature: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
}

private struct StatusToast: View {
    let text: String
    let theme: PaletteTheme
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(color)
            Text(text)
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(theme.textPrimary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.65))
                .shadow(color: color.opacity(0.25), radius: 10, y: 6)
        )
        .padding(.horizontal, 24)
    }
}

/// Soft animated blobs floating in the background for a cozy mood.
private struct CozyAmbientBackground: View {
    let isLightsOut: Bool

    private let paletteLight: [Color] = [
        Palette.peach.opacity(0.18),
        Palette.sunGlow.opacity(0.14),
        Palette.cream.opacity(0.18)
    ]

    private let paletteDark: [Color] = [
        Color(red: 1.0, green: 0.85, blue: 0.65).opacity(0.24),
        Color(red: 0.92, green: 0.72, blue: 0.55).opacity(0.2),
        Color(red: 0.74, green: 0.56, blue: 0.46).opacity(0.2)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let colors = isLightsOut ? paletteDark : paletteLight

                for i in 0..<6 {
                    let progress = time / Double(18 + i * 2)
                    let phase = CGFloat(progress.truncatingRemainder(dividingBy: 1.0))

                    let baseX = size.width * (0.15 + CGFloat(i) * 0.15)
                    let baseY = size.height * (0.15 + CGFloat(i % 3) * 0.25)

                    let floatX = baseX + sin(phase * .pi * 2) * 26
                    let floatY = baseY + cos(phase * .pi * 2) * 32
                    let blobSize = CGFloat(120 + (i * 15))

                    let rect = CGRect(x: floatX, y: floatY, width: blobSize, height: blobSize)
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    let path = Path(ellipseIn: rect)
                    context.fill(path, with: .radialGradient(
                        .init(colors: [colors[i % colors.count], .clear]),
                        center: center,
                        startRadius: 10,
                        endRadius: blobSize * 0.7))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct LightButton: View {
    let theme: PaletteTheme
    let baseWidth: CGFloat
    let offsetScaleX: CGFloat
    let offsetScaleY: CGFloat
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            Image("light")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: Layout.lightWidth, height: Layout.lightWidth)
                .shadow(color: theme.shadowColor.opacity(0.35), radius: 6, y: 4)
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .frame(width: Layout.lightWidth, height: Layout.lightWidth)
        .contentShape(Rectangle())
        .position(x: baseWidth * 0.5 + Layout.lightXOffset * offsetScaleX,
                  y: Layout.lightY * offsetScaleY)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        isPressed = false
                    }
                }
        )
        .highPriorityGesture(
            TapGesture().onEnded {
                hapticSoft()
            }
        )
    }
}

private final class SupabaseAuthService {
    static let shared = SupabaseAuthService()

    private let projectURL = URL(string: "https://ahtkqcaxeycxvwntjcxp.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFodGtxY2F4ZXljeHZ3bnRqY3hwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ1MDI3MDQsImV4cCI6MjA4MDA3ODcwNH0.cyIkcEN6wd71cis85jAOCMHrx8RoHbuMuUOvi_b10SI"
    private let clientId = "com.anthony.lovablee"
    private let usersTablePath = "rest/v1/users"
    private let storageBucketPath = "storage"

    var publicProjectURL: URL { projectURL }
    var publicAnonKey: String { anonKey }

    private func validateResponse(_ data: Data,
                                  _ response: URLResponse,
                                  successRange: Range<Int> = 200..<300) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseAuthError.unknown
        }

        // Debug 5xx responses with raw body and URL for easier diagnosis.
        if httpResponse.statusCode >= 500 {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            let urlString = httpResponse.url?.absoluteString ?? "<no url>"
            print("🚨 Supabase 5xx (\(httpResponse.statusCode)) for \(urlString)")
            print("🚨 Body (\(data.count) bytes): \(raw)")
        }

        // Treat 401 and 400 as unauthorized (400 often returned for expired refresh tokens)
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 400 {
            let message = String(data: data, encoding: .utf8) ?? "Your session expired. Please sign in again."
            // Check if it's an auth-related error
            if message.lowercased().contains("token") || message.lowercased().contains("session") || message.lowercased().contains("unauthorized") || httpResponse.statusCode == 401 {
                throw SupabaseAuthError.unauthorized(message)
            }
        }

        // Some Supabase gateways return 500 for expired/invalid JWTs. Detect and treat as unauthorized.
        if httpResponse.statusCode == 500 {
            let lower = (String(data: data, encoding: .utf8) ?? "").lowercased()
            if lower.contains("jwt") || lower.contains("token") || lower.contains("session") {
                throw SupabaseAuthError.unauthorized(lower.isEmpty ? "Session expired. Please sign in again." : lower)
            }
        }

        guard successRange.contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown Supabase error"
            print("❌ Supabase error response (status \(httpResponse.statusCode)):")
            print("   Raw response: \(message)")

            // Try to parse JSON error message
            if let jsonData = message.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                print("   Parsed JSON: \(json)")
                let rawError = json["error_description"] as? String ?? json["message"] as? String ?? json["msg"] as? String ?? json["hint"] as? String
                let details = json["details"] as? String
                let picked = rawError ?? details
                if let picked {
                    print("   Error message: \(picked)")

                    // Friendly mapping for common auth/signup issues (422).
                    if httpResponse.statusCode == 422 {
                        let lower = picked.lowercased()
                        if lower.contains("already registered") || lower.contains("user already exists") {
                            throw SupabaseAuthError.emailInUse
                        }
                        if lower.contains("password") {
                            throw SupabaseAuthError.weakPassword
                        }
                    }

                    throw SupabaseAuthError.server(picked)
                }
            }

            throw SupabaseAuthError.server(message)
        }
        return httpResponse
    }

    func signInWithApple(idToken: String, nonce: String) async throws -> SupabaseSession {
        var components = URLComponents(url: projectURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let payload = SupabaseApplePayload(provider: "apple",
                                           clientId: clientId,
                                           idToken: idToken,
                                           nonce: nonce)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SupabaseSession.self, from: data)
    }

    func signUpWithEmail(email: String, password: String) async throws -> SupabaseSession {
        var request = URLRequest(url: projectURL.appendingPathComponent("auth/v1/signup"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: String] = [
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // Try to decode as a full session first (when email confirmation is disabled)
        if let session = try? decoder.decode(SupabaseSession.self, from: data) {
            return session
        }

        // If that fails, it means email confirmation is required
        // Parse the response to check
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("📧 Signup response: \(json)")

            // Check if there's a user but no session (confirmation required)
            if let _ = json["id"] as? String {
                throw SupabaseAuthError.server("Please check your email to confirm your account, then sign in.")
            }
        }

        throw SupabaseAuthError.server("Signup failed. Please try again.")
    }

    func signInWithEmail(email: String, password: String) async throws -> SupabaseSession {
        var components = URLComponents(url: projectURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let payload: [String: String] = [
            "email": email,
            "password": password
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SupabaseSession.self, from: data)
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        var components = URLComponents(url: projectURL.appendingPathComponent("auth/v1/token"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SupabaseSession.self, from: data)
    }

    func registerUser(session: SupabaseSession,
                      appleIdentifier: String,
                      email: String?,
                      displayName: String,
                      apnsToken: String?) async throws -> SupabaseUserRegistrationResult {
        print("📝 Registering user: id=\(session.user.id), appleId=\(appleIdentifier), email=\(email ?? "nil"), name=\(displayName)")

        var request = URLRequest(url: projectURL.appendingPathComponent(usersTablePath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let record = SupabaseUserRecord(id: session.user.id,
                                        email: email,
                                        appleIdentifier: appleIdentifier,
                                        displayName: displayName,
                                        apnsToken: apnsToken)

        if let jsonString = String(data: try JSONEncoder().encode(record), encoding: .utf8) {
            print("📤 Sending user record: \(jsonString)")
        }
        request.httpBody = try JSONEncoder().encode(record)

        let (data, response) = try await NetworkService.shared.performRequest(request)

        print("📥 Got response, validating...")
        _ = try validateResponse(data, response)

        print("✅ User registration request successful")

        let decoder = JSONDecoder()
        let records = try decoder.decode([SupabaseUserRegistrationResult].self, from: data)
        if let record = records.first,
           !(record.pairingCode?.isEmpty ?? true) {
            return record
        }
        guard let fallback = try await fetchUserRecord(id: session.user.id,
                                                       accessToken: session.accessToken) else {
            throw SupabaseAuthError.unknown
        }
        return fallback
    }

    func signOut(session: SupabaseSession) async throws {
        var request = URLRequest(url: projectURL.appendingPathComponent("auth/v1/logout"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response, successRange: 200..<400)
    }

    func deleteUserAccount(session: SupabaseSession) async throws {
        var components = URLComponents(url: projectURL.appendingPathComponent(usersTablePath),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(session.user.id)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
    }

    func fetchUserRecord(id: String, accessToken: String) async throws -> SupabaseUserRegistrationResult? {
        var components = URLComponents(url: projectURL.appendingPathComponent(usersTablePath),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        let decoder = JSONDecoder()
        let records = try decoder.decode([SupabaseUserRegistrationResult].self, from: data)
        return records.first
    }

    func fetchPetStatus(session: SupabaseSession) async throws -> SupabasePetStatus {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/get_pet_status"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SupabasePetStatus.self, from: data)
    }

    func fetchCoupleActivity(session: SupabaseSession,
                             limit: Int = 50) async throws -> [SupabaseActivityItem] {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/get_couple_activity"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload = ActivityRequest(pLimit: limit)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SupabaseActivityItem].self, from: data)
    }

    func performPetAction(session: SupabaseSession,
                          action: PetActionType) async throws -> SupabasePetStatus {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/record_pet_action"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload = PetActionRequest(actionType: action.rawValue)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(payload)

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SupabasePetStatus.self, from: data)
    }

    func updatePetName(session: SupabaseSession, petName: String) async throws -> SupabasePetStatus {
        var components = URLComponents(url: projectURL.appendingPathComponent("rest/v1/pet_status"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(session.user.id)")
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let now = ISO8601DateFormatter().string(from: Date())
        let body: [String: Any] = [
            "pet_name": petName,
            "updated_at": now
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([SupabasePetStatus].self, from: data)
        if let updated = rows.first {
            return updated
        }
        throw SupabaseAuthError.unknown
    }

    func joinPartner(session: SupabaseSession, pairingCode: String) async throws -> SupabaseUserRegistrationResult {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/join_partner"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload = ["p_pairing_code": pairingCode.uppercased()]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SupabaseUserRegistrationResult.self, from: data)
    }

    func leavePartner(session: SupabaseSession) async throws -> SupabaseUserRegistrationResult {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/leave_partner"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SupabaseUserRegistrationResult.self, from: data)
    }

    func sendLoveNote(session: SupabaseSession, message: String) async throws -> LoveNote {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/send_love_note"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload = ["p_message": message]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoveNote.self, from: data)
    }

    func getLoveNotes(session: SupabaseSession, limit: Int = 50) async throws -> [LoveNote] {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/get_love_notes"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload = ["p_limit": limit]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([LoveNote].self, from: data)
    }

    func uploadDoodleImage(session: SupabaseSession, imageData: Data) async throws -> String {
        let fileName = "\(UUID().uuidString).png"
        let path = "storage/v1/object/\(storageBucketPath)/doodles/\(fileName)"
        print("📤 Uploading to path: \(path)")
        print("📤 Full URL: \(projectURL.appendingPathComponent(path))")

        var request = URLRequest(url: projectURL.appendingPathComponent(path))
        request.httpMethod = "PUT"
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.upload(for: request, from: imageData)

        if let httpResponse = response as? HTTPURLResponse {
            print("📤 Upload response status: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("📤 Upload response body: \(responseString)")
            }
        }

        _ = try validateResponse(data, response)
        let storagePath = "doodles/\(fileName)"
        print("📤 Returning storage path: \(storagePath)")
        return storagePath
    }

    func saveDoodle(session: SupabaseSession, content: String) async throws -> Doodle {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/save_doodle"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload = ["p_content": content, "p_storage_path": NSNull()] as [String : Any]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Doodle.self, from: data)
    }

    func getDoodles(session: SupabaseSession, limit: Int = 50) async throws -> [Doodle] {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/get_doodles"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload = ["p_limit": limit]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Doodle].self, from: data)
    }

    func publishLiveDoodle(session: SupabaseSession,
                           senderName: String?,
                           contentBase64: String) async throws {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/publish_live_doodle"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let body: [String: Any?] = [
            "p_content_base64": contentBase64,
            "p_sender_name": senderName
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
    }

    func fetchLatestLiveDoodle(session: SupabaseSession,
                               excludeSenderId: String?) async throws -> LiveDoodle? {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/fetch_latest_live_doodle"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let body: [String: Any?] = [
            "p_exclude_sender": excludeSenderId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        // Prefer strict decode; fall back to manual parsing so we never silently drop a valid record.
        let decoder = JSONDecoder.liveDoodle
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let doodle = try? decoder.decode(LiveDoodle?.self, from: data) {
            return doodle
        }

        // Manual fallback to survive format drift (e.g., timestamps).
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return LiveDoodleParser.parse(json: json)
    }

    func getCoupleKey(session: SupabaseSession) async throws -> String? {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/get_couple_key"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
    }

    func getCouplePremiumStatus(session: SupabaseSession) async throws -> (isPremium: Bool, premiumUntil: Date?) {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/get_couple_premium_status"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (false, nil) }

        let isPremium: Bool = {
            if let b = json["is_premium"] as? Bool { return b }
            if let s = json["is_premium"] as? String { return ["true", "t", "1"].contains(s.lowercased()) }
            return false
        }()

        let premiumUntil: Date? = {
            guard let untilString = json["premium_until"] as? String else { return nil }
            if let iso = ISO8601DateFormatter().date(from: untilString) { return iso }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
            if let d = formatter.date(from: untilString) { return d }
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter.date(from: untilString)
        }()
        return (isPremium, premiumUntil)
    }

    func setPremiumStatus(session: SupabaseSession,
                          premiumUntil: Date?,
                          premiumSource: String?) async throws {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/set_premium_status"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let iso = ISO8601DateFormatter()
        let payload: [String: Any?] = [
            "p_premium_until": premiumUntil.map { iso.string(from: $0) } ?? NSNull(),
            "p_premium_source": premiumSource
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
    }

    func sendGift(session: SupabaseSession, giftType: String, message: String) async throws -> PurchasedGift {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/send_gift"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "p_gift_type": giftType,
            "p_message": message.isEmpty ? NSNull() : message
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PurchasedGift.self, from: data)
    }

    func getGifts(session: SupabaseSession) async throws -> [PurchasedGift] {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/load_couple_gifts"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [:]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PurchasedGift].self, from: data)
    }

    func markGiftAsOpened(session: SupabaseSession, giftId: UUID) async throws {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/mark_gift_opened"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = ["p_gift_id": giftId.uuidString]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
    }

    func loadAnniversaries(session: SupabaseSession) async throws -> (togetherSince: Date?, customAnniversaries: [Anniversary]) {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/load_anniversaries"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = "{}".data(using: .utf8)

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        guard let result = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = result.first else {
            return (nil, [])
        }

        let togetherSince: Date? = {
            guard let dateString = first["together_since"] as? String else { return nil }
            return ISO8601DateFormatter().date(from: dateString)
        }()

        let customAnniversaries: [Anniversary] = {
            guard let customJSON = first["custom_anniversaries"] as? [[String: Any]] else { return [] }
            return customJSON.compactMap { dict in
                guard let idString = dict["id"] as? String,
                      let id = UUID(uuidString: idString),
                      let name = dict["name"] as? String,
                      let dateString = dict["date"] as? String,
                      let date = ISO8601DateFormatter().date(from: dateString) else {
                    return nil
                }
                return Anniversary(id: id, name: name, date: date)
            }
        }()

        return (togetherSince, customAnniversaries)
    }

    func setTogetherSince(session: SupabaseSession, date: Date) async throws {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/set_together_since"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let dateString = ISO8601DateFormatter().string(from: date)
        let payload: [String: Any] = ["p_date": dateString]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
    }

    func addCustomAnniversary(session: SupabaseSession, name: String, date: Date) async throws -> Anniversary {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/add_custom_anniversary"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let dateString = ISO8601DateFormatter().string(from: date)
        let payload: [String: Any] = ["p_name": name, "p_date": dateString]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let returnedName = dict["name"] as? String,
              let dateString = dict["anniversary_date"] as? String,
              let returnedDate = ISO8601DateFormatter().date(from: dateString) else {
            throw SupabaseAuthError.server("Failed to decode anniversary response")
        }

        return Anniversary(id: id, name: returnedName, date: returnedDate)
    }

    func deleteCustomAnniversary(session: SupabaseSession, id: UUID) async throws {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/custom_anniversaries"))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("id=eq.\(id.uuidString)", forHTTPHeaderField: "Prefer")

        var components = URLComponents(url: projectURL.appendingPathComponent("rest/v1/custom_anniversaries"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]
        guard let url = components?.url else { throw SupabaseAuthError.server("Invalid URL for delete request") }
        request.url = url

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)
    }

    func loadDailyMoods(session: SupabaseSession, date: Date) async throws -> MoodPair {
        let dayString = Self.localDayString(for: date)

        do {
            return try await fetchMoodPairFromTable(session: session, dayString: dayString)
        } catch {
            print("⚠️ Mood table fetch failed, falling back to RPC: \(error)")
        }

        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/load_daily_moods"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload = ["p_local_date": dayString]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let pair = try? decoder.decode(MoodPair.self, from: data) {
            return pair
        }
        if let pairs = try? decoder.decode([MoodPair].self, from: data),
           let first = pairs.first {
            return first
        }
        // Fallback: decode from raw JSON object/array
        if let json = try? JSONSerialization.jsonObject(with: data) {
            if let dict = json as? [String: Any],
               let dictData = try? JSONSerialization.data(withJSONObject: dict),
               let pair = try? decoder.decode(MoodPair.self, from: dictData) {
                return pair
            }
            if let arr = json as? [[String: Any]],
               let first = arr.first,
               let firstData = try? JSONSerialization.data(withJSONObject: first),
               let pair = try? decoder.decode(MoodPair.self, from: firstData) {
                return pair
            }

            // Manual fallback to parse loose JSON shapes
            let parse: (Any) -> MoodEntry? = { value in
                Self.decodeMoodEntry(from: value, fallbackDate: date, fallbackUserId: session.user.id)
            }
            if let dict = json as? [String: Any] {
                let my = parse(dict["my_mood"] as Any)
                let partner = parse(dict["partner_mood"] as Any)
                return MoodPair(myMood: my, partnerMood: partner)
            }
            if let arr = json as? [[String: Any]], let first = arr.first {
                let my = parse(first["my_mood"] as Any)
                let partner = parse(first["partner_mood"] as Any)
                return MoodPair(myMood: my, partnerMood: partner)
            }
        }
        return MoodPair(myMood: nil, partnerMood: nil)
    }

    private func fetchMoodPairFromTable(session: SupabaseSession,
                                        dayString: String) async throws -> MoodPair {
        var components = URLComponents(
            url: projectURL.appendingPathComponent("rest/v1/user_moods"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "mood_date", value: "eq.\(dayString)"),
            URLQueryItem(name: "order", value: "updated_at.desc"),
            URLQueryItem(
                name: "select",
                value: "id,user_id,mood_key,emoji,label,mood_date,created_at,updated_at"
            )
        ]
        guard let url = components?.url else {
            throw SupabaseAuthError.server("Invalid URL for mood fetch")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        let entries = try Self.decodeMoodEntries(
            from: data,
            fallbackDate: DateFormatter.yearMonthDay.date(from: dayString) ?? Date(),
            fallbackUserId: session.user.id
        )

        if entries.isEmpty {
            return MoodPair(myMood: nil, partnerMood: nil)
        }

        let myMood = entries.first(where: { $0.userId == session.user.id })
        let partnerMood = entries.first(where: { $0.userId != session.user.id })
        return MoodPair(myMood: myMood, partnerMood: partnerMood)
    }

    private static func decodeMoodEntries(from data: Data,
                                          fallbackDate: Date,
                                          fallbackUserId: String) throws -> [MoodEntry] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let entries = try? decoder.decode([MoodEntry].self, from: data) {
            return entries
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw SupabaseAuthError.server("Failed to decode mood response")
        }

        if let arr = json as? [Any] {
            return arr.compactMap { decodeMoodEntry(from: $0,
                                                    fallbackDate: fallbackDate,
                                                    fallbackUserId: fallbackUserId) }
        }
        if let dict = json as? [String: Any],
           let entry = decodeMoodEntry(from: dict,
                                       fallbackDate: fallbackDate,
                                       fallbackUserId: fallbackUserId) {
            return [entry]
        }
        return []
    }

    func setMood(session: SupabaseSession,
                 option: MoodOption,
                 date: Date) async throws -> MoodEntry {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/set_mood"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = [
            "p_mood_key": option.key,
            "p_emoji": option.emoji,
            "p_label": option.title,
            "p_local_date": Self.localDayString(for: date)
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await NetworkService.shared.performRequest(request)
        _ = try validateResponse(data, response)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let single = try? decoder.decode(MoodEntry.self, from: data) {
            return single
        }
        if let rows = try? decoder.decode([MoodEntry].self, from: data),
           let first = rows.first {
            return first
        }
        // Fallback: parse JSON manually
        if let json = try? JSONSerialization.jsonObject(with: data) {
            var dict: [String: Any]?
            if let raw = json as? [String: Any] {
                dict = raw
            } else if let arr = json as? [[String: Any]], let first = arr.first {
                dict = first
            }
            if let dict {
                let id = UUID(uuidString: dict["id"] as? String ?? "") ?? UUID()
                let userId = (dict["user_id"] as? String) ?? session.user.id
                let moodKey = (dict["mood_key"] as? String) ?? option.key
                let emoji = dict["emoji"] as? String
                let label = dict["label"] as? String
                let moodDateString = dict["mood_date"] as? String ?? DateFormatter.yearMonthDay.string(from: date)
                let moodDate = DateFormatter.yearMonthDay.date(from: moodDateString) ??
                    ISO8601DateFormatter().date(from: moodDateString) ??
                    date
                let createdAtString = dict["created_at"] as? String
                let updatedAtString = dict["updated_at"] as? String
                let createdAt = createdAtString.flatMap { ISO8601DateFormatter().date(from: $0) }
                let updatedAt = updatedAtString.flatMap { ISO8601DateFormatter().date(from: $0) }
                return MoodEntry(
                    id: id,
                    userId: userId,
                    moodKey: moodKey,
                    emoji: emoji,
                    label: label,
                    moodDate: moodDate,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                )
            }
        }
        throw SupabaseAuthError.server("Failed to decode mood response")
    }

    private static func localDayString(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func decodeMoodEntry(from raw: Any,
                                        fallbackDate: Date,
                                        fallbackUserId: String) -> MoodEntry? {
        guard let dict = raw as? [String: Any] else { return nil }
        let id = UUID(uuidString: dict["id"] as? String ?? "") ?? UUID()
        let userId = (dict["user_id"] as? String)
            ?? (dict["userId"] as? String)
            ?? fallbackUserId
        let moodKey = (dict["mood_key"] as? String)
            ?? (dict["moodKey"] as? String)
            ?? "unknown"
        let emoji = dict["emoji"] as? String
        let label = dict["label"] as? String
        let moodDateString = (dict["mood_date"] as? String)
            ?? (dict["moodDate"] as? String)
            ?? localDayString(for: fallbackDate)
        let moodDate = DateFormatter.yearMonthDay.date(from: moodDateString)
            ?? ISO8601DateFormatter().date(from: moodDateString)
            ?? fallbackDate

        let createdAtString = dict["created_at"] as? String ?? dict["createdAt"] as? String
        let createdAt = createdAtString.flatMap { ISO8601DateFormatter().date(from: $0) }
        let updatedAtString = dict["updated_at"] as? String ?? dict["updatedAt"] as? String
        let updatedAt = updatedAtString.flatMap { ISO8601DateFormatter().date(from: $0) }

        return MoodEntry(id: id,
                         userId: userId,
                         moodKey: moodKey,
                         emoji: emoji,
                         label: label,
                         moodDate: moodDate,
                         createdAt: createdAt,
                         updatedAt: updatedAt)
    }

    func uploadProfileImage(session: SupabaseSession, imageData: Data) async throws -> String {
        let path = "storage/v1/object/\(storageBucketPath)/profiles/\(session.user.id).jpg"
        var request = URLRequest(url: projectURL.appendingPathComponent(path))
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.upload(for: request, from: imageData)
        _ = try validateResponse(data, response)
        return UUID().uuidString
    }

    func profileImageURL(for userId: String, version: String? = nil) -> URL? {
        var components = URLComponents(url: projectURL, resolvingAgainstBaseURL: false)
        components?.path = "/storage/v1/object/public/\(storageBucketPath)/profiles/\(userId).jpg"
        if let version {
            components?.queryItems = [URLQueryItem(name: "v", value: version)]
        }
        return components?.url
    }
}

private struct SupabaseApplePayload: Encodable {
    let provider: String
    let clientId: String
    let idToken: String
    let nonce: String

    enum CodingKeys: String, CodingKey {
        case provider
        case clientId = "client_id"
        case idToken = "id_token"
        case nonce
    }
}

private struct SupabaseUserRecord: Encodable {
    let id: String
    let email: String?
    let appleIdentifier: String
    let displayName: String
    let apnsToken: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case appleIdentifier = "apple_identifier"
        case displayName = "display_name"
        case apnsToken = "apns_token"
    }
}

private struct PetActionRequest: Encodable {
    let actionType: String
}

private struct ActivityRequest: Encodable {
    let pLimit: Int
}

struct SupabaseUserRegistrationResult: Codable {
    let id: String
    let email: String?
    let displayName: String?
    let pairingCode: String?
    let partnerId: String?
    let partnerDisplayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "display_name"
        case pairingCode = "pairing_code"
        case partnerId = "partner_id"
        case partnerDisplayName = "partner_display_name"
    }
}

private struct SupabaseSession: Codable {
    struct SupabaseUser: Codable {
        let id: String
        let email: String?
    }

    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let user: SupabaseUser
}

private enum SupabaseAuthError: LocalizedError {
    case server(String)
    case unauthorized(String)
    case emailInUse
    case weakPassword
    case unknown

    var errorDescription: String? {
        switch self {
        case .server(let message):
            return "Supabase error: \(message)"
        case .unauthorized(let message):
            return message
        case .emailInUse:
            return "That email is already registered. Please sign in instead."
        case .weakPassword:
            return "Password must be at least 6 characters."
        case .unknown:
            return "Something went wrong talking to Supabase."
        }
    }
}

private final class SupabaseSessionStore {
    private let storage = UserDefaults.standard
    private let key = "lovablee.supabase.session"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    struct StoredSession: Codable {
        var session: SupabaseSession
        var appleIdentifier: String
        var displayName: String
        var userRecord: SupabaseUserRegistrationResult?
    }

    func save(session: SupabaseSession, appleIdentifier: String, displayName: String) {
        let payload = StoredSession(session: session,
                                    appleIdentifier: appleIdentifier,
                                    displayName: displayName,
                                    userRecord: nil)
        guard let data = try? encoder.encode(payload) else { return }
        storage.set(data, forKey: key)
    }

    func updateDisplayName(_ name: String) {
        guard var stored = load() else { return }
        stored.displayName = name
        guard let data = try? encoder.encode(stored) else { return }
        storage.set(data, forKey: key)
    }

    func update(session: SupabaseSession) {
        guard var stored = load() else { return }
        stored.session = session
        guard let data = try? encoder.encode(stored) else { return }
        storage.set(data, forKey: key)
    }

    func update(userRecord: SupabaseUserRegistrationResult) {
        guard var stored = load() else { return }
        stored.userRecord = userRecord
        guard let data = try? encoder.encode(stored) else { return }
        storage.set(data, forKey: key)
    }

    func load() -> StoredSession? {
        guard let data = storage.data(forKey: key) else { return nil }
        return try? decoder.decode(StoredSession.self, from: data)
    }

    func clear() {
        storage.removeObject(forKey: key)
    }
}

private enum AppleNonce {
    static func random(length: Int = 32) -> String {
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }
}

private extension String {
    func sha256() -> String {
        let inputData = Data(self.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(20)
    }
}

struct PaletteTheme {
    let textPrimary: Color
    let textMuted: Color
    let buttonFill: Color
    let shadowColor: Color
    let dotActive: Color
    let dotInactive: Color
}

enum Palette {
    static let cream = Color(red: 0.98, green: 0.93, blue: 0.83)
    static let peach = Color(red: 0.99, green: 0.88, blue: 0.75)
    static let sunGlow = Color(red: 1.0, green: 0.83, blue: 0.52)
    static let sunShadow = Color(red: 0.75, green: 0.53, blue: 0.3)
    static let textPrimary = Color(red: 0.38, green: 0.27, blue: 0.19)
    static let textMuted = Color(red: 0.54, green: 0.43, blue: 0.32)
    static let buttonFill = Color(red: 0.98, green: 0.71, blue: 0.35)

    static let lightTheme = PaletteTheme(
        textPrimary: Palette.textPrimary,
        textMuted: Palette.textMuted,
        buttonFill: Palette.buttonFill,
        shadowColor: Palette.sunShadow,
        dotActive: Palette.sunShadow.opacity(0.9),
        dotInactive: Palette.sunShadow.opacity(0.35)
    )

    static let darkTheme = PaletteTheme(
        textPrimary: Color(red: 0.996, green: 0.909, blue: 0.749), // #fee7bf
        textMuted: Color(red: 0.95, green: 0.87, blue: 0.74),
        buttonFill: Color(red: 0.98, green: 0.78, blue: 0.42),
        shadowColor: Color.black,
        dotActive: Color(red: 0.996, green: 0.909, blue: 0.749),
        dotInactive: Color(red: 0.996, green: 0.909, blue: 0.749).opacity(0.45)
    )
}

func hapticSoft() {
    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
}

func hapticLight() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

func hapticBoom() {
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
}

func hapticSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}

func hapticExtreme() {
    let heavy = UIImpactFeedbackGenerator(style: .heavy)
    heavy.impactOccurred(intensity: 1.0)
    let rigid = UIImpactFeedbackGenerator(style: .rigid)
    rigid.impactOccurred(intensity: 1.0)
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}

enum Layout {
    static let baseWidth: CGFloat = 393
    static let baseHeight: CGFloat = 852

    static func scaleX(for size: CGSize) -> CGFloat {
        size.width / baseWidth
    }

    static func scaleY(for size: CGSize) -> CGFloat {
        size.height / baseHeight
    }

    static func yLift(for size: CGSize) -> CGFloat {
        let lift = (scaleY(for: size) - 1) * 80
        return max(0, lift)
    }

    // Adjust these to position elements globally.
    static let titleXOffset: CGFloat = 0
    static let titleY: CGFloat = 350
    static let heroXOffset: CGFloat = -33
    static let heroY: CGFloat = 900
    static let dotsXOffset: CGFloat = 0
    static let dotsY: CGFloat = 420
    static let buttonXOffset: CGFloat = 0
    static let buttonY: CGFloat = 480
    static let textHeight: CGFloat = 220

    // Props
    static let plantXOffset: CGFloat = -158
    static let plantY: CGFloat = 680
    static let plantWidth: CGFloat = 250

    static let loveboxXOffset: CGFloat = -145
    static let loveboxY: CGFloat = 265
    static let loveboxWidth: CGFloat = 250

    static let tvXOffset: CGFloat = 135
    static let tvY: CGFloat = 570
    static let tvWidth: CGFloat = 200

    static let waterXOffset: CGFloat = 158
    static let waterWidth: CGFloat = 150

    static let galleryXOffset: CGFloat = 110
    static let galleryY: CGFloat = 190
    static let galleryWidth: CGFloat = 220

    static let toysXOffset: CGFloat = 95
    static let toysY: CGFloat = 715
    static let toysWidth: CGFloat = 90

    static let sofaXOffset: CGFloat = -32
    static let sofaWidth: CGFloat = 250
    static let sofaOffsetFromFloor: CGFloat = 0

    static let windowXOffset: CGFloat = -100
    static let windowY: CGFloat = 110
    static let windowWidth: CGFloat = 280

    static let lightXOffset: CGFloat = -170
    static let lightY: CGFloat = 570
    static let lightWidth: CGFloat = 120

    static let heartsBadgeXOffset: CGFloat = -80
    static let streakBadgeXOffset: CGFloat = 80
    static let badgesXOffset: CGFloat = 0
    static let badgesY: CGFloat = 130
    static let badgeWidth: CGFloat = 126

    static let floorWidthFactor: CGFloat = 1.1
    static let floorYFactor: CGFloat = 0.95
    static let heroOffsetFromFloor: CGFloat = 65
    static let plantOffsetFromFloor: CGFloat = -5
    static let waterOffsetFromFloor: CGFloat = -35
    static let toysOffsetFromFloor: CGFloat = -30

    // Name screen positions
    static let nameBackXOffset: CGFloat = -150
    static let nameBackY: CGFloat = 10
    static let nameTitleXOffset: CGFloat = 20
    static let nameTitleY: CGFloat = 250
    static let nameFieldXOffset: CGFloat = 20
    static let nameFieldY: CGFloat = 310
    static let nameButtonXOffset: CGFloat = 20
    static let nameButtonY: CGFloat = 400
    static let nameCardXOffset: CGFloat = 0
    static let nameCardY: CGFloat = 280
    static let nameCardHeight: CGFloat = 280
    static let floorVisualPadding: CGFloat = 40
}

struct DecorPlacement {
    var floorWidthFactor: CGFloat = Layout.floorWidthFactor
    var floorYOffset: CGFloat = 0
    var plantWidth: CGFloat = Layout.plantWidth
    var plantXOffset: CGFloat = Layout.plantXOffset
    var plantOffsetFromFloor: CGFloat = Layout.plantOffsetFromFloor
    var loveboxWidth: CGFloat = Layout.loveboxWidth
    var loveboxXOffset: CGFloat = Layout.loveboxXOffset
    var loveboxY: CGFloat = Layout.loveboxY
    var tvWidth: CGFloat = Layout.tvWidth
    var tvXOffset: CGFloat = Layout.tvXOffset
    var tvY: CGFloat = Layout.tvY
    var waterWidth: CGFloat = Layout.waterWidth
    var waterXOffset: CGFloat = Layout.waterXOffset
    var waterOffsetFromFloor: CGFloat = Layout.waterOffsetFromFloor
    var galleryWidth: CGFloat = Layout.galleryWidth
    var galleryXOffset: CGFloat = Layout.galleryXOffset
    var galleryY: CGFloat = Layout.galleryY
    var toysWidth: CGFloat = Layout.toysWidth
    var toysXOffset: CGFloat = Layout.toysXOffset
    var toysOffsetFromFloor: CGFloat = Layout.toysOffsetFromFloor
    var sofaWidth: CGFloat = Layout.sofaWidth
    var sofaXOffset: CGFloat = Layout.sofaXOffset
    var sofaOffsetFromFloor: CGFloat = Layout.sofaOffsetFromFloor
    var windowWidth: CGFloat = Layout.windowWidth
    var windowXOffset: CGFloat = Layout.windowXOffset
    var windowY: CGFloat = Layout.windowY
    var heroXOffset: CGFloat = Layout.heroXOffset
    var heroOffsetFromFloor: CGFloat = Layout.heroOffsetFromFloor
    var giftWidth: CGFloat = 180
    var giftXOffset: CGFloat = 120
    var giftY: CGFloat = 55
}

extension DecorPlacement {
    static let onboarding = DecorPlacement()
}

struct OnboardingPage {
    let title: String
    let subtitle: String
}

extension DecorPlacement {
    static func dashboard(
        floorWidthFactor: CGFloat = Layout.floorWidthFactor,
        floorYOffset: CGFloat = 0,
        plantWidth: CGFloat = Layout.plantWidth,
        plantXOffset: CGFloat = Layout.plantXOffset,
        plantOffsetFromFloor: CGFloat = Layout.plantOffsetFromFloor,
        loveboxWidth: CGFloat = Layout.loveboxWidth,
        loveboxXOffset: CGFloat = Layout.loveboxXOffset,
        loveboxY: CGFloat = Layout.loveboxY,
        tvWidth: CGFloat = Layout.tvWidth,
        tvXOffset: CGFloat = Layout.tvXOffset,
        tvY: CGFloat = Layout.tvY,
        waterWidth: CGFloat = Layout.waterWidth,
        waterXOffset: CGFloat = Layout.waterXOffset,
        waterOffsetFromFloor: CGFloat = Layout.waterOffsetFromFloor,
        galleryWidth: CGFloat = Layout.galleryWidth,
        galleryXOffset: CGFloat = Layout.galleryXOffset,
        galleryY: CGFloat = Layout.galleryY,
        toysWidth: CGFloat = Layout.toysWidth,
        toysXOffset: CGFloat = Layout.toysXOffset,
        toysOffsetFromFloor: CGFloat = Layout.toysOffsetFromFloor,
        sofaWidth: CGFloat = Layout.sofaWidth,
        sofaXOffset: CGFloat = Layout.sofaXOffset,
        sofaOffsetFromFloor: CGFloat = Layout.sofaOffsetFromFloor,
        windowWidth: CGFloat = Layout.windowWidth,
        windowXOffset: CGFloat = Layout.windowXOffset,
        windowY: CGFloat = Layout.windowY,
        heroXOffset: CGFloat = Layout.heroXOffset,
        heroOffsetFromFloor: CGFloat = Layout.heroOffsetFromFloor,
        giftWidth: CGFloat = 80,
        giftXOffset: CGFloat = -120,
        giftY: CGFloat = 380
    ) -> DecorPlacement {
        var placement = DecorPlacement()
        placement.floorWidthFactor = floorWidthFactor
        placement.floorYOffset = floorYOffset
        placement.plantWidth = plantWidth
        placement.plantXOffset = plantXOffset
        placement.plantOffsetFromFloor = plantOffsetFromFloor
        placement.loveboxWidth = loveboxWidth
        placement.loveboxXOffset = loveboxXOffset
        placement.loveboxY = loveboxY
        placement.tvWidth = tvWidth
        placement.tvXOffset = tvXOffset
        placement.tvY = tvY
        placement.waterWidth = waterWidth
        placement.waterXOffset = waterXOffset
        placement.waterOffsetFromFloor = waterOffsetFromFloor
        placement.galleryWidth = galleryWidth
        placement.galleryXOffset = galleryXOffset
        placement.galleryY = galleryY
        placement.toysWidth = toysWidth
        placement.toysXOffset = toysXOffset
        placement.toysOffsetFromFloor = toysOffsetFromFloor
        placement.sofaWidth = sofaWidth
        placement.sofaXOffset = sofaXOffset
        placement.sofaOffsetFromFloor = sofaOffsetFromFloor
        placement.windowWidth = windowWidth
        placement.windowXOffset = windowXOffset
        placement.windowY = windowY
        placement.heroXOffset = heroXOffset
        placement.heroOffsetFromFloor = heroOffsetFromFloor
        placement.giftWidth = giftWidth
        placement.giftXOffset = giftXOffset
        placement.giftY = giftY
        return placement
    }
}

// Automatically adjust scale on small devices (e.g., iPhone SE height 667)
extension Layout {
    static func smallDeviceScale(for size: CGSize) -> CGFloat {
        if size.height < 720 {    // iPhone SE, older small iPhones
            return 1           // shrink props & floor ~18%
        }
        return 1.0
    }

    static func floorY(for size: CGSize) -> CGFloat {
        var base: CGFloat
        if size.height < 720 {
            base = size.height * 0.88
        } else if size.height < 780 {
            base = size.height * 0.95
        } else {
            base = size.height * floorYFactor
        }

        if size.height <= 740 {
            base -= 8   // slightly lift floor on smaller iPhones (e.g., SE)
        }
        return base
    }

    static func heroScale(for size: CGSize) -> CGFloat {
        let minScale = min(scaleX(for: size), scaleY(for: size))
        let smallFactor = smallDeviceScale(for: size)
        let scaled = minScale * smallFactor * 1.05
        return max(0.68, min(1.0, scaled))
    }

    static func heroOffsetBoost(for size: CGSize) -> CGFloat {
        if size.height < 720 { return 1.1 }
        if size.height < 780 { return 1.12 }
        return 1.0
    }

    static func smallPropDrop(for size: CGSize) -> CGFloat {
        if size.height < 720 { return 10 }   // move props down slightly on SE
        if size.height < 780 { return 12 }
        return 0
    }
}

// MARK: - Love Note Sheet
struct LoveNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    let userName: String
    let partnerName: String?
    let isLightsOut: Bool
    let onSend: (String) -> Void

    @State private var message: String = ""
    @FocusState private var isMessageFocused: Bool

    private var theme: PaletteTheme {
        isLightsOut ? Palette.darkTheme : Palette.lightTheme
    }

    private var displayPartnerName: String {
        partnerName ?? "Your partner"
    }

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }

    var body: some View {
        ZStack {
            // Background
            backgroundGradient(isDark: isLightsOut)
                .ignoresSafeArea()
                .onTapGesture {
                    isMessageFocused = false
                }

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.7))
                                .frame(width: 44, height: 44)
                        }

                        Spacer()

                        Button(action: {
                            isMessageFocused = false
                        }) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.7))
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Title
                    Text("Write a note")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                        .padding(.top, 20)

                    // Heart icon
                    Image(systemName: "heart.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(.pink.opacity(0.8))
                        .padding(.top, 30)
                        .padding(.bottom, 30)

                    // From/To info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("From: \(userName)")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.8))

                            Spacer()

                            Text(todayString)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(theme.textMuted)
                        }

                        Text("To: \(displayPartnerName)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.8))
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)

                    // Message input
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Write a message...")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(theme.textMuted.opacity(0.5))
                                .padding(.top, 12)
                                .padding(.leading, 16)
                        }

                        TextEditor(text: $message)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(theme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .focused($isMessageFocused)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                    }
                    .frame(height: 200)
                    .padding(.horizontal, 20)

                    // Decorative hearts
                    HStack {
                        Spacer()
                        Image(systemName: "heart")
                            .font(.system(size: 28))
                            .foregroundStyle(theme.textMuted.opacity(0.2))
                        Image(systemName: "heart.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.pink.opacity(0.3))
                            .offset(x: -8, y: 8)
                    }
                    .padding(.trailing, 40)
                    .padding(.top, 20)

                    // Send button
                    Button(action: handleSend) {
                        Text("Send")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? theme.textMuted : theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                          ? theme.textMuted.opacity(0.2)
                                          : theme.buttonFill.opacity(0.5))
                            )
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    .padding(.bottom, 30)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isMessageFocused = true
            }
        }
    }

    private func handleSend() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        hapticSoft()
        onSend(trimmed)
        dismiss()
    }

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
}

// MARK: - DoodleCanvasView
struct DoodleCanvasView: View {
    @Environment(\.dismiss) private var dismiss
    let theme: PaletteTheme
    let isLightsOut: Bool
    let userName: String
    let onSave: (UIImage) -> Void

    @StateObject private var canvasViewModel = CanvasViewModel()
    @State private var selectedColor: Color = .black
    @State private var brushSize: CGFloat = 5.0

    private let availableColors: [(Color, String)] = [
        (.black, "Black"),
        (.red, "Red"),
        (Color(red: 1.0, green: 0.4, blue: 0.7), "Pink"),
        (.purple, "Purple"),
        (.blue, "Blue"),
        (.green, "Green"),
        (.yellow, "Yellow")
    ]

    var body: some View {
        ZStack {
            backgroundGradient(isDark: isLightsOut)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with Save/Cancel buttons
                HStack {
                    Button(action: {
                        hapticSoft()
                        dismiss()
                    }) {
                        Text("Cancel")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(theme.textMuted)
                    }

                    Spacer()

                    Text("Draw Your Doodle")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(theme.textPrimary)

                    Spacer()

                    Button(action: {
                        hapticSoft()
                        if let snapshot = canvasViewModel.captureSnapshot() {
                            onSave(snapshot)
                        }
                        dismiss()
                    }) {
                        Text("Save")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(theme.buttonFill)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                // Color picker
                GeometryReader { geo in
                    let isIPad = geo.size.width > 600
                    let colorSize: CGFloat = isIPad ? 56 : 40
                    let colorSpacing: CGFloat = isIPad ? 20 : 12

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: colorSpacing) {
                            ForEach(availableColors, id: \.1) { color, name in
                                Button(action: {
                                    hapticSoft()
                                    selectedColor = color
                                    updateToolColor()
                                }) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: colorSize, height: colorSize)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(
                                                    selectedColor == color ? theme.textPrimary : Color.clear,
                                                    lineWidth: isIPad ? 4 : 3
                                                )
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, isIPad ? 32 : 20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 70)
                .padding(.vertical, 12)

                // Brush size slider
                GeometryReader { geo in
                    let isIPad = geo.size.width > 600

                    VStack(spacing: isIPad ? 12 : 8) {
                        HStack {
                            Text("Brush Size")
                                .font(.system(size: isIPad ? 17 : 15, weight: .medium))
                                .foregroundColor(theme.textMuted)

                            Spacer()

                            Text("\(Int(brushSize))")
                                .font(.system(size: isIPad ? 17 : 15, weight: .semibold))
                                .foregroundColor(theme.textPrimary)
                                .frame(width: isIPad ? 40 : 30)
                        }

                        Slider(value: $brushSize, in: 1...20, step: 1)
                            .tint(theme.buttonFill)
                            .onChange(of: brushSize) { _, _ in
                                updateToolWidth()
                            }
                    }
                    .padding(.horizontal, isIPad ? 32 : 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 60)
                .padding(.vertical, 12)

                // Drawing canvas - always square
                GeometryReader { geo in
                    let isIPad = geo.size.width > 600
                    let availableWidth = max(0, geo.size.width - (isIPad ? 80 : 40))
                    let maxCanvasSize: CGFloat = isIPad ? 700 : 500
                    let canvasSize = min(availableWidth, maxCanvasSize)

                    VStack {
                        Spacer()
                        CanvasViewWrapper(canvasView: canvasViewModel.canvas)
                            .frame(width: canvasSize, height: canvasSize)
                            .background(Color.white)
                            .cornerRadius(isIPad ? 20 : 16)
                            .shadow(color: Color.black.opacity(0.1), radius: isIPad ? 20 : 10, x: 0, y: 5)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Undo/Redo buttons
                GeometryReader { geo in
                    let isIPad = geo.size.width > 600

                    HStack(spacing: isIPad ? 32 : 24) {
                        Button(action: {
                            hapticSoft()
                            canvasViewModel.undo()
                        }) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: isIPad ? 28 : 24, weight: .medium))
                                .foregroundColor(canvasViewModel.canUndo ? theme.textPrimary : theme.textMuted.opacity(0.3))
                                .frame(width: isIPad ? 60 : 44, height: isIPad ? 60 : 44)
                                .background(
                                    Circle()
                                        .fill(canvasViewModel.canUndo ? theme.textPrimary.opacity(0.08) : Color.clear)
                                )
                        }
                        .disabled(!canvasViewModel.canUndo)

                        Button(action: {
                            hapticSoft()
                            canvasViewModel.redo()
                        }) {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: isIPad ? 28 : 24, weight: .medium))
                                .foregroundColor(canvasViewModel.canRedo ? theme.textPrimary : theme.textMuted.opacity(0.3))
                                .frame(width: isIPad ? 60 : 44, height: isIPad ? 60 : 44)
                                .background(
                                    Circle()
                                        .fill(canvasViewModel.canRedo ? theme.textPrimary.opacity(0.08) : Color.clear)
                                )
                        }
                        .disabled(!canvasViewModel.canRedo)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: 80)
                .padding(.vertical, 20)
                .padding(.bottom, 8)
            }
        }
        .onAppear {
            updateToolColor()
            updateToolWidth()
        }
    }

    private func updateToolColor() {
        let uiColor = UIColor(selectedColor)
        canvasViewModel.canvas.tool = PKInkingTool(.pen, color: uiColor, width: brushSize)
    }

    private func updateToolWidth() {
        let uiColor = UIColor(selectedColor)
        canvasViewModel.canvas.tool = PKInkingTool(.pen, color: uiColor, width: brushSize)
    }

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
}

/// MARK: - Canvas ViewModel
class CanvasViewModel: ObservableObject {
    let canvas = PKCanvasView()
    @Published var updateTrigger = false

    var canUndo: Bool {
        canvas.undoManager?.canUndo ?? false
    }

    var canRedo: Bool {
        canvas.undoManager?.canRedo ?? false
    }

    func undo() {
        canvas.undoManager?.undo()
        updateTrigger.toggle()
    }

    func redo() {
        canvas.undoManager?.redo()
        updateTrigger.toggle()
    }

    func clear() {
        canvas.drawing = PKDrawing()
        updateTrigger.toggle()
    }

    func captureSnapshot() -> UIImage? {
        let bounds = canvas.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        // Use PKDrawing's rasterization to avoid heavy view hierarchy rendering (keeps strokes smooth).
        return canvas.drawing.image(from: bounds, scale: UIScreen.main.scale)
    }
}

// MARK: - Canvas View Wrapper
struct CanvasViewWrapper: UIViewRepresentable {
    let canvasView: PKCanvasView
    var onDrawingChanged: ((PKDrawing) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        if canvasView.backgroundColor == nil {
            canvasView.backgroundColor = .white
        }
        canvasView.delegate = context.coordinator
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.delegate = context.coordinator
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasViewWrapper

        init(parent: CanvasViewWrapper) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.onDrawingChanged?(canvasView.drawing)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(PushNotificationManager())
}
