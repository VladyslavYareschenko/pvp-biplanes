import AVFoundation
import SpriteKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Game Events
// ─────────────────────────────────────────────────────────────────────────────

enum GameEvent {
    case planeDestroyed(
        playerIndex: Int,
        worldX: Float,
        worldY: Float,
        dir: Float,
        speed: Float
    )
    case planeDamaged(playerIndex: Int)
    case pilotJumped(playerIndex: Int)
    case chuteOpened(playerIndex: Int)
    case chuteBroken(playerIndex: Int)
    case pilotLanded(playerIndex: Int)
    case pilotDied(playerIndex: Int)
    case pilotRescued(playerIndex: Int)
    case bulletFired
    case roundFinished(winnerId: Int?)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - State Machines
// ─────────────────────────────────────────────────────────────────────────────

enum PlanePhase: Equatable {
    case flying
    case onGround
    case damaged  // hp == 1, smoke
    case burning  // hp == 0, fire
    case dead
}

enum PilotPhase: Equatable {
    case inPlane
    case falling
    case parachuting
    case runningOrIdle
    case angel
}

final class PlaneStateMachine {
    private(set) var phase: PlanePhase = .flying

    @discardableResult
    func update(from p: PlaneState) -> PlanePhase {
        let next: PlanePhase
        if p.isDead {
            next = .dead
        } else if p.isOnGround {
            next = .onGround
        } else if p.hp == 0 {
            next = .burning
        } else if p.hp == 1 {
            next = .damaged
        } else {
            next = .flying
        }
        phase = next
        return next
    }
}

final class PilotStateMachine {
    private(set) var phase: PilotPhase = .inPlane

