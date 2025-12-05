import Foundation
import Combine
import StoreKit

enum LegalLinks {
    static let privacy = URL(string: "https://lovableeapp.vercel.app/privacy.html")!
    static let terms = URL(string: "https://lovableeapp.vercel.app/terms.html")!
    static let support = URL(string: "https://lovableeapp.vercel.app/support.html")!
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    enum Plan: String, CaseIterable {
        case monthly = "com.anthony.lovablee.pro.monthly2"
        case yearly = "com.anthony.lovablee.pro.yearly"

        var marketingName: String {
            switch self {
            case .monthly: return "Monthly"
            case .yearly: return "Yearly"
            }
        }
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var activeProductIDs: Set<String> = []
    @Published private(set) var purchaseInFlightProductID: String?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var hasActiveSubscription = false
    @Published private(set) var activePlan: Plan?
    @Published private(set) var subscriptionExpirationDate: Date?

    private var entitlementRefreshTask: Task<Void, Never>?
    private init() {
        Task { await refreshProducts() }
        Task { await updateActiveEntitlements() }
        startEntitlementRefreshLoop()
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for await result in Transaction.updates {
                do {
                    try await self.handle(transactionResult: result)
                } catch {
                    await MainActor.run {
                        self.lastErrorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    deinit {
        entitlementRefreshTask?.cancel()
    }

    var isSubscribed: Bool { hasActiveSubscription }

    func refreshProducts() async {
        do {
            let fetched = try await Product.products(for: Plan.allCases.map(\.rawValue))
            await MainActor.run {
                products = fetched.sorted(by: { $0.displayName < $1.displayName })
            }
        } catch {
            await MainActor.run {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    func purchase(productID: String) async {
        guard let product = products.first(where: { $0.id == productID }) else {
            lastErrorMessage = "Unable to find product."
            return
        }
        purchaseInFlightProductID = productID
        defer { purchaseInFlightProductID = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                try await handle(transactionResult: verification)
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateActiveEntitlements()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func displayPrice(for plan: Plan) -> String {
        if let product = products.first(where: { $0.id == plan.rawValue }) {
            return product.displayPrice
        }
        switch plan {
        case .monthly: return "$1.99"
        case .yearly: return "$12.99"
        }
    }

    var remainingTimeDescription: String? {
        guard let expirationDate = subscriptionExpirationDate, expirationDate > Date() else { return nil }
        let components = Calendar.current.dateComponents([.day, .hour], from: Date(), to: expirationDate)
        var parts: [String] = []
        if let days = components.day, days > 0 { parts.append("\(days)d") }
        if let hours = components.hour, hours > 0 { parts.append("\(hours)h") }
        if parts.isEmpty { parts.append("under 1h") }
        return parts.joined(separator: " ")
    }

    private func updateActiveEntitlements() async {
        var activeIDs = Set<String>()
        var chosenTransaction: Transaction?
        let now = Date()

        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement,
                  transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil else { continue }

            if let expiry = transaction.expirationDate, expiry <= now { continue }

            activeIDs.insert(transaction.productID)

            if chosenTransaction == nil {
                chosenTransaction = transaction
            } else if let currentExpiry = chosenTransaction?.expirationDate,
                      let newExpiry = transaction.expirationDate,
                      newExpiry > currentExpiry {
                chosenTransaction = transaction
            }
        }

        await MainActor.run {
            activeProductIDs = activeIDs
            activePlan = chosenTransaction.flatMap { Plan(rawValue: $0.productID) }
            subscriptionExpirationDate = chosenTransaction?.expirationDate
            hasActiveSubscription = chosenTransaction != nil
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async throws {
        switch transactionResult {
        case .unverified(_, let error):
            await MainActor.run {
                lastErrorMessage = error.localizedDescription
            }
        case .verified(let transaction):
            await transaction.finish()
            await updateActiveEntitlements()
        }
    }

    private func startEntitlementRefreshLoop() {
        entitlementRefreshTask = Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000) // 1 hour
                await self.updateActiveEntitlements()
            }
        }
    }
}
