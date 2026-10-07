import Foundation
@main struct ClipTests {
    static func main() {
        precondition(Clip.initial(2.2) == Clip(start: 0, end: 2.2, cover: 0))
        precondition(Clip(start: 10, end: 13, cover: 11).next(total: 30) == Clip(start: 13, end: 16, cover: 13))
        precondition(Clip(start: 7, end: 9.5, cover: 8).next(total: 10) == Clip(start: 7, end: 10, cover: 7))
        precondition(Clip(start: 0, end: 1, cover: 0).validate(total: 600))
        precondition(!Clip(start: 0, end: 1, cover: 0).validate(total: 600.0001))
        precondition(!Clip(start: 0, end: 0.99, cover: 0).validate(total: 30))
        precondition(!Clip(start: 0, end: 5.01, cover: 0).validate(total: 30))
        precondition(!Clip(start: 0, end: 3, cover: 3).validate(total: 30))
        precondition(!Clip(start: .nan, end: 3, cover: 0).validate(total: 30))
        let original = Clip(start: 2, end: 5, cover: 3)
        precondition(original.replacingStart(3, total: 30) == Clip(start: 3, end: 5, cover: 3))
        precondition(original.replacingEnd(4.5, total: 30) == Clip(start: 2, end: 4.5, cover: 3))
        precondition(original.moved(toStart: 6, total: 30) == Clip(start: 6, end: 9, cover: 7))
        precondition(original.moved(toStart: 29, total: 30) == Clip(start: 27, end: 30, cover: 28))
        let secondClip = Clip(start: 0, end: 3, cover: 0).next(total: 12)
        precondition(secondClip.moved(toStart: 5, total: 12) == Clip(start: 5, end: 8, cover: 5))
        let visibleClip = Clip(start: 3, end: 6, cover: 4)
        precondition(visibleClip.keptVisible(from: 0, to: 30, total: 60) == visibleClip)
        precondition(visibleClip.keptVisible(from: 15, to: 45, total: 60) == Clip(start: 15, end: 18, cover: 16))
        let laterClip = Clip(start: 20, end: 23, cover: 21)
        precondition(laterClip.keptVisible(from: 0, to: 15, total: 60) == Clip(start: 12, end: 15, cover: 13))
        print("17 clip boundary, independent-handle, next-window, and viewport checks passed")
    }
}
