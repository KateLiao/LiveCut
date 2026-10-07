import SwiftUI

enum LCColor {
    static let canvas = Color(red: 0.025, green: 0.035, blue: 0.052)
    static let surface = Color(red: 0.075, green: 0.092, blue: 0.12)
    static let elevated = Color(red: 0.105, green: 0.125, blue: 0.16)
    static let line = Color.white.opacity(0.12)
    static let secondary = Color(red: 0.62, green: 0.66, blue: 0.72)
    static let blue = Color(red: 0.05, green: 0.49, blue: 1.0)
    static let cyan = Color(red: 0.16, green: 0.73, blue: 1.0)
    static let green = Color(red: 0.19, green: 0.82, blue: 0.42)
    static let danger = Color(red: 1.0, green: 0.28, blue: 0.31)

    static let accentGradient = LinearGradient(
        colors: [blue, Color(red: 0.02, green: 0.59, blue: 1.0)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            LCColor.canvas
            RadialGradient(
                colors: [LCColor.blue.opacity(0.16), .clear],
                center: UnitPoint(x: 0.5, y: 0.22),
                startRadius: 12,
                endRadius: 310
            )
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct PrimaryActionButton: View {
    let title: String
    var icon: String?
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.headline) }
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(.white)
            .background(enabled ? AnyShapeStyle(LCColor.accentGradient) : AnyShapeStyle(Color.white.opacity(0.13)))
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: enabled ? LCColor.blue.opacity(0.23) : .clear, radius: 18, y: 8)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(.isButton)
    }
}

struct SecondaryActionButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let icon { Image(systemName: icon).font(.headline) }
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(LCColor.elevated)
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08))
            }
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CircleIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct HeroConversionGraphic: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LCColor.blue.opacity(0.18))
                .frame(width: 250, height: 250)
                .blur(radius: 34)

            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.12, green: 0.23, blue: 0.38), Color(red: 0.03, green: 0.08, blue: 0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 205, height: 275)
                .overlay {
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.19, green: 0.62, blue: 0.93), Color(red: 0.11, green: 0.19, blue: 0.34)], startPoint: .top, endPoint: .bottom)
                        Circle()
                            .fill(Color(red: 1.0, green: 0.74, blue: 0.35))
                            .frame(width: 42, height: 42)
                            .offset(x: 49, y: -68)
                        WaveShape()
                            .fill(Color(red: 0.10, green: 0.34, blue: 0.48).opacity(0.92))
                            .frame(height: 118)
                            .offset(y: 78)
                        Image(systemName: "play.fill")
                            .font(.system(size: 25, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 62, height: 62)
                            .background(.black.opacity(0.34), in: Circle())
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .padding(6)
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 5) {
                        Image(systemName: "video.fill")
                        Text("视频")
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(14)
                }
                .rotationEffect(.degrees(-6))
                .offset(x: -36, y: animate ? -5 : 3)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .frame(width: 155, height: 205)
                .overlay {
                    VStack(spacing: 15) {
                        Image(systemName: "livephoto")
                            .font(.system(size: 64, weight: .thin))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, LCColor.blue)
                        Text("LIVE")
                            .font(.caption.weight(.bold))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16))
                }
                .rotationEffect(.degrees(7))
                .offset(x: 72, y: animate ? 6 : -3)
                .shadow(color: LCColor.blue.opacity(0.28), radius: 22, y: 12)

            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(LCColor.accentGradient, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22)))
                .offset(x: 28, y: 8)
        }
        .frame(height: 315)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { animate = true }
        }
        .accessibilityHidden(true)
    }
}

struct WaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.45))
        path.addCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.22),
            control1: CGPoint(x: rect.width * 0.28, y: rect.height * 0.05),
            control2: CGPoint(x: rect.width * 0.7, y: rect.height * 0.72)
        )
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct ThumbnailStrip: View {
    let thumbnails: [FrameThumbnail]
    var cornerRadius: CGFloat = 9

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                if thumbnails.isEmpty {
                    ForEach(0..<8, id: \.self) { index in
                        LinearGradient(
                            colors: index.isMultiple(of: 2)
                                ? [Color(red: 0.10, green: 0.23, blue: 0.34), Color(red: 0.06, green: 0.11, blue: 0.17)]
                                : [Color(red: 0.09, green: 0.18, blue: 0.28), Color(red: 0.04, green: 0.08, blue: 0.13)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: max(1, (proxy.size.width - 7) / 8))
                    }
                } else {
                    ForEach(thumbnails) { thumbnail in
                        Image(uiImage: UIImage(cgImage: thumbnail.image))
                            .resizable()
                            .scaledToFill()
                            .frame(width: max(1, (proxy.size.width - CGFloat(thumbnails.count - 1)) / CGFloat(thumbnails.count)))
                            .clipped()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LCColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    var emphasized = false

    var body: some View {
        VStack(spacing: 5) {
            Text(label)
                .font(.caption)
                .foregroundStyle(LCColor.secondary)
            Text(value)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(emphasized ? LCColor.cyan : .white)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(LCColor.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(emphasized ? LCColor.blue.opacity(0.5) : LCColor.line)
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
