import SwiftUI

// MARK: - Data Models

struct GiftItem: Identifiable {
    let id = UUID()
    let name: String
    let imageName: String
    let cost: Int
    let isLocked: Bool
    let isPremium: Bool

    static let allGifts: [GiftItem] = [
        GiftItem(name: "candy", imageName: "candy", cost: 100, isLocked: false, isPremium: false),
        GiftItem(name: "lollipop", imageName: "lollipop", cost: 120, isLocked: false, isPremium: false),
        GiftItem(name: "sweet", imageName: "sweet", cost: 130, isLocked: false, isPremium: false),
        GiftItem(name: "rose", imageName: "rose", cost: 150, isLocked: false, isPremium: false),
        GiftItem(name: "donut", imageName: "donut", cost: 160, isLocked: false, isPremium: false),
        GiftItem(name: "star", imageName: "star", cost: 170, isLocked: false, isPremium: false),
        GiftItem(name: "toast", imageName: "toast", cost: 180, isLocked: false, isPremium: false),
        GiftItem(name: "cake", imageName: "cake", cost: 200, isLocked: false, isPremium: false),
        GiftItem(name: "lipgloss", imageName: "lipgloss", cost: 220, isLocked: false, isPremium: false),
        GiftItem(name: "juice", imageName: "juice", cost: 250, isLocked: false, isPremium: false),
        GiftItem(name: "snowman", imageName: "snowman", cost: 280, isLocked: false, isPremium: false),
        GiftItem(name: "xmastree", imageName: "xmastree", cost: 350, isLocked: false, isPremium: false),
        GiftItem(name: "pizza", imageName: "pizza", cost: 400, isLocked: false, isPremium: false),
        GiftItem(name: "watch", imageName: "watch", cost: 450, isLocked: false, isPremium: false),
        GiftItem(name: "necklace", imageName: "necklace", cost: 500, isLocked: false, isPremium: false),
        GiftItem(name: "ring", imageName: "ring", cost: 600, isLocked: false, isPremium: false)
    ]
}

struct PurchasedGift: Codable, Identifiable {
    let id: UUID
    let coupleKey: String
    let senderId: String
    let senderName: String
    let recipientId: String
    let recipientName: String
    let giftType: String
    let message: String?
    let isOpened: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case coupleKey
        case senderId
        case senderName
        case recipientId
        case recipientName
        case giftType
        case message
        case isOpened
        case createdAt
    }
}

// MARK: - Main Gifts Shop View

struct GiftsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var currentHearts: Int
    let onPurchase: (GiftItem, String) -> Void
    let loadGifts: (() async throws -> [PurchasedGift])?
    let userIdentifier: String?

    @State private var selectedGift: GiftItem?
    @State private var showPurchaseSheet = false
    @State private var showGiftHistory = false

    let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(red: 0.996, green: 0.909, blue: 0.749)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Text("gifts")
                                .font(.system(size: 48, weight: .bold))
                                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))

                            Text("send a gift to your partner")
                                .font(.system(size: 18))
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.35))
                        }
                        .padding(.top, 20)

                        // Hearts display
                        HStack(spacing: 8) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red.opacity(0.8))
                                .font(.system(size: 20))
                            Text("\(currentHearts)")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 25)
                                .fill(Color.white.opacity(0.9))
                        )

                        // Gift grid
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(GiftItem.allGifts) { gift in
                                GiftCard(gift: gift, currentHearts: currentHearts)
                                    .onTapGesture {
                                        if !gift.isLocked {
                                            print("🎁 Gift tapped: \(gift.name), Cost: \(gift.cost), Current Hearts: \(currentHearts), Can afford: \(currentHearts >= gift.cost)")
                                            selectedGift = gift
                                            showPurchaseSheet = true
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showGiftHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 20))
                            .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))
                    }
                }
            }
        }
        .sheet(isPresented: $showPurchaseSheet) {
            if let gift = selectedGift {
                GiftPurchaseSheet(gift: gift, currentHearts: currentHearts) { message in
                    onPurchase(gift, message)
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showGiftHistory) {
            if let loadGifts = loadGifts {
                GiftHistoryView(loadGifts: loadGifts, userIdentifier: userIdentifier)
            }
        }
    }
}

// MARK: - Gift Card Component

struct GiftCard: View {
    let gift: GiftItem
    let currentHearts: Int

    var canAfford: Bool {
        currentHearts >= gift.cost && !gift.isLocked
    }

    var body: some View {
        VStack(spacing: 12) {
            // Gift image
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.white.opacity(0.9))
                    .frame(height: 160)

                if gift.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color(red: 0.6, green: 0.55, blue: 0.5))
                        .opacity(0.4)
                } else {
                    Image(gift.imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .opacity(canAfford ? 1.0 : 0.4)
                }
            }

            // Gift name
            Text(gift.name)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))

            // Cost badge
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundColor(.red.opacity(0.8))
                    .font(.system(size: 14))
                Text("\(gift.cost)")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))

                if gift.isPremium {
                    Image(systemName: "crown.fill")
                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.2))
                        .font(.system(size: 14))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.7))
            )
        }
        .opacity(canAfford ? 1.0 : 0.6)
    }
}

