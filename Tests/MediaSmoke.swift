import Foundation
import AVFoundation
import ImageIO
@main struct MediaSmoke {
    static func main() async throws {
        let pipeline = MediaPipeline()
        let source = try await pipeline.inspect(URL(fileURLWithPath: "/private/tmp/livecut-fixtures/source.mov"))
        for length in [1.0,3.0,5.0] {
            for cover in [0.0,length/2,length-1/30] {
                let pair = try await pipeline.generate(source: source, clip: Clip(start: 0,end: length,cover: cover))
                defer { pair.clean() }
                let asset = AVURLAsset(url: pair.video)
                let duration = try await asset.load(.duration).seconds
                let tracks = try await asset.loadTracks(withMediaType: .video)
                let size = try await tracks[0].load(.naturalSize)
                let audio = try await asset.loadTracks(withMediaType: .audio)
                let metaTracks = try await asset.loadTracks(withMediaType: .metadata)
                let metadata = try await asset.load(.metadata)
                let id = metadata.first { $0.identifier?.rawValue == "mdta/com.apple.quicktime.content.identifier" }
                let videoID = try await id?.load(.stringValue)
                let image = CGImageSourceCreateWithURL(pair.photo as CFURL, nil)!
                let props = CGImageSourceCopyPropertiesAtIndex(image, 0, nil)! as NSDictionary
                let maker = props[kCGImagePropertyMakerAppleDictionary] as? NSDictionary
                precondition(maker?["17"] as? String == videoID && videoID != nil)
                precondition(abs(duration-length) <= 1/30 + 0.001)
                precondition(size == CGSize(width:640,height:360))
                precondition(!audio.isEmpty && !metaTracks.isEmpty)
                print("PASS duration=\(length) cover=\(cover) size=\(size) audio=\(audio.count) metadata=\(metaTracks.count) identifiers=matched")
            }
        }
        print("9 media combinations passed; Photos/iPhone acceptance NOT tested")
    }
}
