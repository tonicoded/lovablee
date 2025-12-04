import SwiftUI
import PencilKit
import UIKit
import Combine

/// Full-screen faux lock screen with live doodling.
struct DoodleLiveLockScreenView: View {
    @Environment(\.dismiss) private var dismiss
    let userName: String
    let partnerName: String?
    let userId: String?
    let coupleKey: String?
    let onSaveDoodle: ((UIImage) async throws -> Void)?
    let loadDoodles: (() async throws -> [Doodle])?
    let onPublishLive: ((UIImage) async throws -> Void)?
    let onFetchLive: (() async throws -> LiveDoodle?)?
    let onGetCoupleKey: (() async throws -> String?)?
    let supabaseURL: URL?
    let supabaseAnonKey: String?
    let accessToken: String?

    @StateObject private var viewModel = DoodleLiveLockScreenViewModel()
    @StateObject private var realtimeService = LiveDoodleRealtimeService()
    @State private var selectedStyle: LockScreenStyle = .neonGrid
    @State private var showStyles = false
    @State private var now = Date()
    @State private var showErrorAlert = false
    @State private var showPalette = false
    @State private var livePollTimer: AnyCancellable?
    @State private var livePublishDebounce: AnyCancellable?
    @State private var isPublishingLive = false
    @State private var debugStatus: String = "idle"

    private let colors: [Color] = [
        Color(red: 1.00, green: 0.90, blue: 0.30), // yellow
        Color(red: 1.00, green: 0.55, blue: 0.80), // pink
        Color(red: 0.65, green: 0.80, blue: 1.00), // sky
        Color(red: 0.65, green: 1.00, blue: 0.75), // mint
        Color.white,
        Color(red: 0.95, green: 0.25, blue: 0.35)  // red
    ]

    var body: some View {
        ZStack {
            lockScreenBackground(style: selectedStyle)
            styleOverlay(style: selectedStyle)

            if let partner = viewModel.partnerImage {
                Image(uiImage: partner)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .opacity(0.9) // Show partner strokes vividly
                    .allowsHitTesting(false)
            }

            // Full-bleed canvas layer
            TransparentCanvasView(canvasView: viewModel.canvasModel.canvas) {
                viewModel.updateUndoStates()
                scheduleLivePublish()
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    clockView
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 200, height: 36)
                        .overlay(
                            HStack(spacing: 8) {
                                Label(partnerName ?? "Partner", systemImage: "heart.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("·")
                                    .font(.system(size: 15, weight: .semibold))
                                Text(userName)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                                .foregroundColor(.white)
                        )
                }
                .padding(.top, 52)

                Spacer()

                Button {
                    hapticSoft()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                        showStyles.toggle()
                    }
                } label: {
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 180, height: 44)
                        .overlay(
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text(showStyles ? "hide lockscreen styles" : "choose lockscreen")
                            }
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                        )
                }
                .padding(.horizontal, 20)

                if showStyles {
                    stylePicker
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                drawingToolbar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                Text(debugStatus)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.bottom, 8)