    @discardableResult
    func update(from p: PlaneState) -> PilotPhase {
        let next: PilotPhase
        if !p.hasJumped {
            next = .inPlane
        } else if p.pilotIsDead {
            next = .angel
        } else if p.pilotChuteOpen {
            next = .parachuting
        } else if Float(p.pilotY) > 0.85 {
            next = .runningOrIdle
        } else {
            next = .falling
        }
        phase = next
        return next
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Commands
// ─────────────────────────────────────────────────────────────────────────────

protocol GameCommand {
    func execute()
}

final class SpawnCloudCommand: GameCommand {
    private weak var scene: SKScene?
    private let cloudTextures: [SKTexture]
    private let preplace: Bool

    init(scene: SKScene, cloudTextures: [SKTexture], preplace: Bool) {
        self.scene = scene
        self.cloudTextures = cloudTextures
        self.preplace = preplace
    }

    func execute() {
        guard let scene else { return }

        let texture = cloudTextures.randomElement()!
        let node = SKSpriteNode(texture: texture)
        let w = CGFloat.random(in: 80...160)
        let aspect = texture.size().width / max(texture.size().height, 1)
        node.size = CGSize(width: w, height: w / aspect)
        node.zPosition = 1
        node.alpha = Bool.random() ? 0.5 : 1.0

        if node.alpha == 0.5 && Bool.random() {
            node.zPosition = 18  // occasionally in front of game elements, below HUD
        }

        let y = CGFloat.random(
            in: scene.size.height * 0.30...scene.size.height * 0.90
        )
        let goingLeft = Bool.random()
        let speed = CGFloat.random(in: 20...50)

        let startX: CGFloat
        let endX: CGFloat
        if preplace {
            startX = CGFloat.random(in: 0...scene.size.width)
            endX =
                goingLeft
                ? -node.size.width : scene.size.width + node.size.width
        } else {
            startX =
                goingLeft
                ? scene.size.width + node.size.width : -node.size.width
            endX =
                goingLeft
                ? -node.size.width : scene.size.width + node.size.width
        }

        node.position = CGPoint(x: startX, y: y)
        scene.addChild(node)

        let duration = TimeInterval(abs(endX - startX) / speed)
        node.run(
            .sequence([
                .moveTo(x: endX, duration: duration), .removeFromParent(),
            ])
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - State Change Detector
// ─────────────────────────────────────────────────────────────────────────────

/// Diffs previous vs current bridge state each frame and emits typed GameEvents.
/// Owns all `prev*` state so no other class needs it.
final class StateChangeDetector {
    private var prevIsDead = [Bool](repeating: false, count: 2)
    private var prevHP = [Int](repeating: 3, count: 2)
    private var prevHasJumped = [Bool](repeating: false, count: 2)
    private var prevChuteOpen = [Bool](repeating: false, count: 2)
    private var prevChuteBroken = [Bool](repeating: false, count: 2)
    private var prevPilotIsDead = [Bool](repeating: false, count: 2)
    private var prevIsRunning = [Bool](repeating: false, count: 2)
    private var prevBulletCount = 0
    private var prevRoundFinished = false

    // Cached for spark spawn position (bridge resets coords to 0 on death)
    private var lastWorldX = [Float](repeating: 0, count: 2)
    private var lastWorldY = [Float](repeating: 0, count: 2)
    private var lastPlaneDir = [Float](repeating: 0, count: 2)
    private var lastPlaneSpeed = [Float](repeating: 0, count: 2)

    func detect(
        state: BiplanesBridgeState,
        planes: [PlaneState],
        bullets: [BulletState]
    ) -> [GameEvent] {
        var events: [GameEvent] = []

        for i in 0..<2 {
            let p = planes[i]

            // Keep alive snapshot before death overwrites coords
            if !p.isDead {
                lastWorldX[i] = p.x
                lastWorldY[i] = p.y
                lastPlaneDir[i] = p.dir
                lastPlaneSpeed[i] = p.speed
            }

            // ── Plane ────────────────────────────────────────────────────────
            if p.isDead && !prevIsDead[i] {
                events.append(
                    .planeDestroyed(
                        playerIndex: i,
                        worldX: lastWorldX[i],
                        worldY: lastWorldY[i],
                        dir: lastPlaneDir[i],
                        speed: lastPlaneSpeed[i]
                    )
                )
            }
            if !p.isDead && Int(p.hp) < prevHP[i] && p.hp > 0 {
                events.append(.planeDamaged(playerIndex: i))
            }
            if !p.isDead { prevHP[i] = Int(p.hp) }
            prevIsDead[i] = p.isDead

            // ── Pilot ────────────────────────────────────────────────────────
            if p.hasJumped {
                if !prevHasJumped[i] {
                    events.append(.pilotJumped(playerIndex: i))
                }
                if p.pilotIsDead && !prevPilotIsDead[i] {
                    events.append(.pilotDied(playerIndex: i))
                }
                if p.pilotChuteOpen && !prevChuteOpen[i] {
                    events.append(.chuteOpened(playerIndex: i))
                }
                if p.pilotChuteBroken && !prevChuteBroken[i] {
                    events.append(.chuteBroken(playerIndex: i))
                }
                if p.pilotIsRunning && !prevIsRunning[i] {
                    events.append(.pilotLanded(playerIndex: i))
                }

                prevHasJumped[i] = true
                prevPilotIsDead[i] = p.pilotIsDead
                prevChuteOpen[i] = p.pilotChuteOpen
                prevChuteBroken[i] = p.pilotChuteBroken
                prevIsRunning[i] = p.pilotIsRunning
            } else {
                if prevHasJumped[i] {
                    events.append(.pilotRescued(playerIndex: i))
                }
                prevHasJumped[i] = false
                prevPilotIsDead[i] = false
                prevChuteOpen[i] = false
                prevChuteBroken[i] = false
                prevIsRunning[i] = false
            }
        }

        // ── Bullets ──────────────────────────────────────────────────────────
        if bullets.count > prevBulletCount { events.append(.bulletFired) }
        prevBulletCount = bullets.count

        // ── Round ────────────────────────────────────────────────────────────
        if state.roundFinished && !prevRoundFinished {
            events.append(
                .roundFinished(
                    winnerId: state.winnerId >= 0 ? Int(state.winnerId) : nil
                )
            )
        }
        prevRoundFinished = state.roundFinished

        return events
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Audio System
// ─────────────────────────────────────────────────────────────────────────────

/// Sole consumer of GameEvents for audio. GameScene never touches AudioManager directly.
final class AudioSystem {
    private let bridge: BiplanesBridge

    init(bridge: BiplanesBridge) {
        self.bridge = bridge
    }

    func handle(events: [GameEvent]) {
        for event in events {
            switch event {
            case .planeDestroyed:
                AudioManager.shared.playSound("explosion")
            case .planeDamaged:
                AudioManager.shared.playSound("hit_plane")
            case .chuteOpened:
                AudioManager.shared.playSound("chute_loop")
            case .chuteBroken:
                AudioManager.shared.playSound("hit_chute")
            case .pilotLanded:
                AudioManager.shared.playSound("hit_ground")
            case .pilotDied:
                AudioManager.shared.playSound("pilot_death")
            case .pilotRescued:
                AudioManager.shared.playSound("pilot_rescue")
            case .bulletFired:
                AudioManager.shared.playSound("shoot")
            case .roundFinished(let winnerId):
                AudioManager.shared.playSound("victory")
                if let winner = winnerId, winner != bridge.playerId {
                    AudioManager.shared.playSound("defeat")
                }
            case .pilotJumped:
                break  // no dedicated sound
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Renderable
// ─────────────────────────────────────────────────────────────────────────────

protocol Renderable: AnyObject {
    func update(
        planes: [PlaneState],
        bullets: [BulletState],
        state: BiplanesBridgeState,
        events: [GameEvent],
        dt: TimeInterval
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Coordinate Helper
// ─────────────────────────────────────────────────────────────────────────────

/// World [0..1] with Y=0 at top → SpriteKit points with Y=0 at bottom.
private func worldToScreen(x: CGFloat, y: CGFloat, in size: CGSize) -> CGPoint {
    CGPoint(x: x * size.width, y: (1.0 - y) * size.height)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Plane Renderer
// ─────────────────────────────────────────────────────────────────────────────

final class PlaneRenderer: Renderable {
    private unowned let scene: SKScene

    private let nodes: [SKSpriteNode]
    private let stateMachines = [PlaneStateMachine(), PlaneStateMachine()]

    private let smokeTextures: [SKTexture] = (1...5).map {
        SKTexture(imageNamed: "smoke\($0)")
    }
    private let fireTextures: [SKTexture] = (1...3).map {
        SKTexture(imageNamed: "fire\($0)")
    }

    // Green: faces right → base angle = 0
    // Red:   faces left  → base angle = π
    private let baseAngles: [CGFloat] = [0, .pi]

    private let idleTextures: [SKTexture]
    private let flyActions: [SKAction]
    private var isAnimating = [false, false]

    private var smokeTimer = [TimeInterval](repeating: 0, count: 2)
    private var fireTimer  = [TimeInterval](repeating: 0, count: 2)
    // Fire trace spawned every N seconds — matches server's fire::frameTime × frameCount
    private static let fireTraceInterval: TimeInterval = 0.075 * 3  // 0.225 s
    // Once protection expires, prevent any bounce-back blink caused by predictor
    // reconcile briefly restoring a non-zero protectionRemaining.
    // Resets only when protectionRemaining > 1.0 (well into a fresh spawn).
    private var protectionExpired = [false, false]

    init(scene: SKScene, planeColors: [SKColor]) {
        self.scene = scene

        let names = ["green_biplane", "red_biplane"]
        idleTextures = names.map { SKTexture(imageNamed: $0) }
        flyActions = (0..<2).map { i in
            let frames = (1...8).map {
                SKTexture(imageNamed: "\(names[i])\($0)")
            }
            return .repeatForever(
                .animate(
                    with: frames,
                    timePerFrame: 0.03,
                    resize: false,
                    restore: false
                )
            )
        }

        nodes = (0..<2).map { i in
            let tex = SKTexture(imageNamed: names[i])
            let texSize = tex.size()
            let h: CGFloat = 24
            let aspect = texSize.height > 0 ? texSize.width / texSize.height : 1
            let node = SKSpriteNode(texture: tex)
            node.size = CGSize(width: h * aspect, height: h)
            node.color = planeColors[i]
            node.colorBlendFactor = texSize.width > 0 ? 0 : 1
            node.zPosition = 10
            scene.addChild(node)
            return node
        }
    }

    func update(
        planes: [PlaneState],
        bullets: [BulletState],
        state: BiplanesBridgeState,
        events: [GameEvent],
        dt: TimeInterval
    ) {
        for i in 0..<2 {
            let p = planes[i]
            let phase = stateMachines[i].update(from: p)

            guard phase != .dead else {
                nodes[i].isHidden = true
                smokeTimer[i] = 0
                fireTimer[i]  = 0
                stopAnimation(i)
                continue
            }

            nodes[i].isHidden = false
            let pos = worldToScreen(
                x: CGFloat(p.x),
                y: CGFloat(p.y),
                in: scene.size
            )
            nodes[i].position = pos
            nodes[i].zRotation =
                .pi / 2 - CGFloat(p.dir) * .pi / 180 + baseAngles[i]
            // Hard-reset flag prevents blink caused by predictor reconcile
            // briefly bouncing protectionRemaining back above zero.
            if p.protectionRemaining > 1.0 { protectionExpired[i] = false }
            else if p.protectionRemaining == 0 { protectionExpired[i] = true }
            nodes[i].alpha =
                (!protectionExpired[i] && p.protectionRemaining > 0)
                ? CGFloat(0.5 + 0.5 * sin(Double(p.protectionRemaining) * 10))
                : 1

            updateAnimation(i, isOnGround: p.isOnGround)

            switch phase {
            case .damaged, .burning:

                smokeTimer[i] += dt
                if smokeTimer[i] >= 0.06 {
                    smokeTimer[i] = 0
                    spawnTrace(
                        smokeTextures,
                        at: pos,
                        size: 20,
                        zPos: 11,
                        timePerFrame: 0.15
                    )
                }

                if phase == .burning {
                    fireTimer[i] += dt
                    if fireTimer[i] >= Self.fireTraceInterval {
                        fireTimer[i] = 0
                        spawnTrace(
                            fireTextures,
                            at: pos,
                            size: 24,
                            zPos: 12,
                            timePerFrame: 0.075
                        )
                    }
                }
            default:
                smokeTimer[i] = 0
                fireTimer[i]  = 0
            }
        }
    }

    private func updateAnimation(_ i: Int, isOnGround: Bool) {
        let should = !isOnGround
        if should && !isAnimating[i] {
            nodes[i].run(flyActions[i], withKey: "fly")
            isAnimating[i] = true
        } else if !should && isAnimating[i] {
            stopAnimation(i)
        }
    }

    private func stopAnimation(_ i: Int) {
        nodes[i].removeAction(forKey: "fly")
        nodes[i].texture = idleTextures[i]
        isAnimating[i] = false
    }

    private func spawnTrace(
        _ textures: [SKTexture],
        at pos: CGPoint,
        size: CGFloat,
        zPos: CGFloat,
        timePerFrame: TimeInterval
    ) {
        let node = SKSpriteNode(texture: textures[0])
        node.size = CGSize(width: size, height: size)
        node.position = pos
        node.zPosition = zPos
        node.alpha = 0.85
        scene.addChild(node)
        let dur = timePerFrame * Double(textures.count)
        node.run(
            .sequence([
                .group([
                    .animate(
                        with: textures,
                        timePerFrame: timePerFrame,
                        resize: false,
                        restore: false
                    ),
                    .fadeOut(withDuration: dur),
                    .scale(to: 1.6, duration: dur),
                ]),
                .removeFromParent(),
            ])
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Pilot Renderer
// ─────────────────────────────────────────────────────────────────────────────

final class PilotRenderer: Renderable {
    private unowned let scene: SKScene

    private let pilotNodes: [SKSpriteNode]
    private let chuteNodes: [SKSpriteNode]
    private let stateMachines = [PilotStateMachine(), PilotStateMachine()]
    private var facingRight = [true, true]

    private let fallTextures: [[SKTexture]]
    private let runTextures: [[SKTexture]]
    private let idleTextures: [SKTexture]
    private let angelTextures: [SKTexture]

    // Client-side animation timers — independent of server frame counters
    private static let runFrameInterval:   TimeInterval = 0.10  // 10 fps, 5 frames
    private static let fallFrameInterval:  TimeInterval = 0.14  // ~7 fps, 3 frames
    private static let angelFrameInterval: TimeInterval = 0.12  // ~8 fps, 4 frames

    private var runTimer   = [TimeInterval](repeating: 0, count: 2)
    private var fallTimer  = [TimeInterval](repeating: 0, count: 2)
    private var angelTimer = [TimeInterval](repeating: 0, count: 2)
    private var runFrame   = [Int](repeating: 0, count: 2)
    private var fallFrame  = [Int](repeating: 0, count: 2)
    private var angelFrame = [Int](repeating: 0, count: 2)

    init(scene: SKScene) {
        self.scene = scene

        fallTextures = [
            (1...3).map { SKTexture(imageNamed: "pilot_fall_green\($0)") },
            (1...3).map { SKTexture(imageNamed: "pilot_fall_red\($0)") },
        ]
        runTextures = [
            (1...5).map { SKTexture(imageNamed: "pilot_run_green\($0)") },
            (1...5).map { SKTexture(imageNamed: "pilot_run_red\($0)") },
        ]
        idleTextures = [
            SKTexture(imageNamed: "pilot_idle_green"),
            SKTexture(imageNamed: "pilot_idle_red"),
        ]
        angelTextures = (1...4).map {
            SKTexture(imageNamed: "pilot_angel\($0)")
        }

        pilotNodes = (0..<2).map { i in
            let node = SKSpriteNode(
                texture: SKTexture(imageNamed: "pilot_fall_green1")
            )
            node.size = CGSize(width: 15, height: 22)
            node.zPosition = 12
            node.isHidden = true
            scene.addChild(node)
            return node
        }
        chuteNodes = (0..<2).map { _ in
            let node = SKSpriteNode(
                texture: SKTexture(imageNamed: "pilot_parachute")
            )
            node.size = CGSize(width: 44, height: 38)
            node.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.zPosition = 11
            node.isHidden = true
            scene.addChild(node)
            return node
        }
    }

    func update(
        planes: [PlaneState],
        bullets: [BulletState],
        state: BiplanesBridgeState,
        events: [GameEvent],
        dt: TimeInterval
    ) {
        for i in 0..<2 {
            let p = planes[i]
            let phase = stateMachines[i].update(from: p)

            guard p.hasJumped else {
                pilotNodes[i].isHidden = true
                chuteNodes[i].isHidden = true
                continue
            }

            let ppos = worldToScreen(
                x: CGFloat(p.pilotX),
                y: CGFloat(p.pilotY),
                in: scene.size
            )
            pilotNodes[i].position = ppos
            pilotNodes[i].isHidden = false
            chuteNodes[i].isHidden = true

            pilotNodes[i].alpha = 1.0
            
            switch phase {
            case .angel:
                angelTimer[i] += dt
                while angelTimer[i] >= Self.angelFrameInterval {
                    angelTimer[i] -= Self.angelFrameInterval
                    angelFrame[i] = (angelFrame[i] + 1) % angelTextures.count
                }
                pilotNodes[i].texture = angelTextures[angelFrame[i]]
                pilotNodes[i].size = CGSize(width: 20, height: 30)
                pilotNodes[i].xScale = 1
                pilotNodes[i].alpha = 0.5

            case .parachuting:
                fallTimer[i] += dt
                while fallTimer[i] >= Self.fallFrameInterval {
                    fallTimer[i] -= Self.fallFrameInterval
                    fallFrame[i] = (fallFrame[i] + 1) % fallTextures[i].count
                }
                pilotNodes[i].texture = fallTextures[i][fallFrame[i]]
                pilotNodes[i].size = CGSize(width: 15.6, height: 24.2)
                pilotNodes[i].xScale = 1
                // Chute hangs above pilot
                chuteNodes[i].isHidden = false
                chuteNodes[i].position = CGPoint(x: ppos.x, y: ppos.y + 11)
                chuteNodes[i].color =
                    p.pilotChuteBroken
                    ? SKColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1)
                    : .white
                chuteNodes[i].colorBlendFactor = p.pilotChuteBroken ? 0.5 : 0

            case .falling:
                fallTimer[i] += dt
                while fallTimer[i] >= Self.fallFrameInterval {
                    fallTimer[i] -= Self.fallFrameInterval
                    fallFrame[i] = (fallFrame[i] + 1) % fallTextures[i].count
                }
                pilotNodes[i].texture = fallTextures[i][fallFrame[i]]
                pilotNodes[i].size = CGSize(width: 15.6, height: 24.2)
                pilotNodes[i].xScale = 1

            case .runningOrIdle:
                if p.pilotIsRunning && p.pilotIsMoving {
                    runTimer[i] += dt
                    while runTimer[i] >= Self.runFrameInterval {
                        runTimer[i] -= Self.runFrameInterval
                        runFrame[i] = (runFrame[i] + 1) % runTextures[i].count
                    }
                    pilotNodes[i].texture = runTextures[i][runFrame[i]]
                    pilotNodes[i].size = CGSize(width: 19.5, height: 24.2)
                    let right = Int(p.pilotDir) >= 180
                    facingRight[i] = right
                    pilotNodes[i].xScale = right ? 1 : -1
                } else {
                    runTimer[i] = 0
                    runFrame[i] = 0
                    let tex = idleTextures[i]
                    let aspect = tex.size().width / tex.size().height
                    pilotNodes[i].texture = tex
                    pilotNodes[i].size = CGSize(
                        width: 26 * aspect * 1.10 * 0.85 * 1.3,
                        height: 26 * 0.85 * 1.1
                    )
                    pilotNodes[i].xScale = facingRight[i] ? 1 : -1
                }

            case .inPlane:
                runTimer[i] = 0; runFrame[i] = 0
                fallTimer[i] = 0; fallFrame[i] = 0
                angelTimer[i] = 0; angelFrame[i] = 0
                pilotNodes[i].isHidden = true
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Bullet Renderer
// ─────────────────────────────────────────────────────────────────────────────

final class BulletRenderer: Renderable {
    private unowned let scene: SKScene

    // Three-layer composite per bullet + one gradient trail sprite
    private struct BulletVisual {
        let outerGlow: SKShapeNode   // soft wide halo
        let midGlow:   SKShapeNode   // warm mid ring
        let core:      SKShapeNode   // bright white-hot center
        let trail:     SKSpriteNode  // directional gradient streak
    }

    private var pool:          [BulletVisual] = []
    private var prevPositions: [CGPoint?]     = []

    // Built once; reused for every trail sprite in the pool
    private let trailTexture: SKTexture

    // ── Init ──────────────────────────────────────────────────────────────────

    init(scene: SKScene) {
        self.scene       = scene
        self.trailTexture = BulletRenderer.makeTrailTexture()
    }

    // Horizontal gradient: bright yellow-white on the right (bullet tip),
    // fading to transparent warm orange on the left (tail end).
    private static func makeTrailTexture() -> SKTexture {
        let size = CGSize(width: 28, height: 4)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let colors = [
                UIColor(red: 1.00, green: 1.00, blue: 0.80, alpha: 0.95).cgColor,
                UIColor(red: 1.00, green: 0.65, blue: 0.10, alpha: 0.55).cgColor,
                UIColor(red: 1.00, green: 0.30, blue: 0.00, alpha: 0.00).cgColor,
            ] as CFArray
            let locations: [CGFloat] = [0, 0.45, 1]
            let space    = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(
                colorsSpace: space,
                colors: colors,
                locations: locations
            )!
            // Draw right-to-left so anchor point at x=1 is the bright tip
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: size.width, y: size.height / 2),
                end:   CGPoint(x: 0,          y: size.height / 2),
                options: []
            )
        }
        let tex = SKTexture(image: img)
        tex.filteringMode = .linear
        return tex
    }

    // ── Pool management ───────────────────────────────────────────────────────

    private func makeBulletVisual() -> BulletVisual {
        // Outer soft halo
        let outerGlow = SKShapeNode(circleOfRadius: 7)
        outerGlow.fillColor   = SKColor(red: 1.00, green: 0.88, blue: 0.20, alpha: 0.10)
        outerGlow.strokeColor = .clear
        outerGlow.zPosition   = 8
        scene.addChild(outerGlow)

        // Mid warm ring
        let midGlow = SKShapeNode(circleOfRadius: 4)
        midGlow.fillColor   = SKColor(red: 1.00, green: 0.65, blue: 0.10, alpha: 0.40)
        midGlow.strokeColor = .clear
        midGlow.zPosition   = 9
        scene.addChild(midGlow)

        // Bright core
        let core = SKShapeNode(circleOfRadius: 2)
        core.fillColor   = SKColor(red: 1.00, green: 0.97, blue: 0.82, alpha: 1.00)
        core.strokeColor = SKColor(red: 1.00, green: 0.80, blue: 0.30, alpha: 0.60)
        core.lineWidth   = 1
        core.zPosition   = 10
        scene.addChild(core)

        // Gradient trail — anchor at x=1 so position == bullet tip
        let trail = SKSpriteNode(texture: trailTexture)
        trail.size        = CGSize(width: 28, height: 4)
        trail.anchorPoint = CGPoint(x: 1.0, y: 0.5)
        trail.zPosition   = 7
        scene.addChild(trail)

        return BulletVisual(
            outerGlow: outerGlow,
            midGlow:   midGlow,
            core:      core,
            trail:     trail
        )
    }

    // ── Renderable ────────────────────────────────────────────────────────────

    func update(
        planes: [PlaneState],
        bullets: [BulletState],
        state: BiplanesBridgeState,
        events: [GameEvent],
        dt: TimeInterval
    ) {
        // Grow pool on demand
        while pool.count < bullets.count {
            pool.append(makeBulletVisual())
            prevPositions.append(nil)
        }

        // Active bullets
        for (idx, b) in bullets.enumerated() {
            let pos = worldToScreen(
                x: CGFloat(b.x),
                y: CGFloat(b.y),
                in: scene.size
            )

            let v = pool[idx]
            v.outerGlow.position = pos
            v.midGlow.position   = pos
            v.core.position      = pos
            v.trail.position     = pos

            // Orient trail along velocity; reset if bullet teleported (respawn)
            if let prev = prevPositions[idx] {
                let dx = pos.x - prev.x
                let dy = pos.y - prev.y
                let dist = sqrt(dx * dx + dy * dy)

                if dist > 0.5 && dist < 80 {          // ignore teleports
                    v.trail.zRotation   = atan2(dy, dx)
                    let trailLen        = min(28, dist * 3.5)
                    v.trail.size        = CGSize(width: trailLen, height: 4)
                    v.trail.isHidden    = false
                } else if dist >= 80 {
                    v.trail.isHidden = true            // just spawned / teleported
                }
            } else {
                v.trail.isHidden = true                // first frame for this slot
            }

            prevPositions[idx] = pos
            setHidden(false, on: v)
        }

        // Idle pool slots
        for idx in bullets.count..<pool.count {
            setHidden(true, on: pool[idx])
            prevPositions[idx] = nil                   // clear so trail resets on reuse
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func setHidden(_ hidden: Bool, on v: BulletVisual) {
        v.outerGlow.isHidden = hidden
        v.midGlow.isHidden   = hidden
        v.core.isHidden      = hidden
        v.trail.isHidden     = hidden || v.trail.isHidden && !hidden
            ? hidden          // preserve the "just spawned" suppression
            : false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Zeppelin Renderer
// ─────────────────────────────────────────────────────────────────────────────

final class ZeppelinRenderer: Renderable {
    private unowned let scene: SKScene
    private let zepNode: SKSpriteNode
    private let scoreLabels: [SKLabelNode]

    private var x: CGFloat = 0.5
    private var y: CGFloat = 0.2
    private var vx: CGFloat = 0.012
    private var vy: CGFloat = 0.008
    private var dirTimer: TimeInterval = 0
    private var nextDirChange = TimeInterval.random(in: 2...5)

    init(scene: SKScene, planeColors: [SKColor]) {
        self.scene = scene

        let tex = SKTexture(imageNamed: "zeppilin")
        tex.filteringMode = .linear
        zepNode = SKSpriteNode(texture: tex)
        zepNode.size = CGSize(width: 80, height: 44)
        zepNode.zPosition = 15
        zepNode.position = CGPoint(
            x: scene.size.width * 0.5,
            y: scene.size.height * 0.8
        )
        scene.addChild(zepNode)

        scoreLabels = (0..<2).map { i in
            let label = SKLabelNode(fontNamed: "AmericanTypewriter")
            label.fontSize = 16
            label.fontColor = planeColors[i]
            label.zPosition = 16
            label.text = "0"
            label.horizontalAlignmentMode = i == 0 ? .right : .left
            scene.addChild(label)
            return label
        }
    }

    func update(
        planes: [PlaneState],
        bullets: [BulletState],
        state: BiplanesBridgeState,
        events: [GameEvent],
        dt: TimeInterval
    ) {
        guard dt > 0 else { return }

        dirTimer += dt
        if dirTimer >= nextDirChange {
            dirTimer = 0
            nextDirChange = TimeInterval.random(in: 2...5)
            vx = CGFloat.random(in: 0.006...0.020) * (Bool.random() ? 1 : -1)
            vy = CGFloat.random(in: 0.003...0.012) * (Bool.random() ? 1 : -1)
        }

        // Edge avoidance
        if x < 0.15 { vx = abs(vx) }
        if x > 0.85 { vx = -abs(vx) }
        if y < 0.05 { vy = abs(vy) }
        if y > 0.45 { vy = -abs(vy) }

        x = (x + vx * CGFloat(dt)).clamped(to: 0.15...0.85)
        y = (y + vy * CGFloat(dt)).clamped(to: 0.05...0.45)

        let pos = worldToScreen(x: x, y: y, in: scene.size)
        zepNode.position = pos

        for i in 0..<2 {
            scoreLabels[i].text = "\(planes[i].score)"
            scoreLabels[i].position = CGPoint(
                x: pos.x + (i == 0 ? -6 : 10),
                y: pos.y - 2
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - HUD Renderer
// ─────────────────────────────────────────────────────────────────────────────

final class HUDRenderer: Renderable {
    private unowned let scene: SKScene
    private let scoreLabels: [SKLabelNode]
    private let hpBarBg: [SKShapeNode]
    private let hpBarFg: [SKShapeNode]
    private let winLabel: SKLabelNode
    private let planeColors: [SKColor]

    init(scene: SKScene, bridge: BiplanesBridge, planeColors: [SKColor]) {
        self.scene = scene
        self.planeColors = planeColors

        scoreLabels = (0..<2).map { i in
            let label = SKLabelNode(fontNamed: "Helvetica-Bold")
            label.fontSize = 16
            label.fontColor = planeColors[i]
            label.zPosition = 20
            label.text = "Score: 0"
            label.horizontalAlignmentMode = i == 0 ? .left : .right
            label.verticalAlignmentMode = .top
            label.position = CGPoint(
                x: i == 0 ? 10 : scene.size.width - 10,
                y: scene.size.height - 10
            )
            scene.addChild(label)
            return label
        }

        hpBarBg = (0..<2).map { i in
            let bar = SKShapeNode(
                rectOf: CGSize(width: 60, height: 8),
                cornerRadius: 2
            )
            bar.fillColor = SKColor(white: 0.2, alpha: 0.8)
            bar.strokeColor = .clear
            bar.zPosition = 20
            bar.position = CGPoint(
                x: i == 0 ? 40 : scene.size.width - 40,
                y: scene.size.height - 34
            )
            scene.addChild(bar)
            return bar
        }

        hpBarFg = (0..<2).map { i in
            let bar = SKShapeNode(
                rectOf: CGSize(width: 60, height: 8),
                cornerRadius: 2
            )
            bar.fillColor = SKColor(
                red: 0.31,
                green: 0.86,
                blue: 0.31,
                alpha: 1
            )
            bar.strokeColor = .clear
            bar.zPosition = 21
            bar.position = CGPoint(
                x: i == 0 ? 40 : scene.size.width - 40,
                y: scene.size.height - 34
            )
            scene.addChild(bar)
            return bar
        }

        let modeLabel = SKLabelNode(fontNamed: "Helvetica")
        modeLabel.fontSize = 13
        modeLabel.fontColor = SKColor(
            red: 0.90,
            green: 0.75,
            blue: 0.30,
            alpha: 1
        )
        modeLabel.zPosition = 20
        modeLabel.text = bridge.isOffline ? "OFFLINE vs BOT" : "ONLINE"
        modeLabel.horizontalAlignmentMode = .center
        modeLabel.position = CGPoint(
            x: scene.size.width * 0.5,
            y: scene.size.height - 18
        )
        scene.addChild(modeLabel)

        winLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        winLabel.fontSize = 40
        winLabel.fontColor = .white
        winLabel.zPosition = 30
        winLabel.isHidden = true
        winLabel.horizontalAlignmentMode = .center
        winLabel.verticalAlignmentMode = .center
        winLabel.position = CGPoint(
            x: scene.size.width * 0.5,
            y: scene.size.height * 0.5
        )
        scene.addChild(winLabel)
    }

    func update(
        planes: [PlaneState],
        bullets: [BulletState],
        state: BiplanesBridgeState,
        events: [GameEvent],
        dt: TimeInterval
    ) {
        for i in 0..<2 {
            let p = planes[i]
            scoreLabels[i].text = "Score: \(p.score)"

            let fraction = CGFloat(max(0, p.hp)) / 3.0
            let filled = max(2, 60 * fraction)
            let bar = SKShapeNode(
                rectOf: CGSize(width: filled, height: 8),
                cornerRadius: 2
            )
            bar.fillColor =
                fraction > 0.5
                ? SKColor(red: 0.31, green: 0.86, blue: 0.31, alpha: 1)
                : SKColor(red: 0.86, green: 0.55, blue: 0.20, alpha: 1)
            hpBarFg[i].path = bar.path
            hpBarFg[i].fillColor = bar.fillColor
        }

        if state.roundFinished {
            winLabel.isHidden = false
            switch state.winnerId {
            case 0:
                winLabel.text = "🟢 Green Wins!"
                winLabel.fontColor = planeColors[0]
            case 1:
                winLabel.text = "🔴 Red Wins!"
                winLabel.fontColor = planeColors[1]
            default:
                winLabel.text = "Draw"
                winLabel.fontColor = .white
            }
        } else {
            winLabel.isHidden = true
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Effects Renderer
// ─────────────────────────────────────────────────────────────────────────────

final class EffectsRenderer: Renderable {
    private unowned let scene: SKScene
    private let explodeTextures: [SKTexture] = (1...8).map {
        SKTexture(imageNamed: "explode\($0)")
    }

    private struct Spark {
        var x, y, vx, vy: Float
        var bounces: Int
        var colorTimer: Float
        var colorIndex: Int
        let node: SKShapeNode
    }
    private var sparks: [Spark] = []

    private static let sparkColors: [SKColor] = [
        SKColor(red: 0, green: 0, blue: 0, alpha: 1),
        SKColor(red: 246 / 255, green: 99 / 255, blue: 0, alpha: 1),
        SKColor(red: 1, green: 1, blue: 1, alpha: 1),
        SKColor(red: 253 / 255, green: 255 / 255, blue: 108 / 255, alpha: 1),
    ]

    private enum K {  // spark constants mirrored from C++
        static let count = 25
        static let colorTime: Float = 0.035
        static let gravity: Float = 0.75
        static let speedMin: Float = 0.4
        static let speedMax: Float = 0.6
        static let speedMask: Float = Float(count) / 1.0123456789
        static let dirRange: Float = 75
        static let dirOffset: Float = 75 * 0.2
        static let bounceSpd: Float = 0.1
        static let maxBounces = 2
        static let groundY: Float = 182 / 208.0
        static let barnRoofY: Float = 168.48 / 208.0
        static let barnLeft: Float = 0.5 - (36.0 / 256.0) * 0.475
        static let barnRight: Float = barnLeft + (36.0 / 256.0) * 0.95
    }

    init(scene: SKScene) { self.scene = scene }

    func update(
        planes: [PlaneState],
        bullets: [BulletState],
        state: BiplanesBridgeState,
        events: [GameEvent],
        dt: TimeInterval
    ) {
        for event in events {
            if case .planeDestroyed(_, let wx, let wy, let dir, let speed) =
                event
            {
                let pos = worldToScreen(
                    x: CGFloat(wx),
                    y: CGFloat(wy),
                    in: scene.size
                )
                spawnExplosion(at: pos)
                spawnSparks(wx: wx, wy: wy, dir: dir, speed: speed)
            }
        }
        updateSparks(dt: Float(dt))
    }

    private func spawnExplosion(at pos: CGPoint) {
        let node = SKSpriteNode(texture: explodeTextures[0])
        node.size = CGSize(width: 72, height: 72)
        node.position = pos
        node.zPosition = 20
        scene.addChild(node)
        node.run(
            .sequence([
                .group([
                    .animate(
                        with: explodeTextures,
                        timePerFrame: 0.06,
                        resize: false,
                        restore: false
                    ),
                    .sequence([
                        .wait(forDuration: 0.24), .fadeOut(withDuration: 0.24),
                    ]),
                ]),
                .removeFromParent(),
            ])
        )
    }

    private func spawnSparks(wx: Float, wy: Float, dir: Float, speed: Float) {
        let dirFactor = sin(dir * .pi / 180)
        let offset = K.dirOffset * dirFactor * (speed / 0.4)

        for i in 0..<K.count {
            let t = Float(i) / Float(K.count)
            let deg =
                offset + K.dirRange
                * (-0.5 + t + 0.45 * dirFactor / Float(K.count))
            let spd =
                K.speedMin + K.speedMask.truncatingRemainder(
                    dividingBy: t + 0.001
                )
                * (K.speedMax - K.speedMin)
            let rad = deg * .pi / 180
            let node = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
            node.fillColor = EffectsRenderer.sparkColors[0]
            node.strokeColor = .clear
            node.zPosition = 19
            scene.addChild(node)
            sparks.append(
                Spark(
                    x: wx,
                    y: wy,
                    vx: sin(rad) * spd,
                    vy: -cos(rad) * spd,
                    bounces: 0,
                    colorTimer: 0,
                    colorIndex: 0,
                    node: node
                )
            )
        }
    }

    private func updateSparks(dt: Float) {
        var i = 0
        while i < sparks.count {
            var s = sparks[i]

            s.colorTimer += dt
            if s.colorTimer >= K.colorTime {
                s.colorTimer -= K.colorTime
                s.colorIndex =
                    (s.colorIndex + 1) % EffectsRenderer.sparkColors.count
                s.node.fillColor = EffectsRenderer.sparkColors[s.colorIndex]
            }

            s.vx -= s.vx * dt
            s.vy += K.gravity * dt
            s.x += s.vx * dt
            s.y += s.vy * dt
            s.x = (s.x.truncatingRemainder(dividingBy: 1) + 1)
                .truncatingRemainder(dividingBy: 1)

            if s.vy > 0 {
                if s.bounces >= K.maxBounces {
                    s.node.removeFromParent()
                    sparks.remove(at: i)
                    continue
                }
                let onBarn = s.x >= K.barnLeft && s.x <= K.barnRight
                let hitBarn = onBarn && s.y >= K.barnRoofY
                let hitFloor = !onBarn && s.y >= K.groundY
                if hitBarn || hitFloor {
                    s.y = hitBarn ? K.barnRoofY : K.groundY
                    s.vy = -K.bounceSpd
                    s.bounces += 1
                }
            }

            s.node.position = worldToScreen(
                x: CGFloat(s.x),
                y: CGFloat(s.y),
                in: scene.size
            )
            sparks[i] = s
            i += 1
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Debug Renderer
// ─────────────────────────────────────────────────────────────────────────────

final class DebugRenderer: Renderable {
    var isVisible: Bool {
        get { !container.isHidden }
        set { container.isHidden = !newValue }
    }

    private unowned let scene: SKScene
    private let container = SKNode()
    private var planeBoxes: [[SKShapeNode]] = []

    init(scene: SKScene, show: Bool) {
        self.scene = scene
        container.zPosition = 50
        scene.addChild(container)
        buildOverlay()
        container.isHidden = !show
    }

    private func rect(_ color: SKColor) -> SKShapeNode {
        let n = SKShapeNode()
        n.fillColor = color.withAlphaComponent(0.25)
        n.strokeColor = color.withAlphaComponent(0.85)
        n.lineWidth = 1.5
        n.zPosition = 50
        return n
    }

    private func buildOverlay() {
        planeBoxes = (0..<2).map { _ in
            let boxes = [rect(.cyan), rect(.yellow), rect(.magenta)]
            boxes.forEach { container.addChild($0) }
            return boxes
        }

        let barnBox = rect(.orange)
        let bx = (0.5 - (36.0 / 256.0) * 0.5) * scene.size.width
        let bw = (36.0 / 256.0) * scene.size.width
        let by = (1.0 - 163.904 / 208.0) * scene.size.height
        let bh = (33.0 / 208.0) * scene.size.height
        barnBox.path = CGPath(
            rect: CGRect(x: bx, y: by - bh, width: bw, height: bh),
            transform: nil
        )
        container.addChild(barnBox)

        let floorY = (1.0 - 182.0 / 208.0) * scene.size.height
        let line = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: floorY))
        path.addLine(to: CGPoint(x: scene.size.width, y: floorY))
        line.path = path
        line.strokeColor = SKColor.red.withAlphaComponent(0.7)
        line.lineWidth = 1.5
        line.zPosition = 50
        container.addChild(line)
    }

    func update(
        planes: [PlaneState],
        bullets: [BulletState],
        state: BiplanesBridgeState,
        events: [GameEvent],
        dt: TimeInterval
    ) {
        guard !container.isHidden else { return }

        let pHW: CGFloat = (24.0 / 256.0) / 3 * 2 / 2
        let pHH: CGFloat = (24.0 / 208.0) / 3 * 2 / 2
        let iHW: CGFloat = (7.0 / 256.0) / 2
        let iHH: CGFloat = (12.0 / 208.0) / 2
        let cW: CGFloat = 20.0 / 256
        let cH: CGFloat = 18.0 / 208
        let cOY: CGFloat = 1.375 * cH

        for i in 0..<2 {
            let p = planes[i]
            let b = planeBoxes[i]
            let W = scene.size.width
            let H = scene.size.height

            if !p.isDead {
                let px = CGFloat(p.x)
                let py = CGFloat(p.y)
                b[0].path = CGPath(
                    rect: CGRect(
                        x: (px - pHW) * W,
                        y: (1 - (py + pHH)) * H,
                        width: pHW * 2 * W,
                        height: pHH * 2 * H
                    ),
                    transform: nil
                )
                b[0].isHidden = false
            } else {
                b[0].isHidden = true
            }

            if p.hasJumped && !p.pilotIsDead {
                let px = CGFloat(p.pilotX)
                let py = CGFloat(p.pilotY)
                b[1].path = CGPath(
                    rect: CGRect(
                        x: (px - iHW) * W,
                        y: (1 - (py + iHH)) * H,
                        width: iHW * 2 * W,
                        height: iHH * 2 * H
                    ),
                    transform: nil
                )
                b[1].isHidden = false
                if p.pilotChuteOpen {
                    b[2].path = CGPath(
                        rect: CGRect(
                            x: (px - cW / 2) * W,
                            y: (1 - (py - cOY + cH)) * H,
                            width: cW * W,
                            height: cH * H
                        ),
                        transform: nil
                    )
                    b[2].isHidden = false
                } else {
                    b[2].isHidden = true
                }
            } else {
                b[1].isHidden = true
                b[2].isHidden = true
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Game Coordinator
// ─────────────────────────────────────────────────────────────────────────────

/// Owns and sequences all subsystems. GameScene calls only `update(currentTime:)`.
final class GameCoordinator {
    private let bridge: BiplanesBridge
    private let detector = StateChangeDetector()
    private let audioSystem: AudioSystem
    private let renderers: [Renderable]
    private let cloudTextures: [SKTexture] = (1...4).map {
        SKTexture(imageNamed: "cloud\($0)")
    }
    private weak var scene: SKScene?
    private var lastUpdateTime: TimeInterval = 0

    init(bridge: BiplanesBridge, scene: SKScene, showDebug: Bool) {
        self.bridge = bridge
        self.scene = scene
        self.audioSystem = AudioSystem(bridge: bridge)

        let planeColors: [SKColor] = [
            SKColor(red: 0.48, green: 0.55, blue: 0.35, alpha: 1),
            SKColor(red: 0.63, green: 0.25, blue: 0.18, alpha: 1),
        ]

        renderers = [
            PlaneRenderer(scene: scene, planeColors: planeColors),
            PilotRenderer(scene: scene),
            BulletRenderer(scene: scene),
            ZeppelinRenderer(scene: scene, planeColors: planeColors),
            HUDRenderer(scene: scene, bridge: bridge, planeColors: planeColors),
            EffectsRenderer(scene: scene),
            DebugRenderer(scene: scene, show: showDebug),
        ]

        startCloudSpawner()
    }

    func update(currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        guard let state = bridge.currentState(),
            let planes = state.planes,
            let bullets = state.bullets,
            planes.count == 2
        else { return }

        let events = detector.detect(
            state: state,
            planes: planes,
            bullets: bullets
        )
        audioSystem.handle(events: events)
        renderers.forEach {
            $0.update(
                planes: planes,
                bullets: bullets,
                state: state,
                events: events,
                dt: dt
            )
        }
    }

    // MARK: Cloud scheduling

    private func startCloudSpawner() {
        guard let scene else { return }
        for _ in 0..<4 {
            SpawnCloudCommand(
                scene: scene,
                cloudTextures: cloudTextures,
                preplace: true
            ).execute()
        }
        scheduleNextCloud()
    }

    private func scheduleNextCloud() {
        guard let scene else { return }
        let delay = TimeInterval.random(in: 3...7)
        scene.run(
            .sequence([
                .wait(forDuration: delay),
                .run { [weak self] in
                    guard let self, let scene = self.scene else { return }
                    SpawnCloudCommand(
                        scene: scene,
                        cloudTextures: self.cloudTextures,
                        preplace: false
                    ).execute()
                    self.scheduleNextCloud()
                },
            ])
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - GameScene   (thin shell — just wires bridge → coordinator)
// ─────────────────────────────────────────────────────────────────────────────

final class GameScene: SKScene {

    var showDebugBoxes = true

    private let bridge: BiplanesBridge
    private let bgIndex: Int
    private var coordinator: GameCoordinator?

    init(bridge: BiplanesBridge, size: CGSize, bgIndex: Int) {
        self.bridge = bridge
        self.bgIndex = bgIndex
        super.init(size: size)
        scaleMode = .aspectFit
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        // Apply crisp nearest-neighbour filtering to all sprite-sheet textures
        // so they stay sharp when the scene is scaled up on iPad.
        let atlas = SKTextureAtlas(named: "biplanes")
        for name in atlas.textureNames {
            atlas.textureNamed(name).filteringMode = .nearest
        }
        buildStaticScene()
        coordinator = GameCoordinator(
            bridge: bridge,
            scene: self,
            showDebug: showDebugBoxes
        )
    }

    override func update(_ currentTime: TimeInterval) {
        coordinator?.update(currentTime: currentTime)
    }

    // Static geometry that belongs to the scene, not any renderer
    private func buildStaticScene() {
        let bgTex = SKTexture(imageNamed: "backround_\(bgIndex)")
        bgTex.filteringMode = .nearest
        let bg = SKSpriteNode(texture: bgTex)
        bg.size = size
        bg.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        bg.zPosition = -10
        addChild(bg)

        let barnRoofY: CGFloat = 163.904 / 208.0
        let bw = size.width * 0.14
        let bh = size.height * 0.10
        let barnTex = SKTexture(imageNamed: "barn")
        barnTex.filteringMode = .nearest
        let barn = SKSpriteNode(texture: barnTex)
        barn.size = CGSize(width: bw, height: bh)
        barn.position = CGPoint(
            x: size.width * 0.5,
            y: (1 - barnRoofY) * size.height - bh * 0.5
        )
        barn.zPosition = 5
        addChild(barn)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Comparable extension
// ─────────────────────────────────────────────────────────────────────────────

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
