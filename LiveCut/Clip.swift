import Foundation

struct Clip: Equatable {
    var start: Double
    var end: Double
    var cover: Double
    var duration: Double { end - start }
    static func initial(_ duration: Double) -> Clip {
        Clip(start: 0, end: min(3, duration), cover: 0)
    }
    func next(total: Double) -> Clip {
        let s = total - end >= 1 ? end : max(0, total - 3)
        return Clip(start: s, end: min(s + 3, total), cover: s)
    }
    func replacingStart(_ value: Double, total: Double) -> Clip {
        let boundedEnd = min(total, end)
        let minimum = max(0, boundedEnd - 5)
        let maximum = max(minimum, boundedEnd - 1)
        let newStart = min(max(minimum, value), maximum)
        let newCover = cover < newStart || cover >= end ? newStart : cover
        return Clip(start: newStart, end: end, cover: newCover)
    }
    func replacingEnd(_ value: Double, total: Double) -> Clip {
        let minimum = min(total, start + 1)
        let maximum = min(total, start + 5)
        let newEnd = min(max(minimum, value), maximum)
        let newCover = cover >= newEnd ? start : cover
        return Clip(start: start, end: newEnd, cover: newCover)
    }
    func moved(toStart value: Double, total: Double) -> Clip {
        let length = duration
        let newStart = min(max(0, value), max(0, total - length))
        let coverOffset = max(0, cover - start)
        return Clip(
            start: newStart,
            end: newStart + length,
            cover: min((newStart + length).nextDown, newStart + coverOffset)
        )
    }
    func keptVisible(from visibleStart: Double, to visibleEnd: Double, total: Double) -> Clip {
        let lowerBound = min(max(0, visibleStart), total)
        let upperBound = max(lowerBound, min(total, visibleEnd) - duration)
        return moved(toStart: min(max(start, lowerBound), upperBound), total: total)
    }
    func validate(total: Double) -> Bool {
        [start, end, cover, total].allSatisfy(\.isFinite) && total >= 1 && total <= 600 && start >= 0 && end <= total && duration >= 1 && duration <= 5 && cover >= start && cover < end
    }
}

enum MediaFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