                Button {
                    hapticSoft()
                    dismiss()
                } label: {
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 180, height: 44)
                        .overlay(
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                Text("close live doodle")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        )
                }
                .padding(.bottom, 12)

                homeIndicator
                    .padding(.bottom, 12)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            viewModel.prepareCanvas()
            Task {
                await resolveCoupleKey()
                await MainActor.run {
                    startLivePolling()
                    startRealtime()
                }
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
        .onReceive(realtimeService.$lastEventDescription.dropFirst().receive(on: RunLoop.main)) { desc in
            debugStatus = desc
        }
        .onDisappear {
            livePollTimer?.cancel()
            livePublishDebounce?.cancel()
            viewModel.resetLiveState()
            viewModel.clearCanvas()
        }
        .alert("Oops", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Something went wrong")
        }
    }

    private func lockScreenBackground(style: LockScreenStyle) -> some View {
        style.background
            .ignoresSafeArea()
    }

    @ViewBuilder
    private func styleOverlay(style: LockScreenStyle) -> some View {
        switch style {
        case .neonGrid:
            LinearGradient(colors: [.clear, Color.white.opacity(0.08)], startPoint: .top, endPoint: .bottom)
                .blendMode(.screen)
            GeometryReader { geo in
                let size = geo.size
                Path { path in
                    let spacing: CGFloat = 28
                    stride(from: 0, through: size.width + spacing, by: spacing).forEach { x in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x - size.height, y: size.height))
                    }
                }
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
            }
            .ignoresSafeArea()
        case .sunsetGlass:
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(x: 140, y: -260)
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -160, y: 140)
        case .cosmic:
            RadialGradient(colors: [Color.white.opacity(0.18), .clear],
                           center: .center,
                           startRadius: 40,
                           endRadius: 380)
                .blendMode(.screen)
        case .vaporWave:
            LinearGradient(colors: [.white.opacity(0.15), .clear],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .blur(radius: 28)
        case .midnightCandy:
            Rectangle()
                .fill(
                    AngularGradient(colors: [
                        Color.white.opacity(0.08),
                        .clear,
                        Color.white.opacity(0.05),
                        .clear
                    ], center: .center)
                )
        }
    }

    private var stylePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LockScreenStyle.allCases, id: \.self) { style in
                    Button {
                        hapticSoft()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            selectedStyle = style
                        }
                    } label: {
                        StyleChip(style: style, isSelected: selectedStyle == style)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var clockView: some View {
        VStack(spacing: 4) {
            Text(now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.85))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(now, style: .time)
                    .font(.system(size: 76, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                if let last = viewModel.lastSavedAt {
                    Text("• sent \(relativeDate(last))")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.75))
                        .padding(.top, 6)
                }
            }
        }
    }

    private var drawingToolbar: some View {
        HStack(spacing: 12) {
            Button {
                hapticSoft()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                    showPalette.toggle()
                }
                debugStatus = "palette \(showPalette ? "open" : "closed")"
            } label: {
                Circle()
                    .fill(viewModel.selectedColor)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "paintbrush.pointed")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black.opacity(0.6))
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 4)
            }

            if showPalette {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            Button {
                                hapticSoft()
                                viewModel.setColor(color)
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(viewModel.selectedColor == color ? 1 : 0),
                                                    lineWidth: 2)
                                    )
                            }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "scribble.variable")
                                .foregroundColor(.white.opacity(0.8))
                            Slider(value: $viewModel.brushSize, in: 2...24, step: 1) { _ in
                                viewModel.setBrushSize(viewModel.brushSize)
                            }
                            .frame(width: 120)
                            .tint(Color.white)
                            Text("\(Int(viewModel.brushSize))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(width: 32)
                        }
                        .padding(.leading, 6)
                    }
                }
                .frame(height: 44)
            }

            Spacer()

            Button {
                hapticSoft()
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .foregroundColor(viewModel.canUndo ? .white : .white.opacity(0.35))
            }
            .disabled(!viewModel.canUndo)

            Button {
                hapticSoft()
                viewModel.clearCanvas()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .foregroundColor(.white)
            }
        }
    }

    private var homeIndicator: some View {
        Capsule()
            .fill(Color.white.opacity(0.6))
            .frame(width: 140, height: 5)
    }

    private func scheduleLivePublish() {
        // Keep input snappy: throttle publish work and avoid overlapping snapshots.
        livePublishDebounce?.cancel()
        livePublishDebounce = Just(())
            .delay(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { _ in
                Task {
                    guard !isPublishingLive else { return }
                    isPublishingLive = true
                    defer { isPublishingLive = false }
                    guard let snapshot = await MainActor.run(body: { viewModel.canvasModel.captureSnapshot() }) else { return }
                    guard let onPublishLive else { return }
                    print("🎨 Live publish snapshot")
                    try? await onPublishLive(snapshot)
                    await MainActor.run {
                        debugStatus = "publish"
                    }
                }
            }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func resolveCoupleKey() async {
        var resolvedKey: String? = nil

        // Seed with the passed-in code if we have it.
        if let localKey = coupleKey, !localKey.isEmpty {
            resolvedKey = localKey
        }

        // Fetch canonical key from Supabase to ensure realtime filters match server expectations.
        let fetched = try? await onGetCoupleKey?()
        if let canonicalKey = fetched ?? nil,
           !canonicalKey.isEmpty {
            resolvedKey = canonicalKey
        }

        await MainActor.run {
            viewModel.coupleKey = resolvedKey
        }
    }

    private func startLivePolling() {
        guard livePollTimer == nil else { return }
        guard viewModel.coupleKey?.isEmpty == false else {
            debugStatus = "no couple key"
            return
        }
        livePollTimer = Timer.publish(every: 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                Task {
                    do {
                        guard let live = try await onFetchLive?() else {
                            await MainActor.run { debugStatus = "poll none" }
                            return
                        }
                        print("🎨 Live poll received \(live.id)")
                        await viewModel.updatePartnerLive(doodle: live)
                        await MainActor.run {
                            debugStatus = "poll ok"
                        }
                    } catch {
                        await MainActor.run { debugStatus = "poll err" }
                        print("🎨 Live poll error: \(error)")
                    }
                }
            }
    }

    private func startRealtime() {
        guard let coupleKey = viewModel.coupleKey, !coupleKey.isEmpty else {
            debugStatus = "no key ws"
            return
        }
        guard let url = supabaseURL,
              let anon = supabaseAnonKey,
              let token = accessToken,
              let myUserId = userId else { return }

        realtimeService.connect(
            projectURL: url,
            anonKey: anon,
            accessToken: token,
            coupleKey: coupleKey,
            myUserId: myUserId
        ) { doodle in
            print("🎨 Live websocket received \(doodle.id)")
            Task { await viewModel.updatePartnerLive(doodle: doodle) }
            Task { @MainActor in
                debugStatus = "ws recv"
            }
        }
        debugStatus = "ws connect"
    }
}

final class DoodleLiveLockScreenViewModel: ObservableObject {
    @Published var partnerImage: UIImage?
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var selectedColor: Color = Color(red: 1.00, green: 0.90, blue: 0.30)
    @Published var brushSize: CGFloat = 10
    @Published var lastSavedAt: Date?
    @Published var canUndo = false
    @Published private(set) var lastPartnerDoodleId: UUID?
    @Published private(set) var lastPartnerLiveId: UUID?
    @Published var coupleKey: String?

    let canvasModel = CanvasViewModel()

    func prepareCanvas() {
        canvasModel.canvas.backgroundColor = .clear
        canvasModel.canvas.isOpaque = false
        canvasModel.canvas.drawingPolicy = .anyInput
        applyTool()
    }

    func setColor(_ color: Color) {
        selectedColor = color
        applyTool()
    }

    func setBrushSize(_ width: CGFloat) {
        brushSize = width
        applyTool()
    }

    func clearCanvas() {
        canvasModel.clear()
        updateUndoStates()
    }

    func resetLiveState() {
        partnerImage = nil
        lastPartnerDoodleId = nil
        lastPartnerLiveId = nil
    }

    func undo() {
        canvasModel.undo()
        updateUndoStates()
    }

    func updateUndoStates() {
        canUndo = canvasModel.canUndo
    }

    func save(using handler: ((UIImage) async throws -> Void)?) async throws {
        guard let handler else { throw DoodleLiveError.missingSaveHandler }
        guard let snapshot = canvasModel.captureSnapshot() else {
            throw DoodleLiveError.snapshotFailed
        }
        isSaving = true
        defer { isSaving = false }
        try await handler(snapshot)
        await MainActor.run {
            lastSavedAt = Date()
        }
    }

    func loadPartnerDoodle(using loader: (() async throws -> [Doodle])?, currentUserId: String?) async {
        guard let loader else { return }
        do {
            let doodles = try await loader()
            // Only show partner doodles; ignore my own so the canvas stays clean.
            guard let target = doodles.first(where: { $0.senderId != currentUserId }) else {
                return
            }
            // Avoid unnecessary decode if already showing this one
            if target.id == lastPartnerDoodleId {
                return
            }
            if let image = try await decodeImage(from: target) {
                await MainActor.run {
                    self.partnerImage = image
                    self.lastPartnerDoodleId = target.id
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    func updatePartnerLive(doodle: LiveDoodle) async {
        if doodle.id == lastPartnerLiveId { return }
        guard let image = decodeBase64(content: doodle.contentBase64) else { return }
        partnerImage = image
        lastPartnerLiveId = doodle.id
    }

    private func decodeImage(from doodle: Doodle) async throws -> UIImage? {
        if let content = doodle.content {
            let payload: String
            if let commaIndex = content.firstIndex(of: ",") {
                payload = String(content[content.index(after: commaIndex)...])
            } else {
                payload = content
            }
            if let data = Data(base64Encoded: payload),
               let image = UIImage(data: data) {
                return image
            }
        }

        if let storagePath = doodle.storagePath,
           let url = URL(string: "https://ahtkqcaxeycxvwntjcxp.supabase.co/storage/v1/object/public/storage/\(storagePath)") {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return UIImage(data: data)
        }

        return nil
    }

    private func applyTool() {
        let color = UIColor(selectedColor)
        canvasModel.canvas.tool = PKInkingTool(.marker, color: color, width: brushSize)
    }

    private func decodeBase64(content: String) -> UIImage? {
        let payload: String
        if let commaIndex = content.firstIndex(of: ",") {
            payload = String(content[content.index(after: commaIndex)...])
        } else {
            payload = content
        }
        guard let data = Data(base64Encoded: payload) else { return nil }
        return UIImage(data: data)
    }
}

enum DoodleLiveError: LocalizedError {
    case missingSaveHandler
    case snapshotFailed

    var errorDescription: String? {
        switch self {
        case .missingSaveHandler:
            return "Save is unavailable right now."
        case .snapshotFailed:
            return "Could not capture your doodle."
        }
    }
}

// MARK: - Styles

enum LockScreenStyle: CaseIterable {
    case neonGrid
    case sunsetGlass
    case cosmic
    case vaporWave
    case midnightCandy

    var title: String {
        switch self {
        case .neonGrid: return "neon grid"
        case .sunsetGlass: return "sunset glass"
        case .cosmic: return "cosmic haze"
        case .vaporWave: return "vapor wave"
        case .midnightCandy: return "midnight candy"
        }
    }

    var accent: Color {
        switch self {
        case .neonGrid: return Color(red: 0.46, green: 0.96, blue: 1.0)
        case .sunsetGlass: return Color(red: 1.0, green: 0.74, blue: 0.37)
        case .cosmic: return Color(red: 0.78, green: 0.53, blue: 1.0)
        case .vaporWave: return Color(red: 1.0, green: 0.62, blue: 0.88)
        case .midnightCandy: return Color(red: 0.98, green: 0.31, blue: 0.45)
        }
    }

    var background: AnyView {
        switch self {
        case .neonGrid:
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.04, blue: 0.12),
                        Color(red: 0.19, green: 0.05, blue: 0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .sunsetGlass:
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.63, blue: 0.45),
                        Color(red: 0.98, green: 0.32, blue: 0.56),
                        Color(red: 0.27, green: 0.05, blue: 0.35)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .cosmic:
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.10, blue: 0.22),
                        Color(red: 0.16, green: 0.20, blue: 0.38),
                        Color(red: 0.05, green: 0.04, blue: 0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        case .vaporWave:
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.42, green: 0.77, blue: 0.98),
                        Color(red: 0.99, green: 0.68, blue: 0.90),
                        Color(red: 0.89, green: 0.53, blue: 0.97)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .midnightCandy:
            return AnyView(
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.02, blue: 0.10),
                        Color(red: 0.10, green: 0.05, blue: 0.22),
                        Color(red: 0.30, green: 0.08, blue: 0.25)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    var chipGradient: LinearGradient {
        switch self {
        case .neonGrid:
            return LinearGradient(colors: [.cyan, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .sunsetGlass:
            return LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .cosmic:
            return LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)
        case .vaporWave:
            return LinearGradient(colors: [.mint, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .midnightCandy:
            return LinearGradient(colors: [Color(red: 0.6, green: 0.2, blue: 0.4), .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

private struct StyleChip: View {
    let style: LockScreenStyle
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(style.chipGradient)
                .frame(width: 44, height: 28)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                )
            Text(style.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.22 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.white.opacity(0.6) : Color.white.opacity(0.15), lineWidth: 1.2)
        )
    }
}

#if DEBUG
#Preview {
    DoodleLiveLockScreenView(
        userName: "You",
        partnerName: "Partner",
        userId: "user-123",
        coupleKey: "couple",
        onSaveDoodle: { _ in },
        loadDoodles: {
            return [
                Doodle(
                    id: UUID(),
                    coupleKey: "couple",
                    senderId: "partner",
                    senderName: "Partner",
                    storagePath: nil,
                    content: nil,
                    isViewed: false,
                    createdAt: Date()
                )
            ]
        },
        onPublishLive: { _ in },
        onFetchLive: { nil },
        onGetCoupleKey: { "couple" },
        supabaseURL: URL(string: "https://example.supabase.co"),
        supabaseAnonKey: "anon-key",
        accessToken: "access"
    )
}
#endif

private struct TransparentCanvasView: UIViewRepresentable {
    let canvasView: PKCanvasView
    var onDrawingChanged: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) { }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: TransparentCanvasView

        init(parent: TransparentCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.onDrawingChanged?()
        }
    }
}
