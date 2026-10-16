import AppKit
import CoreImage

/// The audioware wave: the live audio wave drawn like the cover of
/// github.com/cyb3rpsych0s1s/audioware. Same drawing as skyland's media widget
/// (skyland tools/media-widget: main.swift AudiowareWave, audioware/render.js the
/// reference, audioware/model.json the look tuned on the cover, copied below). Silent or paused: a flat
/// line. Playing, like an oscilloscope on the low signal (advance): the bright edge A is
/// the bass, the second edge B the same 10 ms earlier, a ribbon that twists, shaped by
/// the cover's amplitude window; crest fans on the two highest peaks, a dotted jagged
/// edge hanging by |mid|, spectrum peaks where mid is strong, hairs under troughs with
/// the bass, light from slope and amplitude, onsets flash. Four depth planes, each a
/// layer blurred by Core Image: glow (ribbon light, inner and outer glows), far (tight
/// glows), mid (hatch, peaks, fans, secondary edges), near (bright edge, center line =
/// progress, light points) sharp.
final class AudiowareWave: NSView {
    var progress: CGFloat = 0 { didSet { if progress != oldValue { near.needsDisplay = true } } }
    /// Height of the center line from the bottom, 0...1 (on the cover 0.445).
    var axisFraction: CGFloat = 0.445 { didSet { recompute() } }

    typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)
    typealias Curve = [(x: CGFloat, v: CGFloat)]

    /// skyland tools/media-widget/audioware/model.json: gains tuned on the cover, its
    /// amplitude window along x.
    struct Model {
        var gain: [String: CGFloat]
        var window: Curve

        static let audioware = Model(
            gain: ["fill": 0.4422, "inner": 0.283, "ramp": 0.1001, "outer": 0.3618, "innerB": 0.1612, "innerW": 25.2, "outerW": 14.4, "fan": 1.6402, "axisW": 1.809, "axisGlowW": 4, "axisGlow": 0.3, "core": 1.245, "coreW": 1.8, "far": 0.75, "spike": 0.7537, "hatch": 0.3726, "peak": 0.1571, "hairs": 0.335, "axisHalo": 0.5025, "fanC1": 0.525, "haze": 0.22, "outerB": 0.581, "lightR": 9.0, "coreB": 1.4, "farW": 4.8],
            window: [(0, 0), (0.07, 0), (0.12, 0.15), (0.2, 0.32), (0.28, 0.47), (0.33, 0.7), (0.37, 0.95), (0.41, 1), (0.47, 0.9), (0.55, 0.83), (0.67, 0.79), (0.72, 0.65), (0.78, 0.5), (0.85, 0.42), (0.89, 0.3), (0.93, 0.1), (0.96, 0)]
        )
    }

    private final class Plane: NSView {
        var paint: (CGContext) -> Void = { _ in }
        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            paint(ctx)
        }
    }

    private let model = Model.audioware
    private let glow = Plane(), far = Plane(), mid = Plane(), near = Plane()

    // shape resolution; samples shown (80 ms) and B's delay (10 ms) at 6 kHz (render.js WAVE)
    private static let points = 256, shown = 480, shift = 60

    // audio state (render.js makeAudio / advanceAudio)
    private var activity: CGFloat = 0 // 0 paused ... 1 playing
    private var presence: CGFloat = 0 // 0 silent (flat line) ... 1 sound
    private var bands: [CGFloat] = []
    private var loud: CGFloat = 0, loudSlow: CGFloat = 0, pulse: CGFloat = 0, bass: CGFloat = 0, mids: CGFloat = 0
    private var peakLow: CGFloat = 1e-5, peakMid: CGFloat = 1e-5
    private var raw: [CGFloat]? // last window, for the trigger
    private var shapeA = [CGFloat](repeating: 0, count: AudiowareWave.points)
    private var shapeB = [CGFloat](repeating: 0, count: AudiowareWave.points)
    private var shapeM = [CGFloat](repeating: 0, count: AudiowareWave.points)
    private struct Crest { var x: CGFloat, height: CGFloat, target: CGFloat }
    private var crests: [Crest] = []
    private var spikes: [(x: CGFloat, m: CGFloat)] = []
    private var flatDrawn = false

    // per width
    private var n = 0
    private var xs: [CGFloat] = [], win: [CGFloat] = []
    // per frame
    private var heights: [String: [CGFloat]] = [:], lightOf: [String: [CGFloat]] = [:]
    private var top: [CGFloat] = [], bottom: [CGFloat] = [], thick: [CGFloat] = [], strength: [CGFloat] = []
    private var fill: [CGFloat] = [], inner: [CGFloat] = [], outer: [CGFloat] = [], boost: [CGFloat] = []
    private var amp: CGFloat { activity * presence }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        glow.paint = { [weak self] in self?.drawGlow($0) }
        far.paint = { [weak self] in self?.drawFar($0) }
        mid.paint = { [weak self] in self?.drawMid($0) }
        near.paint = { [weak self] in self?.drawNear($0) }
        for plane in [glow, far, mid, near] {
            plane.frame = bounds
            plane.autoresizingMask = [.width, .height]
            plane.wantsLayer = true
            plane.layerUsesCoreImageFilters = true
            addSubview(plane)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recompute()
    }

    // MARK: audio

    /// 30 times a second: band levels (0...1, fast rise, slow fall) and the decimated low /
    /// mid signals of AudioBands (nil when paused).
    func advance(levels input: [Float], playing: Bool, wave: (low: [Float], mid: [Float])?) {
        let target: CGFloat = playing ? 1 : 0, settling = abs(activity - target) > 0.002
        activity = settling ? activity + (target - activity) * 0.08 : target
        if bands.count != input.count { bands = [CGFloat](repeating: 0, count: input.count) }
        for i in bands.indices { // fast attack, softer release
            let v = CGFloat(input[i])
            bands[i] += (v - bands[i]) * (v > bands[i] ? 0.6 : 0.18)
        }
        let mean = { (part: ArraySlice<CGFloat>) -> CGFloat in part.isEmpty ? 0 : part.reduce(0, +) / CGFloat(part.count) }
        loud = mean(bands[...])
        loudSlow += (loud - loudSlow) * 0.05
        pulse = max(pulse * 0.86, min(1, max(0, (loud - loudSlow) * 4))) // onsets
        bass = mean(bands.prefix(3))
        mids = mean(bands.dropFirst(3).prefix(6))
        let signal = playing ? wave.flatMap { shownSignal($0.low, $0.mid) } : nil
        // silence (or no capture, or paused): back to the flat line
        let gate = signal.map { max(0, min(1, ($0.rms - 0.002) / 0.008)) } ?? 0
        presence += (gate - presence) * (gate > presence ? 0.25 : 0.08)
        let size = 0.9 * (0.65 + 0.5 * loud)
        for r in 0 ..< Self.points {
            let w = Self.linear(model.window, CGFloat(r) / CGFloat(Self.points - 1)) * amp * size
            let a = signal.map { w * Self.soft($0.a[r]) } ?? 0, b = signal.map { w * 0.9 * Self.soft($0.b[r]) } ?? 0
            let m = signal.map { abs($0.m[r]) } ?? 0
            shapeA[r] += (a - shapeA[r]) * 0.5
            shapeB[r] += (b - shapeB[r]) * 0.5
            shapeM[r] += (m - shapeM[r]) * 0.5
        }
        followCrests()
        findSpikes()
        let flat = !shapeA.contains { abs($0) > 1e-4 } && !shapeB.contains { abs($0) > 1e-4 } && pulse < 0.001
        if flat, flatDrawn { return } // the flat line is on screen already
        flatDrawn = flat
        recompute()
    }

    /// Round off the loudest swings; troughs 0.72 of crests, like the cover (+0.84 / -0.6).
    private static func soft(_ v: CGFloat) -> CGFloat {
        let k = tanh(v * 1.1) / tanh(1.1)
        return k < 0 ? k * 0.72 : k
    }

    /// The 80 ms of the low / mid signals shown this frame, normalized by slow peaks.
    private func shownSignal(_ low: [Float], _ mid: [Float]) -> (a: [CGFloat], b: [CGFloat], m: [CGFloat], rms: CGFloat)? {
        let count = Self.shown, delay = Self.shift, length = min(low.count, mid.count)
        guard length >= count + delay + 2 else { return nil }
        func at(_ values: [Float], _ start: Int, _ x: CGFloat) -> CGFloat {
            let p = CGFloat(start) + x * CGFloat(count - 1), i = min(values.count - 2, Int(p)), f = p - CGFloat(i)
            return CGFloat(values[i]) * (1 - f) + CGFloat(values[i + 1]) * f
        }
        // oscilloscope trigger: the offset most like the last frame, else the first rising zero crossing
        let maxOffset = length - count - delay
        var best = -1
        if let raw {
            var error = CGFloat.infinity
            for offset in stride(from: 0, through: maxOffset, by: 2) {
                var e: CGFloat = 0
                for k in 0 ..< 32 {
                    let d = at(low, offset + delay, CGFloat(k) / 31) / peakLow - raw[k]
                    e += d * d
                }
                if e < error { error = e; best = offset }
            }
        }
        if best < 0 {
            best = (0 ..< maxOffset).first { low[$0 + delay] <= 0 && low[$0 + delay + 1] > 0 } ?? 0
        }
        // normalized by slow peaks of the shown part, so the wave fills the window
        var highLow: Float = 1e-6, highMid: Float = 1e-6, energy: Float = 0
        for i in best ..< best + delay + count {
            highLow = max(highLow, abs(low[i]))
            highMid = max(highMid, abs(mid[i]))
        }
        peakLow = max(CGFloat(highLow), peakLow * 0.92, 1e-5)
        peakMid = max(CGFloat(highMid), peakMid * 0.92, 1e-5)
        raw = (0 ..< 32).map { at(low, best + delay, CGFloat($0) / 31) / peakLow }
        for i in best + delay ..< best + delay + count { energy += low[i] * low[i] + mid[i] * mid[i] }
        let steps = (0 ..< Self.points).map { CGFloat($0) / CGFloat(Self.points - 1) }
        return (steps.map { at(low, best + delay, $0) / peakLow }, steps.map { at(low, best, $0) / peakLow },
                steps.map { at(mid, best + delay, $0) / peakMid }, CGFloat(sqrt(energy / Float(count))))
    }

    /// Crest fans on the two highest peaks of A, followed from frame to frame.
    private func followCrests() {
        let last = Self.points - 1
        var found: [(x: CGFloat, h: CGFloat)] = []
        for r in 2 ..< last - 1 {
            let x = CGFloat(r) / CGFloat(last), h = shapeA[r]
            if x > 0.22, x < 0.84, h > 0.1, h >= shapeA[r - 1], h >= shapeA[r + 1], h >= shapeA[r - 2], h >= shapeA[r + 2] { found.append((x, h)) }
        }
        var peaks: [(x: CGFloat, h: CGFloat)] = []
        for p in found.sorted(by: { $0.h > $1.h }) where peaks.count < 2 && peaks.allSatisfy({ abs($0.x - p.x) > 0.1 }) { peaks.append(p) }
        for i in crests.indices { crests[i].target = 0 }
        for p in peaks {
            let i: Int
            if let found = crests.firstIndex(where: { abs($0.x - p.x) < 0.06 }) {
                i = found
            } else {
                crests.append(Crest(x: p.x, height: 0, target: 0))
                i = crests.count - 1
            }
            crests[i].x += (p.x - crests[i].x) * 0.35
            crests[i].target = p.h * (0.45 + 0.5 * mids)
        }
        for i in crests.indices { crests[i].height += (crests[i].target - crests[i].height) * 0.3 }
        crests = Array(crests.filter { $0.height > 0.005 || $0.target > 0 }.sorted { $0.target > $1.target }.prefix(2))
    }

    /// Spectrum peaks where the mid signal is strong.
    private func findSpikes() {
        let last = Self.points - 1
        var found: [(x: CGFloat, m: CGFloat)] = []
        for r in 3 ..< last - 2 {
            let x = CGFloat(r) / CGFloat(last), m = shapeM[r]
            if m > 0.35, Self.linear(model.window, x) > 0.25, m >= shapeM[r - 1], m > shapeM[r + 1], m >= shapeM[r - 3], m > shapeM[r + 3] { found.append((x, m)) }
        }
        spikes = Array(found.sorted { $0.m > $1.m }.prefix(10))
    }

    // MARK: geometry

    private static func linear(_ p: Curve, _ x: CGFloat) -> CGFloat {
        guard let first = p.first, let last = p.last else { return 0 }
        if x <= first.x { return first.v }
        if x >= last.x { return last.v }
        var i = 1
        while p[i].x < x { i += 1 }
        let a = p[i - 1], b = p[i]
        return a.v + (b.v - a.v) * (x - a.x) / (b.x - a.x)
    }
    /// Deterministic pseudo random 0..<1 (strokes stay put between frames).
    private static func hash(_ i: Int) -> CGFloat {
        let s = sin(Double(i) * 12.9898 + 78.233) * 43758.5453
        return CGFloat(s - floor(s))
    }
    /// Crest outline over A: a steep straight rise to the apex, a long fall (the cover's crests).
    private static func crestKernel(_ d: CGFloat) -> CGFloat { d < -0.03 || d > 0.12 ? 0 : d < 0 ? 1 + d / 0.03 : pow(1 - d / 0.12, 2) }
    private static func cgColor(_ c: RGB, _ a: CGFloat) -> CGColor {
        CGColor(srgbRed: c.r / 255, green: c.g / 255, blue: c.b / 255, alpha: max(0, min(1, a)))
    }
    /// A color of the design, in the theme's colors.
    private func rgba(_ c: RGB, _ a: CGFloat) -> CGColor { Self.cgColor(tone(c), a) }

    // MARK: theme (render.js makeTone)

    private var hueShift: CGFloat = 0, saturationScale: CGFloat = 1, inkOnPaper = false, themed = false
    private var softInk = false // the glow planes take the lighter ink on light themes
    private var background: RGB = (10, 18, 26)
    private var toned: [String: RGB] = [:]

    /// Follow the skyland theme: every color of the design turns from the cover's cyan to
    /// `accent` (hue rotated, saturation scaled, brightness kept). On a light `background`
    /// it is ink on paper: brightness inverted for the sharp lines, a lighter ink for the
    /// glows, dark tints of the cover's atmosphere turn pale. nil: the cover's colors.
    func setTheme(accent: NSColor?, background color: NSColor?) {
        let reference = Self.hsv((98, 205, 231))
        themed = accent != nil
        if let accent, let accentRGB = Self.components(accent) {
            let target = Self.hsv(accentRGB)
            hueShift = target.h - reference.h
            saturationScale = max(0, min(1.3, target.s / reference.s))
        }
        background = color.flatMap { Self.components($0) } ?? (10, 18, 26)
        inkOnPaper = themed && (0.2126 * background.r + 0.7152 * background.g + 0.0722 * background.b) / 255 > 0.5
        toned = [:]
        for plane in [glow, far, mid, near] { plane.needsDisplay = true }
    }

    private func tone(_ c: RGB) -> RGB {
        guard themed else { return c }
        let key = "\(c.r),\(c.g),\(c.b),\(softInk)"
        if let cached = toned[key] { return cached }
        var (h, s, v) = Self.hsv(c)
        h = (h + hueShift).truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        s = min(1, s * saturationScale)
        if inkOnPaper {
            s *= pow(min(1, v / 0.6), 2)
            if softInk {
                s *= 0.75
                v = max(0.45, min(0.92, 1.02 - 0.5 * v))
            } else {
                v = max(0.22, min(0.8, 1.08 - v))
            }
        }
        let result = Self.fromHSV(h: h, s: s, v: v)
        toned[key] = result
        return result
    }

    private static func components(_ color: NSColor) -> RGB? {
        guard let c = color.usingColorSpace(.sRGB) else { return nil }
        return (c.redComponent * 255, c.greenComponent * 255, c.blueComponent * 255)
    }
    private static func hsv(_ c: RGB) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
        let r = c.r / 255, g = c.g / 255, b = c.b / 255, high = max(r, g, b), d = high - min(r, g, b)
        var h: CGFloat = 0
        if d > 0 {
            if high == r {
                h = 60 * ((g - b) / d).truncatingRemainder(dividingBy: 6)
            } else if high == g {
                h = 60 * ((b - r) / d + 2)
            } else {
                h = 60 * ((r - g) / d + 4)
            }
        }
        if h < 0 { h += 360 }
        return (h, high > 0 ? d / high : 0, high)
    }
    private static func fromHSV(h: CGFloat, s: CGFloat, v: CGFloat) -> RGB {
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let parts: (CGFloat, CGFloat, CGFloat)
        switch Int(h / 60) % 6 {
        case 0: parts = (c, x, 0)
        case 1: parts = (x, c, 0)
        case 2: parts = (0, c, x)
        case 3: parts = (0, x, c)
        case 4: parts = (x, 0, c)
        default: parts = (c, 0, x)
        }
        return (((parts.0 + m) * 255).rounded(), ((parts.1 + m) * 255).rounded(), ((parts.2 + m) * 255).rounded())
    }
    private func gain(_ key: String) -> CGFloat { model.gain[key] ?? 0 }

    private func recompute() {
        let count = max(60, Int((bounds.width / 1.5).rounded()))
        if count != n {
            n = count
            xs = (0 ... n).map { CGFloat($0) / CGFloat(n) }
            win = xs.map { Self.linear(model.window, $0) }
            // blur radii follow the width, like the prototype (glow 6, far 1.2, mid 0.35 per 1000)
            for (plane, radius) in [(glow, 6.0), (far, 1.2), (mid, 0.35)] {
                plane.layer?.filters = [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: radius * Double(bounds.width) / 1000])!]
            }
        }
        let sample = { (shape: [CGFloat]) -> [CGFloat] in
            self.xs.map { x -> CGFloat in
                let p = x * CGFloat(shape.count - 1), k = min(shape.count - 2, Int(p)), f = p - CGFloat(k)
                return shape[k] * (1 - f) + shape[k + 1] * f
            }
        }
        let a = sample(shapeA), b = sample(shapeB), m = sample(shapeM)
        top = (0 ... n).map { max(a[$0], b[$0]) }
        bottom = (0 ... n).map { min(a[$0], b[$0]) }
        thick = (0 ... n).map { min(1, (top[$0] - bottom[$0]) / 0.25) }
        heights = ["A": a, "B": b, "D": (0 ... n).map { bottom[$0] - win[$0] * amp * (0.05 + 0.28 * m[$0]) }] // dotted jagged edge
        for (k, crest) in crests.enumerated() {
            heights["C\(k + 1)"] = (0 ... n).map { i -> CGFloat in
                let d = xs[i] - crest.x - 0.03
                return d >= -0.03 && d <= 0.12 ? a[i] + crest.height * Self.crestKernel(d) : .nan
            }
        }
        // light: slope and amplitude of the line (the cover's flanks and crests glow)
        let on = min(1, amp * 4)
        let lightA = (0 ... n).map { i -> CGFloat in
            let j = min(n, i + 1), k = max(0, i - 1), slope = abs((a[j] - a[k]) / (CGFloat(j - k) / CGFloat(n)))
            return min(1, 0.3 + 0.9 * abs(a[i]) + 0.05 * slope) * on
        }
        lightOf = ["A": lightA, "B": lightA.map { $0 * 0.8 }, "D": win.map { $0 > 0.05 ? 0.55 * on : 0 }]
        for name in ["C1", "C2"] { if let h = heights[name] { lightOf[name] = h.map { $0.isNaN ? 0 : 0.55 * on } } }
        fill = lightA.map { 0.12 + 0.45 * $0 }
        inner = lightA.map { 0.25 + 0.8 * $0 }
        outer = lightA.map { 0.15 + 0.7 * $0 }
        boost = [CGFloat](repeating: 1 + amp * 0.45 * pulse, count: n + 1) // onsets flash
        strength = m
        for plane in [glow, far, mid, near] { plane.needsDisplay = true }
    }

    // MARK: drawing helpers

    private var unitScale: CGFloat { bounds.width / 1000 }
    private var axisY: CGFloat { bounds.height * axisFraction }
    private func px(_ i: Int) -> CGFloat { CGFloat(i) / CGFloat(n) * bounds.width }
    /// Soft knee above 0.85 so loud crests round off instead of flattening.
    private func py(_ h: CGFloat) -> CGFloat {
        let m = abs(h), clipped = m <= 0.85 ? h : (h < 0 ? -1 : 1) * (0.85 + 0.2 * tanh((m - 0.85) / 0.2))
        return axisY + clipped * bounds.height * 0.525
    }
    private func point(_ i: Int, _ h: CGFloat) -> CGPoint { CGPoint(x: px(i), y: py(h)) }
    /// Width given at 1000 px wide, at least half a point.
    private func lw(_ w: CGFloat) -> CGFloat { max(0.5, w * unitScale) }
    private var column: CGFloat { bounds.width / CGFloat(n) + 0.5 * unitScale }
    private var lineNames: [String] { ["A", "B", "C1", "C2", "D"].filter { heights[$0] != nil } }

    /// A line in chunks of `step` samples whose alpha follows its light (or `profile`), batched by alpha.
    private func lit(_ ctx: CGContext, _ name: String, _ color: RGB, _ alpha: CGFloat, _ width: CGFloat, step: Int = 4, dash: [CGFloat]? = nil, profile: [CGFloat]? = nil) {
        guard let h = heights[name], let light = profile ?? lightOf[name] else { return }
        var buckets: [Int: CGMutablePath] = [:]
        for i in stride(from: 0, to: n, by: step) {
            let j = min(n, i + step)
            guard !h[i].isNaN, !h[j].isNaN else { continue }
            let bucket = Int((min(1, alpha * (light[i] + light[j]) / 2 * (boost[i] + boost[j]) / 2) * 20).rounded())
            guard bucket > 0 else { continue }
            let path = buckets[bucket] ?? CGMutablePath()
            buckets[bucket] = path
            path.move(to: point(i, h[i]))
            for k in i + 1 ... j { path.addLine(to: point(k, h[k])) }
        }
        ctx.saveGState()
        ctx.setLineWidth(lw(width))
        ctx.setLineCap(.round)
        if let dash { ctx.setLineDash(phase: 0, lengths: dash.map { lw($0) }) }
        for (bucket, path) in buckets {
            ctx.addPath(path)
            ctx.setStrokeColor(rgba(color, CGFloat(bucket) / 20))
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private typealias Hair = (from: CGPoint, to: CGPoint, color: Int, alpha: CGFloat)
    /// Hair colors; 6... the center line from cyan (free) to royal blue (under the ribbon) in 6 steps.
    private static let hairColors: [RGB] = [(55, 125, 215), (120, 210, 255), (110, 200, 250), (90, 170, 240), (60, 140, 225), (40, 110, 195)]
        + (0 ... 6).map { step -> RGB in
            let t = CGFloat(step) / 6
            return ((110 + (40 - 110) * t).rounded(), (240 + (90 - 240) * t).rounded(), (255 + (200 - 255) * t).rounded())
        }
        + [(110, 235, 255)]
    private static let axisColor = 6, axisGlowColor = 13
    /// Straight segments batched by color and alpha (rounded to 0.05), `width` in points.
    private func hairs(_ ctx: CGContext, _ list: [Hair], width: CGFloat) {
        var buckets: [Int: [CGPoint]] = [:]
        for hair in list {
            let bucket = Int((min(1, hair.alpha) * 20).rounded())
            guard bucket > 0 else { continue }
            buckets[hair.color * 100 + bucket, default: []] += [hair.from, hair.to]
        }
        ctx.saveGState()
        ctx.setLineWidth(width)
        ctx.setLineCap(.butt)
        for (key, points) in buckets {
            ctx.setStrokeColor(rgba(Self.hairColors[key / 100], CGFloat(key % 100) / 20))
            ctx.strokeLineSegments(between: points)
        }
        ctx.restoreGState()
    }

    /// Elliptic glow `rx` wide, `ry` tall.
    private func halo(_ ctx: CGContext, _ center: CGPoint, _ rx: CGFloat, _ ry: CGFloat, _ color: RGB, _ alpha: CGFloat) {
        guard rx > 0, ry > 0, alpha > 0 else { return }
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgba(color, alpha), rgba(color, 0)] as CFArray, locations: [0, 1])!
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: rx / ry, y: 1)
        ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: ry, options: [])
        ctx.restoreGState()
    }

    private func ribbonPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: point(0, top[0]))
        for i in 1 ... n { path.addLine(to: point(i, top[i])) }
        for i in (0 ... n).reversed() { path.addLine(to: point(i, bottom[i])) }
        path.closeSubpath()
        return path
    }

    private var ready: Bool { n > 0 && top.count == n + 1 && boost.count == n + 1 }

    // MARK: planes

    /// Ribbon light per column, the light the edges pour inside it, wide halos, axis glow.
    private func drawGlow(_ ctx: CGContext) {
        guard ready else { return }
        softInk = true
        defer { softInk = false }
        let w = bounds.width, h = bounds.height
        if amp > 0.01 { halo(ctx, CGPoint(x: w * 0.53, y: axisY), w * 0.40, h * 0.42, (22, 45, 80), 0.45 * amp) }
        var columns: [Hair] = []
        for i in 0 ... n where top[i] - bottom[i] >= 0.005 {
            let a = gain("fill") * fill[i] * boost[i]
            if top[i] > 0 { columns.append((point(i, top[i]), point(i, max(0, bottom[i])), 5, a)) }
            if bottom[i] < 0 { columns.append((point(i, min(0, top[i])), point(i, bottom[i]), 5, a)) }
        }
        hairs(ctx, columns, width: column)
        ctx.saveGState()
        ctx.addPath(ribbonPath())
        ctx.clip()
        for name in ["A", "B"] {
            let a = gain("inner") * (name == "A" ? 1 : gain("innerB")), profile = name == "A" ? inner : nil
            lit(ctx, name, (45, 185, 235), a, gain("innerW"), step: 6, profile: profile)
            lit(ctx, name, (90, 215, 250), a, gain("innerW") * 0.4, step: 6, profile: profile)
        }
        lit(ctx, "B", (50, 140, 230), gain("ramp"), 40, step: 6)
        ctx.restoreGState()
        for name in lineNames {
            lit(ctx, name, (35, 165, 230), gain("outer") * (name == "A" ? 1 : gain("outerB")), gain("outerW"), step: 6, profile: name == "A" ? outer : nil)
        }
        // the axis glows where it is free, like the flat ends of the cover
        hairs(ctx, (0 ... n).map { i -> Hair in
            (CGPoint(x: px(i), y: axisY - lw(4)), CGPoint(x: px(i), y: axisY + lw(4)), Self.axisGlowColor, gain("axisHalo") * 0.6 * (1 - thick[i]))
        }, width: column)
    }

    /// Tight glows around every line.
    private func drawFar(_ ctx: CGContext) {
        guard ready else { return }
        softInk = true
        defer { softInk = false }
        for name in lineNames {
            lit(ctx, name, (60, 195, 240), gain("far") * (name == "A" ? 1 : gain("outerB")), gain("farW"))
        }
    }

    /// Hatch, spectrum peaks, hanging hairs, crest fans, secondary edges.
    private func drawMid(_ ctx: CGContext) {
        guard ready, let d = heights["D"], let a = heights["A"], let lightD = lightOf["D"] else { return }
        let w = bounds.width, on = min(1, amp * 4)
        var hatch: [Hair] = []
        for i in 0 ... n where top[i] - bottom[i] >= 0.01 {
            let r = Self.hash(i + 40)
            hatch.append((point(i, top[i]), point(i, bottom[i]), r > 0.93 ? 1 : 0, gain("hatch") * fill[i] * (0.25 + 1.1 * r) * boost[i] * 2))
        }
        for i in 0 ... n where Self.hash(i + 61) < 0.5 && bottom[i] - d[i] > 0.02 { // sparse under the ribbon
            hatch.append((point(i, bottom[i]), point(i, d[i]), 0, 0.1 * lightD[i] * boost[i]))
        }
        hairs(ctx, hatch, width: lw(0.55))
        // spectrum peaks: narrow glowing peaks with concave flanks, the tallest go on as a
        // hairline with a light tip
        var lines: [Hair] = []
        for spike in spikes {
            let i = Int((spike.x * CGFloat(n)).rounded()), base = top[i]
            let tip = base + (0.06 + 0.45 * spike.m) * amp * win[i] * (0.6 + 0.8 * mids)
            guard tip - base >= 0.03 else { continue }
            let height = min(0.22, tip - base), half = (0.003 + 0.02 * height) * w, apex = point(i, base + height), peak = gain("peak") * boost[i]
            let path = CGMutablePath()
            path.move(to: CGPoint(x: apex.x - half, y: py(base)))
            path.addQuadCurve(to: apex, control: CGPoint(x: apex.x - half * 0.15, y: py(base + height * 0.25)))
            path.addQuadCurve(to: CGPoint(x: apex.x + half, y: py(base)), control: CGPoint(x: apex.x + half * 0.15, y: py(base + height * 0.25)))
            path.closeSubpath()
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgba((70, 170, 245), peak), rgba((70, 170, 245), peak * 0.3)] as CFArray, locations: [0, 1])!
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: py(base)), end: apex, options: [])
            ctx.restoreGState()
            ctx.addPath(path)
            ctx.setStrokeColor(rgba((110, 210, 250), peak * 1.2))
            ctx.setLineWidth(lw(0.5))
            ctx.strokePath()
            if tip - base > height + 0.02 {
                lines.append((apex, point(i, tip), 2, gain("spike") * boost[i]))
                if tip > 0.45 { halo(ctx, point(i, tip), lw(2), lw(2), (170, 240, 255), 0.5 * boost[i]) }
            }
        }
        // hairs over strong mids, hanging under troughs with the bass
        for i in 2 ... max(2, n - 2) {
            let up = strength[i] * win[i] * amp * 0.8, down = min(1, -bottom[i] * 2.5) * amp
            if Self.hash(i + 7) < up {
                let length = pow(Self.hash(i + 11), 2) * 0.3 * (0.5 + strength[i])
                lines.append((point(i, top[i]), point(i, top[i] + length), 4, gain("hairs") * (0.4 + 0.6 * Self.hash(i + 3)) * boost[i]))
            }
            if bottom[i] < -0.1, Self.hash(i + 17) < down * 0.7 {
                let length = (0.04 + pow(Self.hash(i + 19), 1.5) * 0.22) * (0.5 + bass), alpha = gain("hairs") * (0.4 + 0.6 * Self.hash(i + 23)) * boost[i]
                let middle = bottom[i] - length / 2
                lines.append((point(i, bottom[i]), point(i, middle), 4, alpha))
                lines.append((point(i, middle), point(i, bottom[i] - length), 4, alpha * 0.4))
            }
            let trough = bottom[i] <= bottom[i - 1] && bottom[i] < bottom[i + 1] && bottom[i] <= bottom[i - 2] && bottom[i] < bottom[i + 2]
            if bottom[i] < -0.18, trough { // the long hairs at the bottom of troughs
                let tip = bottom[i] - (0.12 + 0.25 * bass) * amp, middle = (bottom[i] + tip) / 2
                lines.append((point(i, bottom[i]), point(i, middle), 3, gain("spike") * boost[i]))
                lines.append((point(i, middle), point(i, tip), 3, gain("spike") * 0.45 * boost[i]))
            }
        }
        hairs(ctx, lines, width: lw(0.6))
        // crest fans: nested contours from A up to the crest (moire)
        for (name, alpha) in [("C1", gain("fanC1")), ("C2", gain("fan"))] {
            guard let crest = heights[name] else { continue }
            let range = (0 ... n).filter { !crest[$0].isNaN }
            guard let start = range.first else { continue }
            ctx.setLineWidth(lw(0.5))
            for f in 1 ... 22 {
                let q = CGFloat(f) / 22, path = CGMutablePath()
                path.move(to: point(start, a[start] + (crest[start] - a[start]) * q))
                for i in range.dropFirst() { path.addLine(to: point(i, a[i] + (crest[i] - a[i]) * q)) }
                ctx.addPath(path)
                ctx.setStrokeColor(rgba((75, 155, 230), alpha * (0.35 + 0.65 * q) * on))
                ctx.strokePath()
            }
        }
        lit(ctx, "B", (98, 205, 231), gain("core"), gain("coreB"), step: 3)
        lit(ctx, "C1", (120, 215, 245), 0.9, 0.8, step: 3)
        lit(ctx, "C2", (120, 215, 245), 0.9, 0.8, step: 3)
        lit(ctx, "D", (120, 215, 245), 1.0, 1.1, step: 3, dash: [1.4, 2.2])
    }

    /// Bright edge, center line (cyan where free, the flat line; royal blue under the
    /// ribbon; dimmer after the playhead), light points.
    private func drawNear(_ ctx: CGContext) {
        guard ready, let a = heights["A"], let b = heights["B"] else { return }
        let w = bounds.width, on = min(1, amp * 4)
        lit(ctx, "A", (98, 205, 231), gain("core"), gain("coreW"), step: 3)
        lit(ctx, "A", (190, 248, 255), 0.8 * gain("core"), 0.6, step: 3)
        let thickness = lw(gain("axisW")), flash = amp * pulse
        hairs(ctx, (0 ... n).map { i -> Hair in
            let step = Int((thick[i] * 6).rounded()), t = CGFloat(step) / 6
            return (CGPoint(x: px(i), y: axisY - thickness / 2), CGPoint(x: px(i), y: axisY + thickness / 2), Self.axisColor + step, (0.95 - 0.55 * t) * (1 + 0.8 * flash))
        }, width: column)
        let flare = 1 + 0.6 * flash
        halo(ctx, CGPoint(x: w * 0.06, y: axisY), w * 0.09 * flare, lw(gain("axisGlowW")), (110, 240, 255), gain("axisGlow") * flare)
        halo(ctx, CGPoint(x: w * 0.945, y: axisY), w * 0.03 * flare, lw(5), (120, 250, 255), 0.7)
        if amp > 0.01 { halo(ctx, CGPoint(x: w * 0.76, y: axisY), w * 0.07 * flare, lw(5), (45, 110, 230), 0.45 * amp * flare) }
        let head = w * max(0, min(1, progress))
        ctx.setFillColor(Self.cgColor(background, 0.45)) // what is left of the track
        ctx.fill(CGRect(x: head, y: axisY - thickness / 2, width: w - head, height: thickness))
        if progress > 0, progress < 1 { halo(ctx, CGPoint(x: head, y: axisY), lw(10), lw(3), (180, 245, 255), 0.9) }
        // light points where the edges cross and on crest tops
        for i in 1 ..< n where (a[i] - b[i]) * (a[i + 1] - b[i + 1]) < 0 && abs(a[i]) > 0.04 {
            halo(ctx, point(i, a[i]), lw(gain("lightR")), lw(gain("lightR")), (160, 235, 255), 0.45 * boost[i] * on)
        }
        for name in ["C1", "C2"] {
            guard let crest = heights[name], let apex = (0 ... n).filter({ !crest[$0].isNaN }).max(by: { crest[$0] < crest[$1] }) else { continue }
            halo(ctx, point(apex, crest[apex]), lw(gain("lightR") * 0.6), lw(gain("lightR") * 0.6), (160, 235, 255), 0.35 * on)
        }
    }
}
