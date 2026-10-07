import SwiftUI
import PhotosUI
import AVKit

@main
struct LiveCutApp: App {
    var body: some Scene {
        WindowGroup {
            LiveCutRootView()
                .preferredColorScheme(.dark)
        }
    }
}

private enum SessionConfirmation: String, Identifiable {
    case exit
    case replace
    case replaceAfterSuccess

    var id: String { rawValue }
}

struct LiveCutRootView: View {
    @State private var model = LiveCutModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickerPresented = false
    @State private var confirmation: SessionConfirmation?
    @State private var duplicateAlert = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            AppBackground()

            switch model.screen {
            case .home:
                HomeView { pickerPresented = true }
                    .transition(.opacity)
            case .loading:
                LoadingView(message: model.loadingMessage, cancel: model.cancelLoading)
                    .transition(.opacity)
            case .rejected(let reason):
                RejectedView(reason: reason) {
                    model.retryAfterRejection()
                    pickerPresented = true
                } cancel: {
                    model.finishSession()
                }
                .transition(.opacity)
            case .editor:
                EditorView(
                    model: model,
                    exit: { confirmation = .exit },
                    replace: { confirmation = .replace },
                    export: {
                        if model.requestExport() { duplicateAlert = true }
                        else if model.notice == nil { model.export() }
                    }
                )
                .transition(.opacity)
            }

            if let phase = model.exportPhase {
                ExportProgressOverlay(phase: phase)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: model.screen)
        .photosPicker(
            isPresented: $pickerPresented,
            selection: $pickerItem,
            matching: .videos,
            preferredItemEncoding: .current
        )
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            model.load(item)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.handleBackgrounding() }
        }
        .confirmationDialog(
            "离开当前视频？",
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmation
        ) { choice in
            Button(choice == .exit ? "结束并返回首页" : "选择另一个视频", role: .destructive) {
                model.prepareForNewVideo()
                confirmation = nil
                if choice != .exit { pickerPresented = true }
            }
            Button("继续编辑", role: .cancel) { confirmation = nil }
        } message: { _ in
            Text("当前视频的编辑状态和已导出标记将不再保留，但已经保存到系统相册的 Live Photo 不受影响。")
        }
        .alert("该片段已经导出过", isPresented: $duplicateAlert) {
            Button("取消", role: .cancel) {}
            Button("仍然导出") { model.export() }
        } message: {
            Text("开始、结束和封面帧与本次会话中的一个已导出片段相同。")
        }
        .alert(item: $model.notice) { notice in
            if notice.offersSettings {
                return Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .default(Text("前往设置"), action: model.openSettings),
                    secondaryButton: .cancel(Text("返回调整"), action: model.returnToTrim)
                )
            }
            if notice.canRetry {
                return Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .default(Text("重试"), action: model.export),
                    secondaryButton: .cancel(Text("返回调整"), action: model.returnToTrim)
                )
            }
            return Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("返回调整"), action: model.returnToTrim))
        }
        .sheet(item: $model.completedRecord) { _ in
            ExportSuccessSheet(
                continueCurrent: model.continueCurrentVideo,
                chooseAnother: { confirmation = .replaceAfterSuccess },
                finish: model.finishSession
            )
            .presentationDetents([.height(470)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground(LCColor.surface)
            .interactiveDismissDisabled()
        }
        .onChange(of: confirmation) { _, value in
            if value == .replaceAfterSuccess { model.completedRecord = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "当前状态") {
            UIAccessibility.post(notification: .announcement, argument: model.statusAnnouncement)
        }
    }
}

private struct HomeView: View {
    let selectVideo: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 34)

            VStack(spacing: 10) {
                Text("LiveCut")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(red: 0.55, green: 0.79, blue: 1)], startPoint: .top, endPoint: .bottom))
                    .accessibilityAddTraits(.isHeader)
                Text("从一段视频中连续截取多个 Live Photo")
                    .font(.subheadline)
                    .foregroundStyle(LCColor.secondary)
                    .multilineTextAlignment(.center)
            }

            HeroConversionGraphic()
                .padding(.top, 10)

            Spacer(minLength: 12)

            VStack(spacing: 16) {
                PrimaryActionButton(title: "从相册选择视频", icon: "photo.on.rectangle.angled", action: selectVideo)
                Label("视频仅在本机处理", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(LCColor.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

private struct LoadingView: View {
    let message: String
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(icon: "xmark", label: "取消载入", action: cancel)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LCColor.surface)
                        .frame(width: 184, height: 248)
                        .overlay {
                            LinearGradient(colors: [LCColor.blue.opacity(0.28), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 58, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(LCColor.cyan)
                }
                .shadow(color: LCColor.blue.opacity(0.2), radius: 26)

                VStack(spacing: 10) {
                    Text(message)
                        .font(.title3.bold())
                    Text("iCloud 素材可能需要更长时间，请保持网络连接")
                        .font(.subheadline)
                        .foregroundStyle(LCColor.secondary)
                        .multilineTextAlignment(.center)
                }

                IndeterminateBar()
                    .frame(width: 238, height: 5)
            }

            Spacer()

            SecondaryActionButton(title: "取消", action: cancel)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
        }
    }
}

private struct IndeterminateBar: View {
    @State private var moving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.11))
                Capsule()
                    .fill(LCColor.accentGradient)
                    .frame(width: proxy.size.width * 0.38)
                    .offset(x: moving ? proxy.size.width * 0.62 : 0)
            }
        }
        .onAppear {
            if reduceMotion { moving = true }
            else {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { moving = true }
            }
        }
        .accessibilityLabel("正在载入")
    }
}

