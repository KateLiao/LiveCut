import SwiftUI

struct ClipTimeline: View {
    @Bindable var model: LiveCutModel
    @State private var initialWindow: Clip?
    @State private var initialStart: Double?
    @State private var initialEnd: Double?
    @State private var zoomAtGestureStart = 1.0
    @State private var viewportOffset = 0.0
    @State private var viewportDragStart: Double?
    @State private var viewportDragBaseline: Clip?

    var body: some View {
        VStack(spacing: 9) {
            HStack(alignment: .center) {
                Text("0:00.0")
                Spacer()
                Text("时长  \(formatDuration(model.clip.duration))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LCColor.cyan)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(LCColor.blue.opacity(0.13), in: Capsule())
                    .overlay(Capsule().strokeBorder(LCColor.blue.opacity(0.35)))
                    .accessibilityLabel("当前片段时长 \(formatDuration(model.clip.duration))")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(model.source.map { formatTime($0.duration) } ?? "0:00.0")
                    Text(String(format: "×%.1f", model.timelineZoom))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(model.timelineZoom > 1 ? LCColor.cyan : LCColor.secondary)
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(LCColor.secondary)

            GeometryReader { viewport in
                let duration = max(0.001, model.source?.duration ?? 1)
                let contentWidth = max(viewport.size.width, viewport.size.width * model.timelineZoom)
                let maximumOffset = max(0, contentWidth - viewport.size.width)
                let timelineY = 35.0
                let timelineHeight = 82.0
                let startX = contentWidth * model.clip.start / duration
                let endX = contentWidth * model.clip.end / duration
                let selectionWidth = max(2, endX - startX)
                let dragSurfaceWidth = max(18, selectionWidth - 44)
                let dragSurfaceX = startX + (selectionWidth - dragSurfaceWidth) / 2

                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        ThumbnailStrip(thumbnails: model.thumbnails, cornerRadius: 10)
                            .frame(height: timelineHeight)
                            .offset(y: timelineY)

                        ForEach(model.records) { record in
                            let markerX = contentWidth * record.clip.start / duration
                            let markerWidth = max(24, contentWidth * record.clip.duration / duration)
                            Button {
                                model.preview(record)
                            } label: {
                                ZStack {
                                    Rectangle().fill(LCColor.green.opacity(0.48))
                                    Text("✓ \(record.sequence)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                                .frame(width: markerWidth, height: timelineHeight)
                            }
                            .buttonStyle(.plain)
                            .offset(x: markerX, y: timelineY)
                            .accessibilityLabel("已导出片段 \(record.sequence)，时长 \(formatDuration(record.clip.duration))")
                        }

                        Rectangle()
                            .fill(Color.black.opacity(0.52))
                            .frame(width: max(0, startX), height: timelineHeight)
                            .offset(y: timelineY)

                        Rectangle()
                            .fill(Color.black.opacity(0.52))
                            .frame(width: max(0, contentWidth - endX), height: timelineHeight)
                            .offset(x: endX, y: timelineY)

                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LCColor.blue.opacity(0.10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(LCColor.blue, lineWidth: 3)
                            }
                            .frame(width: selectionWidth, height: timelineHeight)
                            .offset(x: startX, y: timelineY)
                            .allowsHitTesting(false)

                        Color.clear
                            .frame(width: dragSurfaceWidth, height: timelineHeight)
                            .contentShape(Rectangle())
                            .offset(x: dragSurfaceX, y: timelineY)
                            .highPriorityGesture(moveGesture(width: contentWidth, duration: duration))
                            .accessibilityLabel("当前片段窗口")
                            .accessibilityValue("时长 \(formatDuration(model.clip.duration))")
                            .accessibilityHint("左右拖动可以等长移动片段")
                            .zIndex(4)

                        TimelineHandle(side: .left)
                            .frame(width: 28, height: timelineHeight)
                            .offset(x: startX, y: timelineY)
                            .highPriorityGesture(startGesture(width: contentWidth, duration: duration))
                            .accessibilityLabel("片段开始拖拽柄")
                            .accessibilityValue(formatTime(model.clip.start))
                            .accessibilityAdjustableAction { direction in
                                model.adjustStart(by: direction == .increment ? 0.1 : -0.1)
                            }
                            .zIndex(3)

                        TimelineHandle(side: .right)
                            .frame(width: 28, height: timelineHeight)
                            .offset(x: max(0, endX - 28), y: timelineY)
                            .highPriorityGesture(endGesture(width: contentWidth, duration: duration))
                            .accessibilityLabel("片段结束拖拽柄")
                            .accessibilityValue(formatTime(model.clip.end))
                            .accessibilityAdjustableAction { direction in
                                model.adjustEnd(by: direction == .increment ? 0.1 : -0.1)
                            }
                            .zIndex(3)

                        if model.isClipPreviewing {
                            PlaybackIndicator(
                                x: min(max(0, contentWidth * model.playbackTime / duration), contentWidth),
                                width: contentWidth,
                                time: model.playbackTime,
                                timelineY: timelineY,
                                timelineHeight: timelineHeight
                            )
                            .allowsHitTesting(false)
                            .transition(.opacity)
                        }
                    }
                    .frame(width: contentWidth, height: 128)
                    .offset(x: -viewportOffset)
                    .frame(width: viewport.size.width, height: 128, alignment: .leading)
                    .clipped()

                    TimelineViewportControl(
                        offset: viewportOffset,
                        maximumOffset: maximumOffset,
                        viewportWidth: viewport.size.width,
                        contentWidth: contentWidth,
                        isEnabled: model.timelineZoom > 1.001
                    )
                    .frame(width: viewport.size.width, height: 27)
                    .offset(y: 136)
                    .gesture(viewportGesture(
                        viewportWidth: viewport.size.width,
                        contentWidth: contentWidth,
                        duration: duration
                    ))
                }
                .simultaneousGesture(zoomGesture(viewportWidth: viewport.size.width, duration: duration))
                .onChange(of: model.timelineFocusRevision) { _, _ in
                    centerSelection(viewportWidth: viewport.size.width, duration: duration)
                }
                .onChange(of: model.timelineZoom) { _, _ in
                    centerSelection(viewportWidth: viewport.size.width, duration: duration)
                }
            }
            .frame(height: 163)
            .animation(.linear(duration: 0.05), value: model.playbackTime)

            Label("双指缩放 · 拖动下方浏览柄移动视频窗口", systemImage: "arrow.left.and.right.and.arrow.up.and.down")
                .font(.caption2)
                .foregroundStyle(LCColor.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("时间轴缩放")
                .accessibilityValue(String(format: "%.1f 倍", model.timelineZoom))
                .accessibilityHint("向上或向下调整缩放比例")
                .accessibilityAdjustableAction { direction in
                    let factor = direction == .increment ? 1.5 : 1 / 1.5
                    let duration = max(0.001, model.source?.duration ?? 1)
                    model.setTimelineZoom(boundedZoom(model.timelineZoom * factor, duration: duration), refreshFrames: true)
                    zoomAtGestureStart = model.timelineZoom
                }
        }
        .onAppear { zoomAtGestureStart = model.timelineZoom }
    }

    private func zoomGesture(viewportWidth: Double, duration: Double) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                model.setTimelineZoom(boundedZoom(zoomAtGestureStart * Double(value), duration: duration), refreshFrames: false)
                centerSelection(viewportWidth: viewportWidth, duration: duration)
            }
            .onEnded { value in
                let finalZoom = boundedZoom(zoomAtGestureStart * Double(value), duration: duration)
                model.setTimelineZoom(finalZoom, refreshFrames: true)
                zoomAtGestureStart = model.timelineZoom
                centerSelection(viewportWidth: viewportWidth, duration: duration)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
    }

    private func viewportGesture(viewportWidth: Double, contentWidth: Double, duration: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if viewportDragStart == nil {
                    viewportDragStart = viewportOffset
                    viewportDragBaseline = model.clip
                    model.pause()
                }
                guard let viewportDragStart, let baseline = viewportDragBaseline else { return }
                let maximumOffset = max(0, contentWidth - viewportWidth)
                let thumbWidth = min(viewportWidth, max(52, viewportWidth * viewportWidth / max(viewportWidth, contentWidth)))
                let thumbTravel = max(1, viewportWidth - thumbWidth)
                let candidate = viewportDragStart + Double(value.translation.width) / thumbTravel * maximumOffset
                let newOffset = clampedViewportOffset(candidate, viewportWidth: viewportWidth, contentWidth: contentWidth)
                viewportOffset = newOffset
                let visibleStart = newOffset / contentWidth * duration
                let visibleEnd = (newOffset + viewportWidth) / contentWidth * duration
                let visibleClip = baseline.keptVisible(from: visibleStart, to: visibleEnd, total: duration)
                model.moveClip(toStart: visibleClip.start, baseline: baseline)
            }
            .onEnded { _ in
                viewportDragStart = nil
                viewportDragBaseline = nil
                Task { await model.refreshCoverThumbnails() }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
    }

    private func centerSelection(viewportWidth: Double, duration: Double) {
        let contentWidth = max(viewportWidth, viewportWidth * model.timelineZoom)
        let midpoint = (model.clip.start + model.clip.end) / 2
        let desired = contentWidth * midpoint / max(0.001, duration) - viewportWidth / 2
        viewportOffset = clampedViewportOffset(desired, viewportWidth: viewportWidth, contentWidth: contentWidth)
    }

    private func clampedViewportOffset(_ value: Double, viewportWidth: Double, contentWidth: Double) -> Double {
        min(max(0, value), max(0, contentWidth - viewportWidth))
    }

    private func boundedZoom(_ value: Double, duration: Double) -> Double {
        let selectionFitsViewport = duration / max(0.001, model.clip.duration)
        return min(max(1, value), min(30, max(1, selectionFitsViewport)))
    }

    private func moveGesture(width: Double, duration: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if initialWindow == nil {
                    initialWindow = model.clip
                    model.pause()
                }
                guard let initialWindow else { return }
                let delta = value.translation.width / max(1, width) * duration
                model.moveClip(toStart: initialWindow.start + delta, baseline: initialWindow)
            }
            .onEnded { _ in
                initialWindow = nil
                model.snapMovedClipToFrames()
            }
    }

    private func startGesture(width: Double, duration: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if initialStart == nil {
                    initialStart = model.clip.start
                    model.pause()
                }
                guard let initialStart else { return }
                let delta = value.translation.width / max(1, width) * duration
                model.updateClipStart(initialStart + delta)
            }
            .onEnded { _ in
                initialStart = nil
                model.snapStartToFrame()
                model.setTimelineZoom(boundedZoom(model.timelineZoom, duration: duration), refreshFrames: true)
                boundaryHaptic()
            }
    }

