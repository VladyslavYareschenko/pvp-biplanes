import AVFoundation

final class AudioManager {
    static let shared = AudioManager()

    private let engine = AVAudioEngine()
    // Pool of nodes per sound so rapid-fire sounds can overlap
    private var nodes: [String: [AVAudioPlayerNode]] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]

    private let soundNames = [
        "chute_loop", "defeat", "explosion", "fall_loop",
        "hit_chute", "hit_ground", "hit_plane", "pilot_death",
        "pilot_rescue", "shoot", "victory"
    ]

    // Sounds that fire rapidly and may need to overlap
    private let pooledSounds: Set<String> = ["shoot", "explosion"]
    private let poolSize = 3

    private init() {
        if UserDefaults.standard.object(forKey: "soundsEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "soundsEnabled")
        }
        configureEngine()
    }

    private func configureEngine() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            let mixer = engine.mainMixerNode

            for name in soundNames {
                guard let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
                      let buffer = loadBuffer(url: url) else {
                    print("AudioManager: Missing sound: \(name)")
                    continue
                }
                buffers[name] = buffer

                let count = pooledSounds.contains(name) ? poolSize : 1
                var pool: [AVAudioPlayerNode] = []

                for _ in 0..<count {
                    let node = AVAudioPlayerNode()
                    engine.attach(node)
                    engine.connect(node, to: mixer, format: buffer.format)
                    pool.append(node)
                }
                nodes[name] = pool
            }

            // Pre-warm the engine — eliminates the first-start latency spike
            engine.prepare()
            try engine.start()

        } catch {
            print("AudioManager: Engine setup failed: \(error)")
        }
    }

    private func loadBuffer(url: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length))
        else { return nil }
        try? file.read(into: buffer)
        return buffer
    }

    func playSound(_ soundName: String) {
        guard areSoundsEnabled(),
              let pool = nodes[soundName],
              let buffer = buffers[soundName] else { return }

        // Pick a node that isn't currently playing, or fall back to the first
        let node = pool.first(where: { !$0.isPlaying }) ?? pool[0]

        node.stop()
        // .playerDefault schedules for the earliest possible hardware deadline
        node.scheduleBuffer(buffer, at: nil, options: .interrupts)
        node.play()
    }

    func stopAllSounds() {
        nodes.values.flatMap { $0 }.forEach { $0.stop() }
    }

    func setSoundsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "soundsEnabled")
        if !enabled { stopAllSounds() }
    }

    func areSoundsEnabled() -> Bool {
        UserDefaults.standard.bool(forKey: "soundsEnabled")
    }
}
