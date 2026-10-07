@preconcurrency import AVFoundation
import Photos
import ImageIO
import UniformTypeIdentifiers

struct Source {
    let url: URL
    let duration: Double
    let frames: [Double]
    let fps: Float
    func nearest(_ time: Double, start: Double = 0, end: Double? = nil) -> Double {
        frames.filter { $0 >= start && $0 < (end ?? duration) }.min(by: { abs($0-time) < abs($1-time) }) ?? start
    }
}
struct Pair {
    let directory: URL
    let photo: URL
    let video: URL
    func clean() { try? FileManager.default.removeItem(at: directory) }
}

actor MediaPipeline {
    func inspect(_ url: URL) async throws -> Source {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration >= 1 else { throw MediaFailure.message("视频至少需要 1 秒，请重新选择。") }
        guard duration <= 600 else { throw MediaFailure.message("初版仅支持 10 分钟以内的视频，请重新选择。") }
        guard try await asset.load(.isPlayable), try await asset.load(.isExportable),
              let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaFailure.message("此视频暂时无法读取或导出，请选择其他视频。")
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? MediaFailure.message("无法读取视频帧。") }
        var frames: [Double] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if t >= 0 && t < duration { frames.append(t) }
        }
        guard reader.status == .completed, !frames.isEmpty else { throw reader.error ?? MediaFailure.message("视频没有可用画面。") }
        return Source(url: url, duration: duration, frames: frames.sorted(), fps: try await track.load(.nominalFrameRate))
    }

    func generate(source: Source, clip: Clip) async throws -> Pair {
        guard clip.validate(total: source.duration) else { throw MediaFailure.message("请选择 1～5 秒片段，封面必须在片段内。") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("LiveCut-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pair = Pair(directory: dir, photo: dir.appendingPathComponent("cover.jpg"), video: dir.appendingPathComponent("paired.mov"))
        do {
            let asset = AVURLAsset(url: source.url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaFailure.message("源视频已失效，请重新选择。") }
            let composition = AVMutableComposition()
            let range = CMTimeRange(start: CMTime(seconds: clip.start, preferredTimescale: 60000), duration: CMTime(seconds: clip.duration, preferredTimescale: 60000))
            guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw MediaFailure.message("无法创建视频轨道。") }
            try video.insertTimeRange(range, of: track, at: .zero)
            for audio in try await asset.loadTracks(withMediaType: .audio) {
                let available = try await audio.load(.timeRange)
                let overlap = CMTimeRangeGetIntersection(range, otherRange: available)
                if overlap.duration > .zero {
                    let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    try target?.insertTimeRange(overlap, of: audio, at: overlap.start - range.start)
                }
            }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let rect = CGRect(origin: .zero, size: size).applying(transform)
            let w = abs(rect.width), h = abs(rect.height)
            let maxW: CGFloat = w > h ? 1920 : 1080
            let maxH: CGFloat = h > w ? 1920 : 1080
            let scale = min(1, min(maxW/w, maxH/h))
            let render = CGSize(width: max(2, floor(w*scale/2)*2), height: max(2, floor(h*scale/2)*2))
            let vc = AVMutableVideoComposition()
            vc.renderSize = render
            vc.frameDuration = CMTime(seconds: 1 / Double(min(30, max(1, source.fps))), preferredTimescale: 60000)
            vc.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
            vc.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
            vc.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: range.duration)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: video)
            layer.setTransform(transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY)).concatenating(CGAffineTransform(scaleX: render.width/w, y: render.height/h)), at: .zero)
            instruction.layerInstructions = [layer]
            vc.instructions = [instruction]
            let intermediate = dir.appendingPathComponent("sdr.mov")
            guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw MediaFailure.message("此格式暂不支持生成，请更换视频。") }
            exporter.outputURL = intermediate
            exporter.outputFileType = .mov
            exporter.videoComposition = vc
            // Await encoder completion before cleaning its files; cancellation is checked before saving.
            await exporter.export()
            try Task.checkCancellation()
            guard exporter.status == .completed else { throw exporter.error ?? MediaFailure.message("视频转换失败，请重试。") }
            let converted = AVURLAsset(url: intermediate)
            let imageGenerator = AVAssetImageGenerator(asset: converted)
            imageGenerator.appliesPreferredTrackTransform = true
            let frameTolerance = CMTime(seconds: 1 / Double(min(30, max(1, source.fps))), preferredTimescale: 60000)
            imageGenerator.requestedTimeToleranceBefore = frameTolerance
            imageGenerator.requestedTimeToleranceAfter = frameTolerance
            let result = try await imageGenerator.image(at: CMTime(seconds: clip.cover - clip.start, preferredTimescale: 60000))
            let identifier = UUID().uuidString
            guard let destination = CGImageDestinationCreateWithURL(pair.photo as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw MediaFailure.message("无法写入封面，请检查可用空间。") }
            CGImageDestinationAddImage(destination, result.image, [kCGImagePropertyMakerAppleDictionary: ["17": identifier]] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw MediaFailure.message("封面写入失败，请释放空间后重试。") }
            try await remux(asset: converted, output: pair.video, identifier: identifier, cover: result.actualTime, duration: range.duration)
            try FileManager.default.removeItem(at: intermediate)
            return pair
        } catch { pair.clean(); throw error }
    }

    private func remux(asset: AVAsset, output: URL, identifier: String, cover: CMTime, duration: CMTime) async throws {
        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        let id = AVMutableMetadataItem()
        id.keySpace = .quickTimeMetadata
        id.key = "com.apple.quicktime.content.identifier" as NSString
        id.value = identifier as NSString
        id.dataType = kCMMetadataBaseDataType_UTF8 as String
        writer.metadata = [id]
        var channels: [(AVAssetReaderTrackOutput, AVAssetWriterInput)] = []
        for type in [AVMediaType.video, .audio] {
            for track in try await asset.loadTracks(withMediaType: type) {
                let input = AVAssetWriterInput(mediaType: type, outputSettings: nil, sourceFormatHint: try await track.load(.formatDescriptions).first)
                let source = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
                guard writer.canAdd(input), reader.canAdd(source) else { throw MediaFailure.message("视频轨道格式暂不支持。") }
                writer.add(input); reader.add(source); channels.append((source,input))
            }
        }
        var format: CMMetadataFormatDescription?
        let specification = [kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time", kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: "com.apple.metadata.datatype.int8"]
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed, metadataSpecifications: [specification] as CFArray, formatDescriptionOut: &format)
        guard status == noErr else { throw MediaFailure.message("无法创建 Live Photo 封面元数据。") }
        let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: format)
        let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
        writer.add(metadataInput)
        guard writer.startWriting(), reader.startReading() else { throw writer.error ?? reader.error ?? MediaFailure.message("无法开始生成 Live Photo。") }
        writer.startSession(atSourceTime: .zero)
        let still = AVMutableMetadataItem()
        still.keySpace = .quickTimeMetadata
        still.key = "com.apple.quicktime.still-image-time" as NSString
        still.value = NSNumber(value: Int8(0))
        still.dataType = "com.apple.metadata.datatype.int8"
        guard adaptor.append(AVTimedMetadataGroup(items: [still], timeRange: CMTimeRange(start: cover, duration: CMTime(value: 1, timescale: 30)))) else { throw writer.error ?? MediaFailure.message("封面元数据写入失败。") }
        metadataInput.markAsFinished()
        do {
            // Interleave tracks so writer backpressure cannot block a second track.
            var active = channels
            while !active.isEmpty {
                try Task.checkCancellation()
                guard writer.status == .writing else { throw writer.error ?? MediaFailure.message("配对视频写入中断。") }
                var finished: [Int] = []
                for (index, channel) in active.enumerated() where channel.1.isReadyForMoreMediaData {
                    if let sample = channel.0.copyNextSampleBuffer() {
                        guard channel.1.append(sample) else { throw writer.error ?? MediaFailure.message("配对视频写入失败。") }
                    } else { channel.1.markAsFinished(); finished.append(index) }
                }
                for index in finished.reversed() { active.remove(at: index) }
                if !active.isEmpty { try await Task.sleep(for: .milliseconds(2)) }
            }
            guard reader.status == .completed else { throw reader.error ?? MediaFailure.message("视频读取中断。") }
            writer.endSession(atSourceTime: duration)
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? MediaFailure.message("Live Photo 生成失败。") }
        } catch { reader.cancelReading(); writer.cancelWriting(); throw error }
    }

    func save(_ pair: Pair) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw MediaFailure.message("无法保存：请在系统设置中允许 LiveCut 添加照片，然后重试。") }
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: pair.photo, options: nil)
            request.addResource(with: .pairedVideo, fileURL: pair.video, options: nil)
        }
    }
}
