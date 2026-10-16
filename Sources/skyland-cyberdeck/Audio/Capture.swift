import Accelerate
import AppKit
import ScreenCaptureKit

/// RBJ biquad filter, one sample at a time.
struct Biquad {
    private let b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    private var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0

    init(lowpass frequency: Double, q: Double, rate: Double) {
        let w = 2 * Double.pi * frequency / rate, c = cos(w)
        self.init(b: ((1 - c) / 2, 1 - c, (1 - c) / 2), alpha: sin(w) / (2 * q), cosine: c)
    }

    /// Constant 0 dB peak gain.
    init(bandpass frequency: Double, q: Double, rate: Double) {
        let w = 2 * Double.pi * frequency / rate, alpha = sin(w) / (2 * q)
        self.init(b: (alpha, 0, -alpha), alpha: alpha, cosine: cos(w))
    }

    private init(b: (Double, Double, Double), alpha: Double, cosine: Double) {
        let a0 = 1 + alpha
        b0 = Float(b.0 / a0); b1 = Float(b.1 / a0); b2 = Float(b.2 / a0)
        a1 = Float(-2 * cosine / a0); a2 = Float((1 - alpha) / a0)
    }

    mutating func callAsFunction(_ x: Float) -> Float {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x; y2 = y1; y1 = y
        return y
    }
}

/// System audio -> band levels (and, with onWave, the signals of the audioware wave),
/// from ScreenCaptureKit (audio only, the Screen Recording permission of the launching
/// app), FFT with Accelerate, log-spaced bands with auto gain. Runs only between start()
/// and stop(). Same as skyland's media widget.
final class AudioBands: NSObject, SCStreamOutput, @unchecked Sendable {
    static let fftSize = 1024
    let bandCount: Int
    let onLevels: ([Float]) -> Void // called on the main queue
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "skyland-cyberdeck.audio")
    private var samples: [Float] = []
    private let dft = vDSP.DFT(count: fftSize, direction: .forward, transformType: .complexReal, ofType: Float.self)!
    private let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: fftSize, isHalfWindow: false)
    private var peak: Float = 1e-3 // auto gain, like cava autosens
    private let tilt: Float = 1.5 // music has less energy up high: band gain (1 + band)^tilt, raise for livelier highs
    private var sampleRate: Double = 48000
    /// The audio low-passed (~180 Hz) and band-passed (~1 kHz), decimated by 8 (6 kHz),
    /// the last 768 points of each (oldest first), about 30 times a second, on the main
    /// queue. Set before start().
    var onWave: (([Float], [Float]) -> Void)?
    /// Capture refused (no Screen Recording permission) or no display, on the main queue.
    var onUnavailable: (() -> Void)?
    private var lowFilter = Biquad(lowpass: 180, q: 0.707, rate: 48000), midFilter = Biquad(bandpass: 1000, q: 0.8, rate: 48000)
    private var lowRing = [Float](repeating: 0, count: 768), midRing = [Float](repeating: 0, count: 768), ringIndex = 0
    private var lowSum: Float = 0, midSum: Float = 0, decimation = 0, sinceWave = 0

    init(bands: Int, onLevels: @escaping ([Float]) -> Void) {
        bandCount = bands
        self.onLevels = onLevels
    }

    func start() {
        guard stream == nil else { return }
        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
                  let display = content.displays.first else { return unavailable() }
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = Int(sampleRate)
            config.channelCount = 1
            config.width = 2 // audio only: the smallest video, one frame per second
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: config, delegate: nil)
            try? stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            guard (try? await stream.startCapture()) != nil else { return unavailable() }
            self.stream = stream
        }
    }

    private func unavailable() {
        DispatchQueue.main.async { self.onUnavailable?() }
    }

    func stop() {
        let stream = self.stream
        self.stream = nil
        Task { try? await stream?.stopCapture() }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        try? buffer.withAudioBufferList { list, _ in
            guard let data = list.first?.mData else { return }
            let count = Int(list.first!.mDataByteSize) / MemoryLayout<Float>.size
            let chunk = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count)
            samples.append(contentsOf: chunk)
            if onWave != nil { follow(chunk) }
        }
        while samples.count >= Self.fftSize {
            let block = Array(samples.prefix(Self.fftSize))
            samples.removeFirst(Self.fftSize / 2) // 50% overlap
            let levels = bands(of: block)
            DispatchQueue.main.async { self.onLevels(levels) }
        }
    }

    /// Filters and decimates the new samples into the rings, hands them out ~30 times a second.
    private func follow(_ chunk: UnsafeBufferPointer<Float>) {
        for x in chunk {
            lowSum += lowFilter(x)
            midSum += midFilter(x)
            decimation += 1
            guard decimation == 8 else { continue }
            lowRing[ringIndex] = lowSum / 8
            midRing[ringIndex] = midSum / 8
            ringIndex = (ringIndex + 1) % lowRing.count
            lowSum = 0; midSum = 0; decimation = 0
        }
        sinceWave += chunk.count
        guard sinceWave >= 1600, let onWave else { return } // 30 times a second at 48 kHz
        sinceWave = 0
        let low = Array(lowRing[ringIndex...] + lowRing[..<ringIndex]), mid = Array(midRing[ringIndex...] + midRing[..<ringIndex])
        DispatchQueue.main.async { onWave(low, mid) }
    }

    private func bands(of block: [Float]) -> [Float] {
        let windowed = vDSP.multiply(block, window)
        // complexReal DFT input: even samples as real, odd samples as imaginary
        let even = stride(from: 0, to: Self.fftSize, by: 2).map { windowed[$0] }
        let odd = stride(from: 1, to: Self.fftSize, by: 2).map { windowed[$0] }
        var re = [Float](repeating: 0, count: Self.fftSize / 2), im = re
        dft.transform(inputReal: even, inputImaginary: odd, outputReal: &re, outputImaginary: &im)
        let binHz = sampleRate / Double(Self.fftSize)
        var levels = [Float](repeating: 0, count: bandCount)
        for band in 0 ..< bandCount { // log spaced 50 Hz ... 12 kHz
            let low = 50 * pow(240, Double(band) / Double(bandCount)), high = 50 * pow(240, Double(band + 1) / Double(bandCount))
            let first = max(1, Int(low / binHz)), last = max(first, min(re.count - 1, Int(high / binHz)))
            var sum: Float = 0
            for k in first ... last { sum += sqrt(re[k] * re[k] + im[k] * im[k]) }
            levels[band] = sum / Float(last - first + 1) * pow(Float(1 + band), tilt)
        }
        peak = max(levels.max() ?? 0, peak * 0.995, 1e-3)
        return levels.map { min(1, sqrt($0 / peak)) }
    }
}
