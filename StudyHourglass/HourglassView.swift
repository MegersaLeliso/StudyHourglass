import SwiftUI
import AppKit

// MARK: - Palette

nonisolated enum HourglassPalette {
    static let sandShadow = Color(red: 0.62, green: 0.40, blue: 0.13)
    static let sandMid = Color(red: 0.86, green: 0.63, blue: 0.27)
    static let sandHighlight = Color(red: 0.98, green: 0.82, blue: 0.47)
    static let woodDark = Color(red: 0.30, green: 0.18, blue: 0.08)
    static let woodLight = Color(red: 0.62, green: 0.42, blue: 0.20)
    static let skin = Color(red: 0.93, green: 0.66, blue: 0.52)
}

// MARK: - Assets

/// An optional bitmap layer plus where its subject sits inside the image (normalized),
/// so it can be fitted onto the vector hourglass geometry.
nonisolated struct PlacedAsset {
    let image: Image
    let aspect: CGFloat          // height / width
    let subjectCenterX: CGFloat  // normalized x of the subject's center
    let subjectWidth: CGFloat    // normalized width of the subject
    let anchorY: CGFloat         // normalized y that gets pinned to a target point
    var verticalStretch: CGFloat = 1

    /// Rect in which to draw the image so the subject spans `width`, centered on
    /// `centerX`, with `anchorY` landing on `targetY`.
    func rect(centerX: CGFloat, width: CGFloat, targetY: CGFloat) -> CGRect {
        let w = width / subjectWidth
        let h = w * aspect * verticalStretch
        return CGRect(x: centerX - subjectCenterX * w, y: targetY - anchorY * h, width: w, height: h)
    }
}

/// Looks up `top_figure`, `bottom_figure` and `glass_overlay` in the asset catalog.
/// Any missing asset is nil and the renderer falls back to vector shapes.
nonisolated struct HourglassAssets {
    var topFigure: PlacedAsset?
    var bottomFigure: PlacedAsset?
    var glassOverlay: PlacedAsset?

    @MainActor static let shared: HourglassAssets = {
        func load(_ name: String, centerX: CGFloat, width: CGFloat, anchorY: CGFloat,
                  stretch: CGFloat = 1) -> PlacedAsset? {
            guard let ns = NSImage(named: name), ns.size.width > 0 else { return nil }
            let image = keyedOutBlack(ns).map { Image(decorative: $0, scale: 1) } ?? Image(nsImage: ns)
            return PlacedAsset(image: image, aspect: ns.size.height / ns.size.width,
                               subjectCenterX: centerX, subjectWidth: width, anchorY: anchorY,
                               verticalStretch: stretch)
        }
        // Subject positions measured from the supplied artwork (glass bowl / neck).
        return HourglassAssets(
            topFigure: load("top_figure", centerX: 0.553, width: 0.476, anchorY: 1.0),
            bottomFigure: load("bottom_figure", centerX: 0.574, width: 0.498, anchorY: 0.70),
            glassOverlay: load("glass_overlay", centerX: 0.509, width: 0.449, anchorY: 0.445,
                               stretch: 1.3)
        )
    }()

    /// The artwork is JPEG on black. With no dark card behind the hourglass any more,
    /// convert brightness to alpha so the black backdrop becomes transparent.
    ///
    /// The original colour is kept as the *premultiplied* value and alpha is lifted
    /// above it with a square-root curve. Over black this composites to exactly the
    /// original art; over a white page far less background bleeds through, so the
    /// figures and glass read as rich and solid instead of washed out.
    nonisolated static func keyedOutBlack(_ ns: NSImage) -> CGImage? {
        guard let source = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = source.width, h = source.height
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))

        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        // Per-brightness lookup tables (indexed by the pixel's max channel).
        let floor = 14.0   // swallow JPEG noise in the "black" background
        let knee = 0.08    // fade in over the darkest tones so noise doesn't leave a dark haze
        var alphaLUT = [Int](repeating: 0, count: 256)
        var colorLUT = [Int](repeating: 0, count: 256)   // colour scale × 1024
        for peak in 1...255 {
            let t = max(0, Double(peak) - floor) / (255 - floor)
            guard t > 0 else { continue }
            // sqrt boosts mid-tones toward opaque; never below t so colour ≤ alpha holds.
            let a = max(t, t.squareRoot() * min(1, t / knee))
            alphaLUT[peak] = Int((a * 255).rounded())
            colorLUT[peak] = Int((t * 255 / Double(peak) * 1024).rounded())
        }

        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let r = Int(px[i]), g = Int(px[i + 1]), b = Int(px[i + 2])
            let peak = max(r, g, b)
            let alpha = alphaLUT[peak], k = colorLUT[peak]
            px[i] = UInt8(min(alpha, r * k >> 10))
            px[i + 1] = UInt8(min(alpha, g * k >> 10))
            px[i + 2] = UInt8(min(alpha, b * k >> 10))
            px[i + 3] = UInt8(alpha)
        }
        return ctx.makeImage()
    }
}