    private func endGesture(width: Double, duration: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if initialEnd == nil {
                    initialEnd = model.clip.end
                    model.pause()
                }
                guard let initialEnd else { return }
                let delta = value.translation.width / max(1, width) * duration
                model.updateClipEnd(initialEnd + delta)
            }
            .onEnded { _ in
                initialEnd = nil
                model.snapEndToFrame()
                model.setTimelineZoom(boundedZoom(model.timelineZoom, duration: duration), refreshFrames: true)
                boundaryHaptic()
            }
    }

    private func boundaryHaptic() {
        let reachedBoundary = model.clip.start <= 0.001 ||
            abs(model.clip.end - (model.source?.duration ?? 0)) <= 0.001 ||
            abs(model.clip.duration - 1) <= 0.05 ||
            abs(model.clip.duration - 5) <= 0.05
        if reachedBoundary { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }
}

private struct PlaybackIndicator: View {
    let x: Double
    let width: Double
    let time: Double
    let timelineY: Double
    let timelineHeight: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(formatTime(time))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(LCColor.blue, in: Capsule())
                .fixedSize()
                .offset(x: min(max(0, x - 32), max(0, width - 64)))

            Rectangle()
                .fill(.white)
                .frame(width: 2, height: timelineHeight + 10)
                .shadow(color: LCColor.blue, radius: 6)
                .offset(x: x - 1, y: timelineY - 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("当前播放位置")
        .accessibilityValue(formatTime(time))
    }
}

