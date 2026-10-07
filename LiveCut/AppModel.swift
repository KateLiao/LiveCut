import SwiftUI
import PhotosUI
import AVKit
import UniformTypeIdentifiers

struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent("source-" + UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: target)
            return PickedMovie(url: target)
        }
    }
}

struct FrameThumbnail: Identifiable {
    let id = UUID()
    let time: Double
    let image: CGImage
}

struct ExportRecord: Identifiable, Equatable {
    let id = UUID()
    let sequence: Int
    let clip: Clip
    let exportedAt: Date
}

enum AppScreen: Equatable {
    case home
    case loading
    case rejected(String)
    case editor
}

enum EditorMode: Equatable {
    case trim
    case cover
}

enum ExportPhase: Equatable {
    case generating
    case saving

    var title: String {
        switch self {
        case .generating: "正在生成 Live Photo"
        case .saving: "正在保存到相册"
        }
    }

    var detail: String {
        switch self {
        case .generating: "正在整理画面、声音与封面帧"
        case .saving: "即将完成，请不要退出 LiveCut"
        }
    }
}

struct EditorNotice: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let offersSettings: Bool
    let canRetry: Bool
}

@MainActor
@Observable
final class LiveCutModel {
    var screen: AppScreen = .home
    var mode: EditorMode = .trim
    var source: Source?
    var clip = Clip.initial(3)
    var player: AVPlayer?
    var thumbnails: [FrameThumbnail] = []
    var precisionThumbnails: [FrameThumbnail] = []
    var coverThumbnails: [FrameThumbnail] = []
    var timelineZoom = 1.0
    var timelineFocusRevision = 0
    var records: [ExportRecord] = []
    var exportPhase: ExportPhase?
    var completedRecord: ExportRecord?
    var notice: EditorNotice?
    var isClipPreviewing = false
    var playbackTime = 0.0
    var loadingMessage = "正在载入视频"
    var statusAnnouncement = ""
    var task: Task<Void, Never>?

    private let pipeline = MediaPipeline()
    private var playbackObserver: Any?
    private var playbackObserverPlayer: AVPlayer?

    var isBusy: Bool { screen == .loading || exportPhase != nil }
    var hasSession: Bool { source != nil }