// MARK: - View

struct HourglassView: View {
    /// Unscaled canvas width the renderer's geometry is designed for.
    static let baseWidth: CGFloat = 170
    let model: TimerModel
    private let assets = HourglassAssets.shared

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: model.phase != .running)) { timeline in
            let renderer = HourglassRenderer(
                progress: model.progress(at: timeline.date),
                time: timeline.date.timeIntervalSinceReferenceDate,
                flowing: model.phase == .running,
                assets: assets
            )
            Canvas { context, size in
                // Draw in base (unscaled) units under a vector transform: geometry, sand,
                // stroke widths and figures all scale together and stay crisp at any size.
                let scale = max(0.01, size.width / HourglassView.baseWidth)
                context.scaleBy(x: scale, y: scale)
                renderer.draw(in: &context, size: CGSize(width: size.width / scale,
                                                         height: size.height / scale))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Hourglass timer")
        .accessibilityValue(model.remainingText + " remaining")
    }
}

// MARK: - Geometry

/// Vector profile of the glass. `t` runs from 0 at the neck to 1 at a bulb's rim.
nonisolated struct HourglassGeometry {
    let rect: CGRect
    let capHeight: CGFloat
    let neckY: CGFloat
    let bulbHeight: CGFloat
    let centerX: CGFloat
    let maxHalfWidth: CGFloat
    let neckHalfWidth: CGFloat
    /// Fraction of the top bulb's depth that is filled with sand at the start.
    let initialFill: CGFloat = 0.70

    private static let samples = 240
    private let cumulative: [CGFloat]   // volume from neck (t=0) to t, per sample

    init(rect: CGRect) {
        self.rect = rect
        capHeight = rect.height * 0.045
        let glassTop = rect.minY + capHeight
        let glassBottom = rect.maxY - capHeight
        neckY = (glassTop + glassBottom) / 2
        bulbHeight = neckY - glassTop
        centerX = rect.midX
        maxHalfWidth = rect.width * 0.40
        neckHalfWidth = max(2.2, rect.width * 0.024)

        // Volume of revolution: dV ∝ r(t)² dt.
        var table = [CGFloat](repeating: 0, count: Self.samples + 1)
        let dt = 1 / CGFloat(Self.samples)
        var previous = Self.halfWidth(0, n: neckHalfWidth, m: maxHalfWidth)
        for i in 1...Self.samples {
            let r = Self.halfWidth(CGFloat(i) * dt, n: neckHalfWidth, m: maxHalfWidth)
            table[i] = table[i - 1] + (previous * previous + r * r) / 2 * dt
            previous = r
        }
        cumulative = table
    }

    private static func halfWidth(_ t: CGFloat, n: CGFloat, m: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        let p = pow(sin(.pi * 0.8 * t), 1.25)   // flared neck, round shoulder, narrower rim
        return n + (m - n) * p
    }

    func halfWidth(_ t: CGFloat) -> CGFloat { Self.halfWidth(t, n: neckHalfWidth, m: maxHalfWidth) }
    func topY(_ t: CGFloat) -> CGFloat { neckY - t * bulbHeight }
    func bottomY(_ t: CGFloat) -> CGFloat { neckY + t * bulbHeight }

    func volume(to t: CGFloat) -> CGFloat {
        let x = min(max(t, 0), 1) * CGFloat(Self.samples)
        let i = min(Int(x), Self.samples - 1)
        let f = x - CGFloat(i)
        return cumulative[i] + (cumulative[i + 1] - cumulative[i]) * f
    }

    /// Inverse of `volume(to:)`.
    func level(forVolume v: CGFloat) -> CGFloat {
        if v <= 0 { return 0 }
        if v >= cumulative[Self.samples] { return 1 }
        var lo = 0, hi = Self.samples
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cumulative[mid] < v { lo = mid } else { hi = mid }
        }
        let span = cumulative[hi] - cumulative[lo]
        let f = span > 0 ? (v - cumulative[lo]) / span : 0
        return (CGFloat(lo) + f) / CGFloat(Self.samples)
    }

    var fullVolume: CGFloat { volume(to: initialFill) }

    /// Closed outline of the whole glass (both bulbs joined at the neck).
    var glassPath: Path {
        var path = Path()
        let steps = 60
        // Left side: top rim → neck → bottom rim.
        for i in 0...steps {
            let t = 1 - CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: centerX - halfWidth(t), y: topY(t))
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: centerX - halfWidth(t), y: bottomY(t)))
        }
        // Right side: bottom rim → neck → top rim.
        for i in 0...steps {
            let t = 1 - CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: centerX + halfWidth(t), y: bottomY(t)))
        }
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: centerX + halfWidth(t), y: topY(t)))
        }
        path.closeSubpath()
        return path
    }

    /// One bulb's interior between `from` and `to` (t values), closed straight across.
    func bulbPath(top: Bool, from t0: CGFloat = 0, to t1: CGFloat = 1) -> Path {
        let y = { (t: CGFloat) -> CGFloat in top ? self.topY(t) : self.bottomY(t) }
        var path = Path()
        let steps = 40
        for i in 0...steps {
            let t = t0 + (t1 - t0) * CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: centerX - halfWidth(t), y: y(t))
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        for i in 0...steps {
            let t = t1 - (t1 - t0) * CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: centerX + halfWidth(t), y: y(t)))
        }
        path.closeSubpath()
        return path
    }

    /// Side walls from `t0` to `t1` on one side, used to build sand shapes.
    func addWall(to path: inout Path, top: Bool, left: Bool, from t0: CGFloat, to t1: CGFloat) {
        let steps = 30
        for i in 0...steps {
            let t = t0 + (t1 - t0) * CGFloat(i) / CGFloat(steps)
            let x = centerX + (left ? -1 : 1) * halfWidth(t)
            path.addLine(to: CGPoint(x: x, y: top ? topY(t) : bottomY(t)))
        }
    }
}