private struct TimelineHandle: View {
    enum Side { case left, right }
    let side: Side

    var body: some View {
        HStack(spacing: 0) {
            if side == .right { Spacer(minLength: 0) }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.white)
                .frame(width: 18, height: 82)
                .overlay {
                    HStack(spacing: 3) {
                        Capsule().fill(LCColor.blue).frame(width: 2, height: 24)
                        Capsule().fill(LCColor.blue).frame(width: 2, height: 24)
                    }
                }
                .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
            if side == .left { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .contentShape(Rectangle())
    }
}

private struct TimelineViewportControl: View {
    let offset: Double
    let maximumOffset: Double
    let viewportWidth: Double
    let contentWidth: Double
    let isEnabled: Bool

    var body: some View {
        let thumbWidth = min(viewportWidth, max(52, viewportWidth * viewportWidth / max(viewportWidth, contentWidth)))
        let travel = max(0, viewportWidth - thumbWidth)
        let progress = maximumOffset > 0 ? min(max(0, offset / maximumOffset), 1) : 0

        ZStack(alignment: .leading) {
            Capsule()
                .fill(LCColor.elevated)
                .frame(height: 7)
                .padding(.horizontal, 2)

            Capsule()
                .fill(isEnabled ? LCColor.blue.opacity(0.22) : LCColor.secondary.opacity(0.12))
                .overlay {
                    Capsule().strokeBorder(isEnabled ? LCColor.blue : LCColor.secondary.opacity(0.35), lineWidth: 1)
                }
                .frame(width: thumbWidth, height: 25)
                .overlay {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2.bold())
                        .foregroundStyle(isEnabled ? LCColor.cyan : LCColor.secondary)
                }
                .offset(x: travel * progress)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("视频窗口浏览柄")
        .accessibilityValue(isEnabled ? "可以左右拖动" : "放大时间轴后可用")
        .accessibilityHint("片段窗口离开可见范围时会吸附到最近边缘")
    }
}

struct CoverTimeline: View {
    @Bindable var model: LiveCutModel
    @State private var dragging = false

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                let span = max(0.001, model.clip.duration)
                let ratio = (model.clip.cover - model.clip.start) / span
                let pointerInset = 7.0
                let trackY = 7.0
                let trackHeight = max(1, proxy.size.height - 14)
                let usableWidth = max(1, proxy.size.width - pointerInset * 2)
                let x = pointerInset + min(max(0, ratio), 1) * usableWidth