    func load(_ item: PhotosPickerItem) {
        task?.cancel()
        pause()
        screen = .loading
        loadingMessage = "正在载入视频"
        statusAnnouncement = loadingMessage

        task = Task {
            var importedURL: URL?
            do {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    throw MediaFailure.message("未能获取这个视频，请重新选择。")
                }
                importedURL = movie.url
                loadingMessage = "正在检查视频"
                let inspected = try await pipeline.inspect(movie.url)
                try Task.checkCancellation()

                if let previous = source {
                    try? FileManager.default.removeItem(at: previous.url)
                }
                source = inspected
                clip = .initial(inspected.duration)
                timelineZoom = 1
                timelineFocusRevision += 1
                records = []
                mode = .trim
                player = AVPlayer(url: inspected.url)
                playbackTime = clip.start
                configureLoopObserver()
                screen = .editor
                statusAnnouncement = "视频已载入，可以开始截取。"
                await refreshThumbnails()
                seek(to: clip.start)
            } catch is CancellationError {
                if let importedURL { try? FileManager.default.removeItem(at: importedURL) }
                if source == nil { screen = .home }
            } catch {
                if let importedURL { try? FileManager.default.removeItem(at: importedURL) }
                screen = .rejected(error.localizedDescription)
                statusAnnouncement = error.localizedDescription
            }
        }
    }

    func refreshThumbnails() async {
        guard let source else { return }
        let overviewTimes = evenlySpacedTimes(start: 0, end: source.duration, count: 12)
        thumbnails = await makeThumbnails(source: source, times: overviewTimes)
        await refreshPrecisionThumbnails()
        await refreshCoverThumbnails()
    }

    func setTimelineZoom(_ value: Double, refreshFrames: Bool) {
        timelineZoom = min(max(1, value), 30)
        guard refreshFrames else { return }
        Task { await refreshTimelineThumbnails(for: timelineZoom) }
    }

    func refreshTimelineThumbnails(for zoom: Double) async {
        guard let source else { return }
        let count = min(180, max(12, Int((12 * zoom).rounded())))
        thumbnails = await makeThumbnails(
            source: source,
            times: evenlySpacedTimes(start: 0, end: source.duration, count: count)
        )
    }

    func refreshPrecisionThumbnails() async {
        guard let source else { return }
        let side = max(0.75, (5 - clip.duration) / 2 + 0.5)
        var lower = max(0, clip.start - side)
        var upper = min(source.duration, clip.end + side)
        if upper - lower < 5, source.duration >= 5 {
            if lower == 0 { upper = 5 }
            else if upper == source.duration { lower = source.duration - 5 }
        }
        precisionThumbnails = await makeThumbnails(
            source: source,
            times: evenlySpacedTimes(start: lower, end: upper, count: 10)
        )
    }

    func refreshCoverThumbnails() async {
        guard let source else { return }
        let times = evenlySpacedTimes(start: clip.start, end: clip.end, count: 8)
        coverThumbnails = await makeThumbnails(source: source, times: times)
    }

    func updateClipStart(_ value: Double) {
        guard let source else { return }
        pause()
        let oldCover = clip.cover
        clip = clip.replacingStart(value, total: source.duration)
        if oldCover != clip.cover {
            statusAnnouncement = "原封面已超出新片段，已改为片段第一帧。"
        }
        seek(to: clip.start)
    }

    func updateClipEnd(_ value: Double) {
        guard let source else { return }
        pause()
        clip = clip.replacingEnd(value, total: source.duration)
        seek(to: clip.end.nextDown)
    }

    func moveClip(centeredAt time: Double) {
        guard let source else { return }
        let length = clip.duration
        let start = min(max(0, time - length / 2), source.duration - length)
        let coverOffset = max(0, clip.cover - clip.start)
        clip.start = start
        clip.end = start + length
        clip.cover = min(clip.end.nextDown, clip.start + coverOffset)
        pause()
        seek(to: clip.start)
    }

    func moveClip(toStart value: Double, baseline: Clip) {
        guard let source else { return }
        pause()
        clip = baseline.moved(toStart: value, total: source.duration)
        seek(to: clip.start)
    }

    func snapStartToFrame() {
        guard let source else { return }
        let minimumStart = max(0, clip.end - 5)
        let maximumStart = clip.end - 1
        clip.start = source.nearest(clip.start, start: minimumStart, end: maximumStart.nextUp)
        clip.start = min(max(minimumStart, clip.start), maximumStart)
        if clip.cover < clip.start { clip.cover = clip.start }
        seek(to: clip.start)
        Task { await refreshCoverThumbnails() }
    }

    func snapEndToFrame() {
        guard let source else { return }
        let minimumEnd = clip.start + 1
        let maximumEnd = min(source.duration, clip.start + 5)
        if clip.end >= source.duration - 0.0001 {
            clip.end = source.duration
        } else {
            clip.end = source.nearest(clip.end, start: minimumEnd, end: maximumEnd.nextUp)
            clip.end = min(max(minimumEnd, clip.end), maximumEnd)
        }
        if clip.cover >= clip.end { clip.cover = clip.start }
        seek(to: clip.end.nextDown)
        Task { await refreshCoverThumbnails() }
    }

    func snapClipToFrames() {
        guard let source else { return }
        pause()
        clip.start = source.nearest(clip.start)
        if clip.end < source.duration { clip.end = source.nearest(clip.end) }
        clip.end = max(clip.start + 1, min(clip.end, source.duration))
        if clip.duration > 5 { clip.end = clip.start + 5 }
        clip.cover = source.nearest(clip.cover, start: clip.start, end: clip.end)
        seek(to: mode == .cover ? clip.cover : clip.start)
        Task {
            await refreshPrecisionThumbnails()
            await refreshCoverThumbnails()
        }
    }

    func snapMovedClipToFrames() {
        guard let source else { return }
        let length = clip.duration
        let coverOffset = max(0, clip.cover - clip.start)
        let snappedStart = source.nearest(clip.start)
        clip.start = min(max(0, snappedStart), max(0, source.duration - length))
        clip.end = clip.start + length
        clip.cover = min(clip.end.nextDown, clip.start + coverOffset)
        seek(to: clip.start)
        Task { await refreshCoverThumbnails() }
    }

    func adjustStart(by delta: Double) {
        updateClipStart(clip.start + delta)
        snapStartToFrame()
    }

    func adjustEnd(by delta: Double) {
        updateClipEnd(clip.end + delta)
        snapEndToFrame()
    }

    func selectCover(_ time: Double, snap: Bool = false) {
        guard let source else { return }
        pause()
        clip.cover = min(max(clip.start, time), clip.end.nextDown)
        if snap { clip.cover = source.nearest(clip.cover, start: clip.start, end: clip.end) }
        seek(to: clip.cover)
    }

    func enterCoverMode() {
        snapClipToFrames()
        guard let source, clip.validate(total: source.duration) else {
            notice = EditorNotice(title: "片段范围需要调整", message: "片段时长需要在 1～5 秒之间。", offersSettings: false, canRetry: false)
            return
        }
        mode = .cover
        selectCover(clip.cover, snap: true)
        Task { await refreshCoverThumbnails() }
    }

    func returnToTrim() {
        pause()
        mode = .trim
        seek(to: clip.start)
    }

    func toggleClipPreview() {
        guard let player else { return }
        if isClipPreviewing {
            pause()
            return
        }
        if player.currentTime().seconds < clip.start || player.currentTime().seconds >= clip.end - 0.05 {
            seek(to: clip.start)
        }
        isClipPreviewing = true
        player.play()
    }

    func previewFromCover() {
        seek(to: clip.cover)
        isClipPreviewing = true
        player?.play()
    }

    func requestExport() -> Bool {
        snapClipToFrames()
        guard let source, clip.validate(total: source.duration) else {
            notice = EditorNotice(title: "无法生成", message: "请把片段调整为 1～5 秒，并确保封面位于片段内。", offersSettings: false, canRetry: false)
            return false
        }
        let frameTolerance = 1 / Double(max(1, source.fps))
        return records.contains {
            abs($0.clip.start - clip.start) <= frameTolerance &&
            abs($0.clip.end - clip.end) <= frameTolerance &&
            abs($0.clip.cover - clip.cover) <= frameTolerance
        }
    }

    func export() {
        guard let source, exportPhase == nil else { return }
        let submitted = clip
        pause()
        exportPhase = .generating
        statusAnnouncement = ExportPhase.generating.title

        task = Task {
            do {
                let pair = try await pipeline.generate(source: source, clip: submitted)
                defer { pair.clean() }
                try Task.checkCancellation()
                exportPhase = .saving
                statusAnnouncement = ExportPhase.saving.title
                try await pipeline.save(pair)
                try Task.checkCancellation()

                let record = ExportRecord(sequence: records.count + 1, clip: submitted, exportedAt: .now)
                records.append(record)
                completedRecord = record
                exportPhase = nil
                statusAnnouncement = "已保存到系统相册"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                exportPhase = nil
                notice = EditorNotice(title: "生成已中断", message: "片段与封面设置已保留，可以直接重试。", offersSettings: false, canRetry: true)
            } catch {
                exportPhase = nil
                let message = error.localizedDescription
                notice = EditorNotice(
                    title: message.contains("权限") || message.contains("设置") ? "无法保存到相册" : "生成失败",
                    message: message + "\n片段与封面设置已保留。",
                    offersSettings: message.contains("权限") || message.contains("设置"),
                    canRetry: true
                )
                statusAnnouncement = message
            }
        }
    }

    func continueCurrentVideo() {
        guard let source, let completedRecord else { return }
        clip = completedRecord.clip.next(total: source.duration)
        clip.cover = clip.start
        self.completedRecord = nil
        mode = .trim
        timelineFocusRevision += 1
        seek(to: clip.start)
        Task {
            await refreshPrecisionThumbnails()
            await refreshCoverThumbnails()
        }
    }

    func preview(_ record: ExportRecord) {
        clip = record.clip
        mode = .trim
        timelineFocusRevision += 1
        seek(to: clip.start)
        statusAnnouncement = "已导出片段 \(record.sequence)，时长 \(formatDuration(record.clip.duration))。"
    }

    func finishSession() {
        reset(removeSource: true)
    }

    func prepareForNewVideo() {
        reset(removeSource: true)
    }

    func cancelLoading() {
        task?.cancel()
        if source == nil { screen = .home }
        else { screen = .editor }
    }

    func handleBackgrounding() {
        pause()
        if exportPhase != nil {
            task?.cancel()
        }
    }

    func retryAfterRejection() {
        screen = .home
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func pause() {
        player?.pause()
        isClipPreviewing = false
    }

    func seek(to seconds: Double) {
        let safe = max(0, seconds)
        playbackTime = safe
        player?.seek(to: CMTime(seconds: safe, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func configureLoopObserver() {
        if let playbackObserver, let playbackObserverPlayer {
            playbackObserverPlayer.removeTimeObserver(playbackObserver)
        }
        guard let player else { return }
        playbackObserverPlayer = player
        playbackObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.05, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self, self.isClipPreviewing else { return }
            self.playbackTime = time.seconds
            if time.seconds >= self.clip.end - 0.03 {
                self.seek(to: self.clip.start)
                self.player?.play()
            }
        }
    }

    private func reset(removeSource: Bool) {
        task?.cancel()
        pause()
        if let playbackObserver, let playbackObserverPlayer {
            playbackObserverPlayer.removeTimeObserver(playbackObserver)
        }
        playbackObserver = nil
        playbackObserverPlayer = nil
        if removeSource, let source { try? FileManager.default.removeItem(at: source.url) }
        source = nil
        player = nil
        thumbnails = []
        precisionThumbnails = []
        coverThumbnails = []
        timelineZoom = 1
        timelineFocusRevision += 1
        records = []
        completedRecord = nil
        exportPhase = nil
        notice = nil
        mode = .trim
        screen = .home
    }

    private func evenlySpacedTimes(start: Double, end: Double, count: Int) -> [Double] {
        guard count > 1, end > start else { return [start] }
        return (0..<count).map { index in
            start + (end - start) * Double(index) / Double(count)
        }
    }

    private func makeThumbnails(source: Source, times: [Double]) async -> [FrameThumbnail] {
        let asset = AVURLAsset(url: source.url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 260, height: 180)
        let tolerance = CMTime(seconds: 1 / Double(max(1, source.fps)), preferredTimescale: 60000)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        var result: [FrameThumbnail] = []
        for time in times {
            guard !Task.isCancelled else { break }
            if let frame = try? await generator.image(at: CMTime(seconds: min(time, source.duration.nextDown), preferredTimescale: 60000)) {
                result.append(FrameThumbnail(time: frame.actualTime.seconds, image: frame.image))
            }
        }
        return result
    }
}

func formatTime(_ value: Double) -> String {
    guard value.isFinite else { return "0:00.0" }
    let minutes = Int(value) / 60
    let seconds = value - Double(minutes * 60)
    return String(format: "%d:%04.1f", minutes, seconds)
}

func formatDuration(_ value: Double) -> String {
    String(format: "%.1f 秒", value)
}