// MARK: - Gift Purchase Sheet

struct GiftPurchaseSheet: View {
    @Environment(\.dismiss) var dismiss
    let gift: GiftItem
    let currentHearts: Int
    let onConfirm: (String) -> Void

    @State private var message: String = ""
    @FocusState private var isMessageFocused: Bool

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Gift preview
                    VStack(spacing: 16) {
                        Image(gift.imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 140, height: 140)

                        Text(gift.name)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))

                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red.opacity(0.8))
                            Text("\(gift.cost)")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))
                        }
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 24)

                    // Message input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("add a message (optional)")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.35))
                            .padding(.leading, 4)

                        TextField("write something sweet...", text: $message, axis: .vertical)
                            .lineLimit(3...5)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.9))
                            )
                            .focused($isMessageFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isMessageFocused = false
                            }
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Action buttons
                    VStack(spacing: 16) {
                        Button(action: {
                            isMessageFocused = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                onConfirm(message)
                            }
                        }) {
                            Text("send gift")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(red: 1.0, green: 0.4, blue: 0.4))
                                )
                        }

                        Button(action: { dismiss() }) {
                            Text("cancel")
                                .font(.system(size: 18))
                                .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.35))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(Color(red: 0.996, green: 0.909, blue: 0.749))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        isMessageFocused = false
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
    }
}

// MARK: - Gift History View

struct GiftHistoryView: View {
    @Environment(\.dismiss) var dismiss
    let loadGifts: () async throws -> [PurchasedGift]
    let userIdentifier: String?

    @State private var gifts: [PurchasedGift] = []
    @State private var isLoading = false

    var sentGifts: [PurchasedGift] {
        gifts.filter { $0.senderId == userIdentifier }
    }

    var receivedGifts: [PurchasedGift] {
        gifts.filter { $0.recipientId == userIdentifier }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.996, green: 0.909, blue: 0.749)
                    .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Sent gifts
                            if !sentGifts.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Sent")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))
                                        .padding(.horizontal, 20)

                                    ForEach(sentGifts) { gift in
                                        GiftHistoryCard(gift: gift, isSent: true)
                                    }
                                }
                            }

                            // Received gifts
                            if !receivedGifts.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Received")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))
                                        .padding(.horizontal, 20)

                                    ForEach(receivedGifts) { gift in
                                        GiftHistoryCard(gift: gift, isSent: false)
                                    }
                                }
                            }

                            if gifts.isEmpty && !isLoading {
                                VStack(spacing: 16) {
                                    Image(systemName: "gift")
                                        .font(.system(size: 60))
                                        .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.45))
                                    Text("No gifts yet")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.35))
                                }
                                .padding(.top, 100)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle("Gift History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))
                    }
                }
            }
        }
        .task {
            await refreshGifts()
        }
    }

    private func refreshGifts() async {
        isLoading = true
        do {
            gifts = try await loadGifts()
        } catch {
            print("Error loading gifts: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Gift History Card

struct GiftHistoryCard: View {
    let gift: PurchasedGift
    let isSent: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Gift icon
            Image(gift.giftType)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(isSent ? "To: \(gift.recipientName)" : "From: \(gift.senderName)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))

                    Spacer()

                    Text(gift.giftType)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.45))
                }

                if let message = gift.message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.35))
                        .lineLimit(2)
                }

                Text(gift.createdAt, style: .relative) + Text(" ago")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.6, green: 0.5, blue: 0.45))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.7))
        )
        .padding(.horizontal, 20)
    }
}

// MARK: - Received Gift Modal

struct ReceivedGiftModal: View {
    @Environment(\.dismiss) var dismiss
    let gift: PurchasedGift

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VStack(spacing: 24) {
                // Gift image
                Image(gift.giftType)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)

                // Title
                Text("🎁 Gift Received!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))

                // Sender info
                Text("\(gift.senderName) sent you a \(gift.giftType)!")
                    .font(.system(size: 18))
                    .foregroundColor(Color(red: 0.5, green: 0.4, blue: 0.35))
                    .multilineTextAlignment(.center)

                // Message
                if let message = gift.message, !message.isEmpty {
                    Text("\"\(message)\"")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.25))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .italic()
                }

                // Close button
                Button(action: { dismiss() }) {
                    Text("Thanks!")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(red: 1.0, green: 0.4, blue: 0.4))
                        )
                }
                .padding(.horizontal, 24)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(red: 0.996, green: 0.909, blue: 0.749))
            )
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct GiftsView_Previews: PreviewProvider {
    static var previews: some View {
        GiftsView(
            currentHearts: .constant(1360),
            onPurchase: { gift, message in
                print("Purchased \(gift.name) with message: \(message)")
            },
            loadGifts: nil,
            userIdentifier: nil
        )
    }
}
#endif
