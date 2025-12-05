import SwiftUI

struct PaywallView: View {
    var onSelectMonthly: (() -> Void)?
    var onSelectYearly: (() -> Void)?
    var onRestore: (() -> Void)?
    var onClose: (() -> Void)?
    var monthlyPrice: String = ""
    var monthlyOriginalPrice: String? = nil
    var yearlyPrice: String = ""
    var yearlyOriginalPrice: String? = nil
    var yearlyBadgeText: String? = "Best value"
    var title: String = "Upgrade to Pro"
    var subtitle: String = "Unlock every premium feature for your own space. Each partner upgrades separately."

    var body: some View {
        ZStack {
            background
            VStack(spacing: 22) {
                header
                benefits
                planOptions
                perPersonNote
                legalLinks
            }
            .padding(.horizontal, 22)
            .padding(.top, 32)
            .padding(.bottom, 28)
        }
        .overlay(alignment: .topTrailing) {
            if let onClose {
                CloseButton(action: onClose)
                    .padding(.trailing, 12)
                    .padding(.top, 12)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            AppIconCircleView()
            Text(title)
                .font(.system(size: 28, weight: .black))
                .foregroundColor(.primary)
            Text(subtitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.primary.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 12) {
            BenefitRow(icon: "tv.fill", text: "Cozy TV mode for live doodles")
            BenefitRow(icon: "sparkles", text: "All premium drops & collections")
            BenefitRow(icon: "heart.text.square.fill", text: "Unlimited love notes and doodles")
            BenefitRow(icon: "calendar.badge.clock", text: "Full anniversaries, gifts, and reminders")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planOptions: some View {
        VStack(spacing: 10) {
            PlanCard(
                title: "Yearly plan",
                price: yearlyPrice,
                originalPrice: yearlyOriginalPrice,
                badge: yearlyBadgeText,
                isEmphasized: true,
                action: { onSelectYearly?() }
            )
            PlanCard(
                title: "Monthly plan",
                price: monthlyPrice,
                originalPrice: monthlyOriginalPrice,
                badge: nil,
                isEmphasized: false,
                action: { onSelectMonthly?() }
            )
        }
    }

    private var perPersonNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 0.55, green: 0.28, blue: 0.24))
            Text("Pro is per person. Your partner upgrades separately.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private var legalLinks: some View {
        HStack(spacing: 16) {
            Button("Restore") { onRestore?() }
            Link("Terms", destination: LegalLinks.terms)
            Link("Privacy", destination: LegalLinks.privacy)
        }
        .font(.footnote)
        .foregroundColor(.primary.opacity(0.65))
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.89, blue: 0.83),
                    Color(red: 0.94, green: 0.76, blue: 0.82),
                    Color(red: 0.88, green: 0.63, blue: 0.80)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.22))
                .blur(radius: 60)
                .frame(width: 260, height: 260)
                .offset(x: -140, y: -240)

            Circle()
                .fill(Color.white.opacity(0.18))
                .blur(radius: 70)
                .frame(width: 240, height: 240)
                .offset(x: 160, y: 200)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.85))
                .shadow(color: Color.black.opacity(0.12), radius: 20, y: 10)
                .padding(.horizontal, 12)
                .padding(.vertical, 20)
        }
    }
}

private struct BenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(red: 0.41, green: 0.21, blue: 0.15))
            Text(text)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
}

private struct PlanCard: View {
    let title: String
    let price: String
    let originalPrice: String?
    let badge: String?
    let isEmphasized: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    HStack(spacing: 6) {
                        if let originalPrice {
                            Text(originalPrice)
                                .strikethrough()
                                .foregroundColor(.primary.opacity(0.6))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(price)
                            .foregroundColor(.primary)
                            .font(.system(size: 16, weight: .heavy))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary.opacity(0.5))
                if let badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.92, green: 0.66, blue: 0.78))
                        )
                        .foregroundColor(Color(red: 0.38, green: 0.19, blue: 0.22))
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(isEmphasized ? Color.white : Color.white.opacity(0.7))
                    .shadow(color: Color.black.opacity(isEmphasized ? 0.12 : 0.06), radius: isEmphasized ? 12 : 6, y: isEmphasized ? 6 : 3)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isEmphasized ? Color(red: 0.84, green: 0.34, blue: 0.54) : Color(.separator), lineWidth: isEmphasized ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView(
            onSelectMonthly: {},
            onSelectYearly: {},
            onRestore: {},
            onClose: {}
        )
        .previewLayout(.sizeThatFits)
    }
}
#endif

private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary.opacity(0.8))
                .padding(12)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.9))
                        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Icon helper
private struct AppIconCircleView: View {
    var body: some View {
        if let icon = appIconImage() {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .clipShape(Circle())
                .background(
                    Circle()
                        .fill(Color(.systemGray6))
                        .frame(width: 110, height: 110)
                        .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
                )
        } else {
            Circle()
                .fill(Color(.systemGray6))
                .frame(width: 110, height: 110)
                .overlay(
                    Image(systemName: "heart.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.pink)
                )
                .shadow(color: .black.opacity(0.08), radius: 10, y: 6)
        }
    }

    private func appIconImage() -> UIImage? {
        guard
            let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let last = files.last
        else { return nil }
        return UIImage(named: last)
    }
}