private struct RejectedView: View {
    let reason: String
    let retry: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 62))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.orange)
            VStack(spacing: 10) {
                Text("无法使用这个视频").font(.title2.bold())
                Text(reason)
                    .font(.body)
                    .foregroundStyle(LCColor.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            Spacer()
            VStack(spacing: 12) {
                PrimaryActionButton(title: "重新选择视频", icon: "photo.on.rectangle", action: retry)
                Button("返回首页", action: cancel)
                    .font(.headline)
                    .foregroundStyle(LCColor.cyan)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
    }
}

private struct EditorView: View {
    @Bindable var model: LiveCutModel
    let exit: () -> Void
    let replace: () -> Void
    let export: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditorNavigationBar(model: model, exit: exit, replace: replace)

            ScrollView {
                VStack(spacing: 20) {
                    VideoPreview(model: model)

                    if model.mode == .trim {
                        trimControls
                    } else {
                        coverControls
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .disabled(model.exportPhase != nil)
            .safeAreaInset(edge: .bottom) {
                EditorActionBar(model: model, export: export)
            }
        }
        .background(LCColor.canvas.opacity(0.9))
    }

    private var trimControls: some View {
        ClipTimeline(model: model)
    }

    private var coverControls: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择静止封面")
                        .font(.headline)
                    Text("封面只能位于当前片段内")
                        .font(.caption)
                        .foregroundStyle(LCColor.secondary)
                }
                Spacer()
                Text(formatTime(model.clip.cover))
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(LCColor.cyan)
            }
            CoverTimeline(model: model)
            Label("拖动白色指针选择封面，松手后会吸附到真实视频帧", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(LCColor.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(LCColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(LCColor.line)
        }
    }
}

private struct EditorNavigationBar: View {
    @Bindable var model: LiveCutModel
    let exit: () -> Void
    let replace: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if model.mode == .trim {
                CircleIconButton(icon: "xmark", label: "退出编辑", action: exit)
            } else {
                Button(action: model.returnToTrim) {
                    Label("返回调整", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LCColor.cyan)
                        .frame(minWidth: 96, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            Spacer()
            Text(model.mode == .trim ? "截取片段" : "选择封面")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()

            if model.mode == .trim {
                Button("更换视频", action: replace)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(LCColor.cyan)
                    .frame(minWidth: 88, minHeight: 44, alignment: .trailing)
            } else {
                Color.clear.frame(width: 96, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }
}

private struct VideoPreview: View {
    @Bindable var model: LiveCutModel

    private var timeLabel: String {
        if model.mode == .cover { return "封面  \(formatTime(model.clip.cover))" }
        let total = model.source.map { formatTime($0.duration) } ?? "0:00.0"
        return "\(formatTime(model.playbackTime))  /  \(total)"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black)

            if let player = model.player {
                VideoPlayer(player: player)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            if !model.isClipPreviewing {
                Button(action: model.toggleClipPreview) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 62, height: 62)
                        .background(.black.opacity(0.5), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.22)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.mode == .trim ? "预览所选片段" : "从当前封面开始预览")
            }

            VStack {
                Spacer()
                HStack {
                    Text(timeLabel)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.black.opacity(0.62), in: Capsule())
                    Spacer()
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption)
                        .padding(9)
                        .background(.black.opacity(0.62), in: Circle())
                        .accessibilityLabel("保留原视频声音")
                }
                .padding(12)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.1))
        }
    }
}

