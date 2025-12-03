//
//  PlantSheetView.swift
//  lovablee
//
//  Plant health status view
//

import SwiftUI

struct PlantSheetView: View {
    let lastWateredAt: Date?
    let theme: PaletteTheme
    let isLightsOut: Bool
    let onClose: () -> Void
    let onWater: () -> Void

    @State private var currentTime = Date()

    private static let cooldownInterval: TimeInterval = 15 * 60 // 15 minutes

    private var plantHealth: PlantHealth {
        guard let lastWatered = lastWateredAt else {
            return .dry
        }

        let hoursSinceWatering = currentTime.timeIntervalSince(lastWatered) / 3600

        switch hoursSinceWatering {
        case 0..<1:
            return .thriving
        case 1..<6:
            return .healthy
        case 6..<24:
            return .okay
        case 24..<48:
            return .thirsty
        default:
            return .dry
        }
    }

    private var cooldownRemaining: TimeInterval? {
        guard let lastWatered = lastWateredAt else {
            return nil
        }
        let elapsed = currentTime.timeIntervalSince(lastWatered)
        let remaining = Self.cooldownInterval - elapsed
        return remaining > 0 ? remaining : nil
    }

    private var canWater: Bool {
        cooldownRemaining == nil
    }

    private var waterButtonText: String {
        if let remaining = cooldownRemaining {
            let minutes = Int(ceil(remaining / 60))
            return "Water available in \(minutes) min"
        }
        return "Hold to Water Plant"
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background - adapts to lights out mode
                (isLightsOut ?
                    Color(red: 0.18, green: 0.15, blue: 0.13) :
                    Color(red: 0.98, green: 0.93, blue: 0.83))
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(theme.textPrimary)
                                .padding()
                        }
                        Spacer()
                    }

                    Spacer()

                    // Plant Image
                    Image("plant")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 400, height: 400)
                        .padding(.bottom, 24)

                    // Health Status Card
                    VStack(spacing: 20) {
                        Text("🌱 Plant Health")
                            .font(.system(.title2, weight: .bold))
                            .foregroundColor(theme.textPrimary)

                        // Health Status
                        VStack(spacing: 8) {
                            Text("STATUS")
                                .font(.system(.caption, weight: .bold))
                                .foregroundColor(isLightsOut ?
                                                Color(red: 0.7, green: 0.6, blue: 0.5) :
                                                theme.textMuted)
                                .textCase(.uppercase)

                            Text(plantHealth.displayName)
                                .font(.system(.largeTitle, weight: .bold))
                                .foregroundColor(plantHealth.color)
                        }
                        .padding(.vertical, 20)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(isLightsOut ?
                                      Color(red: 0.14, green: 0.11, blue: 0.1) :
                                      Color.white)
                                .shadow(color: Color.black.opacity(isLightsOut ? 0.3 : 0.1),
                                       radius: 10, y: 5)
                        )
                        .padding(.horizontal, 40)

                        // Last Watered
                        if let lastWatered = lastWateredAt {
                            Text("Last watered \(relativeTime(from: lastWatered))")
                                .font(.system(.subheadline))
                                .foregroundColor(isLightsOut ?
                                                Color(red: 0.7, green: 0.6, blue: 0.5) :
                                                theme.textMuted)
                        } else {
                            Text("Never been watered")
                                .font(.system(.subheadline))
                                .foregroundColor(isLightsOut ?
                                                Color(red: 0.7, green: 0.6, blue: 0.5) :
                                                theme.textMuted)
                        }

                        // Water Button
                        Button {
                            if canWater {
                                onWater()
                            }
                        } label: {
                            HStack {
                                Image(systemName: canWater ? "drop.fill" : "clock.fill")
                                Text(waterButtonText)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(.body))
                            .foregroundColor(.white)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(canWater ?
                                          Color(red: 0.55, green: 0.78, blue: 0.48) :
                                          Color.gray.opacity(0.5))
                            )
                        }
                        .disabled(!canWater)
                        .padding(.horizontal, 40)
                        .padding(.top, 8)
                    }

                    Spacer()
                }
            }
        }
        .onAppear {
            // Start updating current time to keep cooldown fresh
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                currentTime = Date()
            }
        }
    }

    private func relativeTime(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Plant Health

enum PlantHealth {
    case thriving
    case healthy
    case okay
    case thirsty
    case dry

    var displayName: String {
        switch self {
        case .thriving: return "Thriving"
        case .healthy: return "Healthy"
        case .okay: return "Okay"
        case .thirsty: return "Thirsty"
        case .dry: return "Dry"
        }
    }

    var color: Color {
        switch self {
        case .thriving: return Color(red: 0.2, green: 0.8, blue: 0.3)
        case .healthy: return Color(red: 0.55, green: 0.78, blue: 0.48)
        case .okay: return Color(red: 0.95, green: 0.77, blue: 0.06)
        case .thirsty: return Color(red: 0.95, green: 0.61, blue: 0.07)
        case .dry: return Color(red: 0.8, green: 0.4, blue: 0.3)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct PlantSheetView_Previews: PreviewProvider {
    static var previews: some View {
        PlantSheetView(
            lastWateredAt: Date().addingTimeInterval(-60 * 60 * 3), // 3 hours ago
            theme: Palette.lightTheme,
            isLightsOut: false,
            onClose: {},
            onWater: {}
        )
    }
}
#endif