                ZStack(alignment: .topLeading) {
                    ThumbnailStrip(thumbnails: model.coverThumbnails, cornerRadius: 10)
                        .frame(width: proxy.size.width, height: trackHeight)
                        .offset(y: trackY)
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(LCColor.blue, lineWidth: 2)
                        .frame(width: proxy.size.width, height: trackHeight)
                        .offset(y: trackY)
                    Rectangle()
                        .fill(.white)
                        .frame(width: 3, height: trackHeight)
                        .shadow(color: LCColor.blue, radius: 8)
                        .offset(x: x - 1.5, y: trackY)
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(LCColor.blue, lineWidth: 3))
                        .offset(x: x - 7, y: 0)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !dragging { dragging = true; model.pause() }
                            let ratio = min(max(0, (value.location.x - pointerInset) / usableWidth), 1)
                            model.selectCover(model.clip.start + ratio * span)
                        }
                        .onEnded { _ in
                            dragging = false
                            model.selectCover(model.clip.cover, snap: true)
                        }
                )
            }
            .frame(height: 98)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("封面帧")
            .accessibilityValue(formatTime(model.clip.cover))
            .accessibilityHint("左右滑动选择封面")
            .accessibilityAdjustableAction { direction in
                model.selectCover(model.clip.cover + (direction == .increment ? 0.1 : -0.1), snap: true)
            }

            HStack {
                Text(formatTime(model.clip.start))
                Spacer()
                Text(formatTime(model.clip.end))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(LCColor.secondary)
        }
    }
}