// MARK: - Renderer

nonisolated struct HourglassRenderer {
    let progress: Double
    let time: Double
    let flowing: Bool
    let assets: HourglassAssets

    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        // No backdrop: the hourglass floats directly on the desktop.
        let bounds = CGRect(origin: .zero, size: size)
        let g = HourglassGeometry(rect: bounds.insetBy(dx: 10, dy: 6))
        let p = CGFloat(min(max(progress, 0), 1))

        // Smoky tint inside the bulbs, behind sand and figures, so the glass reads
        // against bright backgrounds (white pages) as well as dark wallpapers.
        ctx.fill(g.glassPath, with: .color(.black.opacity(0.28)))

        let topLevel = g.level(forVolume: (1 - p) * g.fullVolume)
        let bottomLevel = g.level(forVolume: g.volume(to: 1) - p * g.fullVolume)
        let bottomSurfaceY = drawSand(&ctx, g, progress: p, topLevel: topLevel, bottomLevel: bottomLevel)

        drawFigures(&ctx, g, topLevel: topLevel)

        if flowing && p < 1 && topLevel > 0 {
            drawStream(&ctx, g, endY: bottomSurfaceY)
        }

        drawGlass(&ctx, g)
        drawFrame(&ctx, g)
    }

    // MARK: Sand

    /// Returns the y of the bottom pile's peak (where the stream lands).
    private func drawSand(_ ctx: inout GraphicsContext, _ g: HourglassGeometry,
                          progress p: CGFloat, topLevel: CGFloat, bottomLevel: CGFloat) -> CGFloat {
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: HourglassPalette.sandShadow, location: 0),
                .init(color: HourglassPalette.sandHighlight, location: 0.38),
                .init(color: HourglassPalette.sandMid, location: 0.7),
                .init(color: HourglassPalette.sandShadow, location: 1),
            ]),
            startPoint: CGPoint(x: g.centerX - g.maxHalfWidth, y: 0),
            endPoint: CGPoint(x: g.centerX + g.maxHalfWidth, y: 0))
        let ease = min(1, p * 25)   // dip / heap grow in smoothly once sand starts moving

        // Top bulb: sand from the neck up to topLevel, with a funnel dip in the middle.
        if topLevel > 0.002 {
            let depth = topLevel * g.bulbHeight
            let dip = min(g.bulbHeight * 0.06, depth * 0.55) * ease
            let surfaceY = g.topY(topLevel)
            var path = Path()
            path.move(to: CGPoint(x: g.centerX - g.halfWidth(topLevel), y: surfaceY))
            path.addQuadCurve(to: CGPoint(x: g.centerX + g.halfWidth(topLevel), y: surfaceY),
                              control: CGPoint(x: g.centerX, y: surfaceY + 2 * dip))
            g.addWall(to: &path, top: true, left: false, from: topLevel, to: 0)
            g.addWall(to: &path, top: true, left: true, from: 0, to: topLevel)
            path.closeSubpath()
            fillSand(&ctx, path, shading: shading, seed: 1)
        }

        // Bottom bulb: pile from the base up to bottomLevel, heaped in the middle.
        var peakY = g.bottomY(1)
        if bottomLevel < 0.998 {
            let depth = (1 - bottomLevel) * g.bulbHeight
            let heap = min(g.bulbHeight * 0.09, depth * 0.9) * ease
            let surfaceY = g.bottomY(bottomLevel)
            peakY = surfaceY - heap
            var path = Path()
            path.move(to: CGPoint(x: g.centerX - g.halfWidth(bottomLevel), y: surfaceY))
            path.addQuadCurve(to: CGPoint(x: g.centerX + g.halfWidth(bottomLevel), y: surfaceY),
                              control: CGPoint(x: g.centerX, y: surfaceY - 2 * heap))
            g.addWall(to: &path, top: false, left: false, from: bottomLevel, to: 1)
            g.addWall(to: &path, top: false, left: true, from: 1, to: bottomLevel)
            path.closeSubpath()
            fillSand(&ctx, path, shading: shading, seed: 2)
        }
        return peakY
    }

    private func fillSand(_ ctx: inout GraphicsContext, _ path: Path,
                          shading: GraphicsContext.Shading, seed: Int) {
        ctx.fill(path, with: shading)
        // Fine grain speckle for texture.
        var grain = ctx
        grain.clip(to: path)
        let box = path.boundingRect
        guard box.width > 1, box.height > 1 else { return }
        let count = Int(box.width * box.height / 18)
        for i in 0..<min(count, 400) {
            let x = box.minX + hash(i, seed) * box.width
            let y = box.minY + hash(i, seed + 17) * box.height
            let light = hash(i, seed + 31) > 0.5
            grain.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.9, height: 0.9)),
                       with: .color(light ? .white.opacity(0.28) : .black.opacity(0.22)))
        }
    }

    // MARK: Stream

    private func drawStream(_ ctx: inout GraphicsContext, _ g: HourglassGeometry, endY: CGFloat) {
        let startY = g.neckY - 3
        let length = endY - startY
        guard length > 1 else { return }

        let wobble = CGFloat(sin(time * 9)) * 0.15
        let stream = CGRect(x: g.centerX - 0.7 + wobble, y: startY, width: 1.4, height: length)
        ctx.fill(Path(roundedRect: stream, cornerRadius: 0.7),
                 with: .linearGradient(Gradient(colors: [HourglassPalette.sandHighlight,
                                                         HourglassPalette.sandMid.opacity(0.85)]),
                                       startPoint: CGPoint(x: 0, y: startY),
                                       endPoint: CGPoint(x: 0, y: endY)))

        // Individual falling grains, accelerating toward the bottom.
        let grains = 16
        for i in 0..<grains {
            let phase = (time * 1.6 + Double(i) / Double(grains)).truncatingRemainder(dividingBy: 1)
            let y = startY + CGFloat(phase * phase) * length
            let x = g.centerX + CGFloat(sin(Double(i) * 12.9898 + time * 6)) * 0.9
            let r: CGFloat = i % 3 == 0 ? 0.9 : 0.6
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(HourglassPalette.sandHighlight.opacity(0.9)))
        }

        // Small splash where the stream lands.
        let splash = CGRect(x: g.centerX - 3, y: endY - 1.2, width: 6, height: 2.4)
        ctx.fill(Path(ellipseIn: splash), with: .color(HourglassPalette.sandHighlight.opacity(0.5)))
    }

    // MARK: Figures

    private func drawFigures(_ ctx: inout GraphicsContext, _ g: HourglassGeometry, topLevel: CGFloat) {
        let width = g.maxHalfWidth * 2
        // How far the top sand surface has dropped since the start; the top figure rides it.
        let sink = g.topY(topLevel) - g.topY(g.initialFill)

        // Top figure is drawn normally (not lighten-blended) after the sand, so it sits in
        // front of the top sand layer instead of being washed out by it.
        var top = ctx
        top.clip(to: g.bulbPath(top: true))
        if let asset = assets.topFigure {
            top.opacity = 0.97
            top.draw(asset.image, in: asset.rect(centerX: g.centerX, width: width,
                                                 targetY: g.topY(0.12) + sink))
        } else {
            top.translateBy(x: 0, y: sink)
            drawFallbackTopFigure(&top, g)
        }

        var bottom = ctx
        bottom.clip(to: g.bulbPath(top: false))
        if let asset = assets.bottomFigure {
            bottom.blendMode = .lighten
            bottom.opacity = 0.95
            bottom.draw(asset.image, in: asset.rect(centerX: g.centerX, width: width, targetY: g.bottomY(0.97)))
        } else {
            drawFallbackBottomFigure(&bottom, g)
        }
    }

    /// Small seated figure in the top bulb.
    private func drawFallbackTopFigure(_ ctx: inout GraphicsContext, _ g: HourglassGeometry) {
        let s = g.maxHalfWidth / 60
        let base = CGPoint(x: g.centerX, y: g.topY(0.45))
        let body = CGRect(x: base.x - 9 * s, y: base.y - 9 * s, width: 18 * s, height: 13 * s)
        let head = CGRect(x: base.x - 2 * s, y: base.y - 20 * s, width: 12 * s, height: 12 * s)
        ctx.opacity = 0.85
        ctx.fill(Path(ellipseIn: body), with: .color(HourglassPalette.skin))
        ctx.fill(Path(ellipseIn: head), with: .color(HourglassPalette.skin))
    }

    /// Small reclining figure in the bottom bulb.
    private func drawFallbackBottomFigure(_ ctx: inout GraphicsContext, _ g: HourglassGeometry) {
        let s = g.maxHalfWidth / 60
        let y = g.bottomY(0.84)
        let body = CGRect(x: g.centerX - 4 * s, y: y - 4 * s, width: 26 * s, height: 9 * s)
        let head = CGRect(x: g.centerX - 18 * s, y: y - 8 * s, width: 13 * s, height: 13 * s)
        ctx.opacity = 0.85
        ctx.fill(Path(roundedRect: body, cornerRadius: 4.5 * s), with: .color(HourglassPalette.skin.opacity(0.8)))
        ctx.fill(Path(ellipseIn: head), with: .color(HourglassPalette.skin))
    }

    // MARK: Glass & frame

    private func drawGlass(_ ctx: inout GraphicsContext, _ g: HourglassGeometry) {
        let hasOverlay = assets.glassOverlay != nil
        if let asset = assets.glassOverlay {
            var overlay = ctx
            overlay.blendMode = .screen
            overlay.opacity = 0.55
            overlay.draw(asset.image, in: asset.rect(centerX: g.centerX, width: g.maxHalfWidth * 2,
                                                     targetY: g.neckY))
        }

        // Vector glass: full strength as a fallback, a faint rim when the bitmap overlay exists.
        ctx.stroke(g.glassPath, with: .linearGradient(
            Gradient(colors: [.white.opacity(hasOverlay ? 0.22 : 0.55),
                              .white.opacity(hasOverlay ? 0.08 : 0.25)]),
            startPoint: CGPoint(x: g.centerX - g.maxHalfWidth, y: 0),
            endPoint: CGPoint(x: g.centerX + g.maxHalfWidth, y: 0)),
                   lineWidth: hasOverlay ? 1 : 1.4)

        // Soft specular highlights on the left of each bulb.
        var glow = ctx
        glow.addFilter(.blur(radius: 1.2))
        for top in [true, false] {
            var path = Path()
            let steps = 24
            for i in 0...steps {
                let t = 0.28 + 0.55 * CGFloat(i) / CGFloat(steps)
                let pt = CGPoint(x: g.centerX - g.halfWidth(t) * 0.72, y: top ? g.topY(t) : g.bottomY(t))
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            glow.stroke(path, with: .color(.white.opacity(hasOverlay ? 0.18 : 0.3)),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }

    private func drawFrame(_ ctx: inout GraphicsContext, _ g: HourglassGeometry) {
        let capHalf = min(g.maxHalfWidth + 9, g.rect.width / 2)
        let wood = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [HourglassPalette.woodLight, HourglassPalette.woodDark]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: g.capHeight))

        // Posts.
        for side in [-1.0, 1.0] {
            let x = g.centerX + CGFloat(side) * (capHalf - 4)
            let post = CGRect(x: x - 1.5, y: g.rect.minY + g.capHeight / 2,
                              width: 3, height: g.rect.height - g.capHeight)
            ctx.fill(Path(roundedRect: post, cornerRadius: 1.5),
                     with: .linearGradient(Gradient(colors: [HourglassPalette.woodDark, HourglassPalette.woodLight,
                                                             HourglassPalette.woodDark]),
                                           startPoint: CGPoint(x: post.minX, y: 0),
                                           endPoint: CGPoint(x: post.maxX, y: 0)))
        }

        // Caps.
        for y in [g.rect.minY, g.rect.maxY - g.capHeight] {
            let cap = CGRect(x: g.centerX - capHalf, y: y, width: capHalf * 2, height: g.capHeight)
            var c = ctx
            c.translateBy(x: 0, y: y)
            c.fill(Path(roundedRect: cap.offsetBy(dx: 0, dy: -y), cornerRadius: g.capHeight / 2.5), with: wood)
            c.stroke(Path(roundedRect: cap.offsetBy(dx: 0, dy: -y).insetBy(dx: 0.5, dy: 0.5),
                          cornerRadius: g.capHeight / 2.5),
                     with: .color(HourglassPalette.sandHighlight.opacity(0.25)), lineWidth: 0.8)
        }
    }

    /// Deterministic pseudo-random value in [0, 1).
    private func hash(_ i: Int, _ seed: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(seed) * 78.233) * 43758.5453
        return CGFloat(v - v.rounded(.down))
    }
}
