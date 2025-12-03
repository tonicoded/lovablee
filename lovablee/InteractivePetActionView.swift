//
//  InteractivePetActionView.swift
//  lovablee
//
//  Interactive tap-based pet care actions
//

import SwiftUI
import Lottie

extension PetActionType {
    var emoji: String {
        switch self {
        case .water: return "💧"
        case .play: return "🎾"
        case .feed: return "🍖"
        case .note: return "💌"
        case .doodle: return "🎨"
        case .plant: return "🌱"
        }
    }

    var actionText: String {
        switch self {
        case .water: return "Watering"
        case .play: return "Playing"
        case .feed: return "Feeding"
        case .note: return "Writing note"
        case .doodle: return "Creating doodle"
        case .plant: return "Watering plant"
        }
    }

    var animation: String {
        switch self {
        case .water: return "water"
        case .play: return "paws"
        case .feed: return "paws"
        case .note: return "water" // Fallback animation
        case .doodle: return "paws" // Fallback animation
        case .plant: return "water"
        }
    }
}

struct InteractivePetActionView: View {
    let actionType: PetActionType
    let petName: String
    let onComplete: () async throws -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var progress: CGFloat = 0
    @State private var isCompleting = false
    @State private var showSuccessAnimation = false
    @State private var tapCount = 0
    @State private var floatingEmojis: [FloatingEmoji] = []
    @State private var bubbaScale: CGFloat = 1.0
    @State private var showLottie = false
    @State private var isHolding = false
    @State private var holdTimer: Timer?

    private let totalTaps = 20 // Number of taps needed

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.98, green: 0.93, blue: 0.83)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(Color(red: 0.38, green: 0.27, blue: 0.19))
                            .padding()
                    }
                    Spacer()
                }

                Spacer()

                // Bubba with tap/hold area
                ZStack {
                    // Bubba
                    Image("bubbaopen")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 250, height: 250)
                        .scaleEffect(bubbaScale)
                        .gesture(
                            actionType == .plant ?
                            // Hold gesture for plant
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !isHolding {
                                        isHolding = true
                                        startHoldProgress()
                                    }
                                }
                                .onEnded { _ in
                                    isHolding = false
                                } :
                            // Tap gesture for others
                            nil
                        )
                        .onTapGesture {
                            if actionType != .plant {
                                handleTap()
                            }
                        }

                    // Lottie animation overlay
                    if showLottie {
                        LottieView(animation: .named(actionType.animation))
                            .looping()
                            .resizable()
                            .frame(width: 200, height: 200)
                            .allowsHitTesting(false)
                    }

                    // Floating emojis
                    ForEach(floatingEmojis) { emoji in
                        Text(emoji.symbol)
                            .font(.system(size: 40))
                            .offset(x: emoji.offset.width, y: emoji.offset.height)
                            .opacity(emoji.opacity)
                    }
                }
                .frame(height: 350)

                Spacer()

                // Progress section
                VStack(spacing: 12) {
                    Text("\(actionType.actionText)... \(actionType.emoji)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.38, green: 0.27, blue: 0.19))

                    // Progress bar
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(red: 0.54, green: 0.43, blue: 0.32).opacity(0.2))
                            .frame(height: 12)

                        // Progress
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(red: 0.98, green: 0.71, blue: 0.35))
                            .frame(width: max(12, progress * (UIScreen.main.bounds.width - 80)), height: 12)
                            .animation(.spring(response: 0.3), value: progress)

                        // Emoji indicator
                        Text(actionType.emoji)
                            .font(.system(size: 20))
                            .offset(x: max(0, progress * (UIScreen.main.bounds.width - 100)))
                            .animation(.spring(response: 0.3), value: progress)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)

                    Text("\(actionType == .plant ? "Hold" : "Tap") \(petName) to \(actionType.rawValue)!")
                        .font(.subheadline)
                        .foregroundColor(Color(red: 0.54, green: 0.43, blue: 0.32))
                        .opacity(progress < 1 ? 1 : 0)
                }
                .padding(.bottom, 60)
            }

            // Success overlay
            if showSuccessAnimation {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()

                    VStack(spacing: 20) {
                        Text("✨")
                            .font(.system(size: 80))
                            .scaleEffect(showSuccessAnimation ? 1 : 0)
                            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: showSuccessAnimation)

                        Text("\(petName) is happy!")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isCompleting)
    }

    private func handleTap() {
        guard !isCompleting, progress < 1 else { return }

        tapCount += 1
        progress = min(1.0, CGFloat(tapCount) / CGFloat(totalTaps))

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Bubba bounce animation
        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
            bubbaScale = 1.15
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.1)) {
            bubbaScale = 1.0
        }

        // Show lottie animation
        if !showLottie {
            showLottie = true
        }

        // Add floating emoji
        addFloatingEmoji()

        // Check if complete
        if progress >= 1 {
            completeAction()
        }
    }

    private func addFloatingEmoji() {
        let emoji = FloatingEmoji(
            id: UUID(),
            symbol: actionType.emoji,
            offset: .zero,
            opacity: 1.0
        )
        floatingEmojis.append(emoji)

        // Animate emoji up and fade out
        withAnimation(.easeOut(duration: 1.0)) {
            if let index = floatingEmojis.firstIndex(where: { $0.id == emoji.id }) {
                floatingEmojis[index].offset = CGSize(
                    width: CGFloat.random(in: -50...50),
                    height: -150
                )
                floatingEmojis[index].opacity = 0
            }
        }

        // Remove after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            floatingEmojis.removeAll { $0.id == emoji.id }
        }
    }

    private func completeAction() {
        isCompleting = true

        // Big success haptic
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Show success animation
        withAnimation {
            showSuccessAnimation = true
        }

        // Complete the action
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            try? await onComplete()

            await MainActor.run {
                dismiss()
            }
        }
    }

    private func startHoldProgress() {
        guard !isCompleting else { return }

        // Show lottie animation immediately
        showLottie = true

        // Haptic feedback
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Start timer for continuous progress
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] _ in
            guard isHolding, progress < 1 else {
                holdTimer?.invalidate()
                holdTimer = nil
                if progress >= 1 {
                    completeAction()
                }
                return
            }

            // Increment progress (3 seconds to complete)
            progress += 0.05 / 3.0

            // Add floating emoji periodically
            if Int(progress * 100) % 10 == 0 {
                addFloatingEmoji()
            }

            // Bubba bounce
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                bubbaScale = 1.1
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.05)) {
                bubbaScale = 1.0
            }
        }
    }
}

// MARK: - Supporting Types

private struct FloatingEmoji: Identifiable {
    let id: UUID
    let symbol: String
    var offset: CGSize
    var opacity: Double
}

// MARK: - Preview

#if DEBUG
struct InteractivePetActionView_Previews: PreviewProvider {
    static var previews: some View {
        InteractivePetActionView(
            actionType: .water,
            petName: "Bubba",
            onComplete: {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        )
    }
}
#endif