private struct EditorActionBar: View {
    @Bindable var model: LiveCutModel
    let export: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { actionButtons }
            VStack(spacing: 10) { actionButtons }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .overlay(alignment: .top) { Divider().overlay(Color.white.opacity(0.08)) }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if model.mode == .trim {
            SecondaryActionButton(
                title: model.isClipPreviewing ? "暂停预览" : "预览片段",
                icon: model.isClipPreviewing ? "pause.fill" : "play.fill",
                action: model.toggleClipPreview
            )
            PrimaryActionButton(title: "下一步：选择封面", icon: "photo", action: model.enterCoverMode)
        } else {
            SecondaryActionButton(title: "预览 Live Photo", icon: "livephoto", action: model.previewFromCover)
            PrimaryActionButton(title: "生成并保存", icon: "square.and.arrow.down", action: export)
        }
    }
}

private struct ExportProgressOverlay: View {
    let phase: ExportPhase

    var body: some View {
        ZStack {
            Color.black.opacity(0.68).ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.1), lineWidth: 7)
                    ProgressView().tint(LCColor.cyan).scaleEffect(1.45)
                }
                .frame(width: 74, height: 74)

                VStack(spacing: 7) {
                    Text(phase.title).font(.title3.bold())
                    Text(phase.detail)
                        .font(.subheadline)
                        .foregroundStyle(LCColor.secondary)
                        .multilineTextAlignment(.center)
                }

                Label("请保持 LiveCut 在前台", systemImage: "iphone")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 30)
            .frame(maxWidth: 330)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.12))
            }
            .shadow(color: .black.opacity(0.4), radius: 28, y: 18)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

private struct ExportSuccessSheet: View {
    let continueCurrent: () -> Void
    let chooseAnother: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            ZStack {
                Circle().fill(LCColor.green.opacity(0.16)).frame(width: 86, height: 86)
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(LCColor.green)
            }
            .padding(.top, 22)

            Text("已保存到系统相册")
                .font(.title2.bold())
                .padding(.top, 15)
            Text("已在时间轴标记这个片段，你可以继续截取当前视频。")
                .font(.subheadline)
                .foregroundStyle(LCColor.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 8)

            VStack(spacing: 11) {
                PrimaryActionButton(title: "继续截取当前视频", icon: "scissors", action: continueCurrent)
                SecondaryActionButton(title: "选择另一个视频", icon: "photo.on.rectangle", action: chooseAnother)
                Button("完成", action: finish)
                    .font(.headline)
                    .foregroundStyle(LCColor.cyan)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
        }
        .background(LCColor.surface)
    }
}
