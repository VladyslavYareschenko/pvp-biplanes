import SpriteKit

/// SpriteKit scene that renders the game state from BiplanesBridge each frame.
final class GameScene: SKScene {

    // ── Constants ──────────────────────────────────────────────────────────
    private let barnSizeX: CGFloat    = 0.14
    private let barnSizeY: CGFloat    = 0.10
    private let barnCollisionY: CGFloat = 0.87

    // ── Plane sprite names & rotation base angles ───────────────────────────
    // green_biplane faces RIGHT  → needs no offset to align with dir=90 (right)
    // red_biplane   faces LEFT   → needs +π offset so dir=270 (left) = no rotation
    private let planeImageNames: [String] = ["green_biplane", "red_biplane"]
    private let planeBaseAngles: [CGFloat] = [0, .pi]

    // ── Nodes ──────────────────────────────────────────────────────────────

    // Planes — SKSpriteNode for textured rendering
    private var planeNodes  = [SKSpriteNode(), SKSpriteNode()]

    // Smoke & fire: preloaded textures; effects are spawned as transient trace nodes
    private let smokeTextures:   [SKTexture] = (1...5).map { SKTexture(imageNamed: "smoke\($0)") }
    private let fireTextures:    [SKTexture] = (1...3).map { SKTexture(imageNamed: "fire\($0)") }
    private let explodeTextures: [SKTexture] = (1...8).map { SKTexture(imageNamed: "explode\($0)") }
    // Swift-side timers for smoke/fire spawn rate (seconds since last spawn)
    private var smokeTimer     = [TimeInterval](repeating: 0, count: 2)
    private var fireTimer      = [TimeInterval](repeating: 0, count: 2)
    private var lastUpdateTime: TimeInterval = 0
    private var prevFireFrame  = [Int](repeating: -1, count: 2)
    private var prevIsDead     = [Bool](repeating: false, count: 2)
    private var prevPilotIsDead = [Bool](repeating: false, count: 2)
    // Last-alive state needed to spawn sparks at correct position/direction
    private var lastWorldX     = [Float](repeating: 0, count: 2)
    private var lastWorldY     = [Float](repeating: 0, count: 2)
    private var lastPlaneDir   = [Float](repeating: 0, count: 2)
    private var lastPlaneSpeed = [Float](repeating: 0, count: 2)

    // ── Spark simulation ────────────────────────────────────────────────────
    private struct SparkState {
        var x, y:   Float          // world coords (y: 0=top, 1=bottom)
        var vx, vy: Float
        var bounces:    Int
        var colorTimer: Float
        var colorIndex: Int
        let node: SKShapeNode
    }
    private var activeSparks = [SparkState]()
    private static let sparkColors: [SKColor] = [
        SKColor(red: 0,       green: 0,       blue: 0,       alpha: 1), // black
        SKColor(red: 246/255, green: 99/255,  blue: 0,       alpha: 1), // orange
        SKColor(red: 1,       green: 1,       blue: 1,       alpha: 1), // white
        SKColor(red: 253/255, green: 255/255, blue: 108/255, alpha: 1), // yellow
    ]

    // Pilots — sprite-based with fall/run/idle animation
    private let pilotFallTextures: [[SKTexture]] = {
        let textures = [
            (1...3).map { SKTexture(imageNamed: "pilot_fall_green\($0)") },
            (1...3).map { SKTexture(imageNamed: "pilot_fall_red\($0)") }
        ]
        textures.forEach { colors in colors.forEach { $0.filteringMode = .linear } }
        return textures
    }()
    private let pilotRunTextures: [[SKTexture]] = {
        let textures = [
            (1...5).map { SKTexture(imageNamed: "pilot_run_green\($0)") },
            (1...5).map { SKTexture(imageNamed: "pilot_run_red\($0)") }
        ]
        textures.forEach { colors in colors.forEach { $0.filteringMode = .linear } }
        return textures
    }()
    private let pilotIdleTextures: [SKTexture] = {
        let textures = [
            SKTexture(imageNamed: "pilot_idle_green"),
            SKTexture(imageNamed: "pilot_idle_red")
        ]
        textures.forEach { $0.filteringMode = .linear }
        return textures
    }()
    private let pilotAngelTextures: [SKTexture] = {
        let textures = [
            SKTexture(imageNamed: "pilot_angel1"),
            SKTexture(imageNamed: "pilot_angel2"),
            SKTexture(imageNamed: "pilot_angel3"),
            SKTexture(imageNamed: "pilot_angel4")
        ]
        textures.forEach { $0.filteringMode = .linear }
        return textures
    }()
    private var pilotNodes      = [SKSpriteNode(), SKSpriteNode()]
    private var chuteNodes      = [SKSpriteNode(), SKSpriteNode()]
    private var pilotAnimTimer  = [TimeInterval](repeating: 0, count: 2)
    private var pilotAnimFrame  = [Int](repeating: 0, count: 2)
    private var pilotFacingRight = [Bool](repeating: true, count: 2)

    // Bullets — reused pool
    private var bulletPool  = [SKShapeNode]()
    private var bulletCount = 0

    // HUD
    private var scoreLabels    = [SKLabelNode(), SKLabelNode()]
    private var hpBarBg        = [SKShapeNode(), SKShapeNode()]
    private var hpBarFg        = [SKShapeNode(), SKShapeNode()]
    private var modeLabel      = SKLabelNode()
    private var winLabel       = SKLabelNode()

    // Zeppelin score display
    private var zeppilinNode   = SKSpriteNode()
    private var zeppilinScoreLabels: [SKLabelNode] = [SKLabelNode(), SKLabelNode()]
    private var zeppilinX: CGFloat = 0.5
    private var zeppilinY: CGFloat = 0.2
    private var zeppilinIsAscending = true
    private var zeppilinVX: CGFloat = 0.012   // world-space units per second
    private var zeppilinVY: CGFloat = 0.008
    private var zeppilinDirChangeTimer: TimeInterval = 0
    private var zeppilinNextDirChange: TimeInterval = TimeInterval.random(in: 2.0...5.0)
    
    private var prevBulletCount = 0
    private var prevRoundFinished = false
    
    // Audio tracking for state changes
    private var prevChuteOpen = [Bool](repeating: false, count: 2)
    private var prevChuteBroken = [Bool](repeating: false, count: 2)
    private var prevIsRunning = [Bool](repeating: false, count: 2)
    private var prevHP = [Int](repeating: 0, count: 2)
    private var prevHasJumped = [Bool](repeating: false, count: 2)
    private var prevPilotIsFalling = [Bool](repeating: false, count: 2)
    private var chuteLoopPlaying = [Bool](repeating: false, count: 2)
    private var fallLoopPlaying = [Bool](repeating: false, count: 2)

    // Static scene
    private var bgNode         = SKSpriteNode()
    private var barnNode       = SKSpriteNode()

    // ── Debug overlay ───────────────────────────────────────────────────────
    var showDebugBoxes = true
    private var debugContainer = SKNode()
    // Per-plane: [planeBox, pilotBox, chuteBox]
    private var debugPlaneBoxes: [[SKShapeNode]] = []
    // Barn + floor
    private var debugBarnBox:  SKShapeNode = SKShapeNode()
    private var debugFloorLine: SKShapeNode = SKShapeNode()

    // Clouds
    private let cloudTextures: [SKTexture] = (1...4).map { SKTexture(imageNamed: "cloud\($0)") }


    private let greenIdleTexture  = SKTexture(imageNamed: "green_biplane")
    private lazy var greenAnimFrames: [SKTexture] = (1...8).map {
        SKTexture(imageNamed: "green_biplane\($0)")
    }
    private lazy var greenFlyAction: SKAction = .repeatForever(
        .animate(with: greenAnimFrames, timePerFrame: 0.03, resize: false, restore: false)
    )
    private var greenIsAnimating = false

    // Red biplane animation
    private let redIdleTexture    = SKTexture(imageNamed: "red_biplane")
    private lazy var redAnimFrames: [SKTexture] = (1...8).map {
        SKTexture(imageNamed: "red_biplane\($0)")
    }
    private lazy var redFlyAction: SKAction = .repeatForever(
        .animate(with: redAnimFrames, timePerFrame: 0.03, resize: false, restore: false)
    )
    private var redIsAnimating = false

    private let bridge: BiplanesBridge

    // Plane colours for HUD (score / HP bar labels)
    private let planeColors: [SKColor] = [
        SKColor(red: 0.48, green: 0.55, blue: 0.35, alpha: 1),  // green
        SKColor(red: 0.63, green: 0.25, blue: 0.18, alpha: 1),  // red
    ]

    // ── Init ───────────────────────────────────────────────────────────────

    private let bgIndex: Int

    init(bridge: BiplanesBridge, size: CGSize, bgIndex: Int) {
        self.bridge = bridge
        self.bgIndex = bgIndex
        super.init(size: size)
        scaleMode = .aspectFit
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        buildStaticScene()
        buildDynamicNodes()
        startCloudSpawner()
        buildDebugOverlay()
    }

    // ── Debug overlay ───────────────────────────────────────────────────────

    private func makeDebugRect(color: SKColor) -> SKShapeNode {
        let n = SKShapeNode()
        n.fillColor   = color.withAlphaComponent(0.25)
        n.strokeColor = color.withAlphaComponent(0.85)
        n.lineWidth   = 1.5
        n.zPosition   = 50
        return n
    }

    private func buildDebugOverlay() {
        debugContainer.zPosition = 50
        addChild(debugContainer)

        let planeColor = SKColor.cyan
        let pilotColor = SKColor.yellow
        let chuteColor = SKColor.magenta
        let barnColor  = SKColor.orange
        let floorColor = SKColor.red

        debugPlaneBoxes = (0..<2).map { _ in
            let boxes = [
                makeDebugRect(color: planeColor),
                makeDebugRect(color: pilotColor),
                makeDebugRect(color: chuteColor),
            ]
            boxes.forEach { debugContainer.addChild($0) }
            return boxes
        }

        // Barn box (static)
        let barnBox = makeDebugRect(color: barnColor)
        let bBarnX: CGFloat = (0.5 - (36.0/256.0) * 0.5) * size.width
        let bBarnW: CGFloat = (36.0/256.0) * size.width
        let bBarnRoofY: CGFloat = (1.0 - 163.904/208.0) * size.height
        let bBarnH: CGFloat = (33.0/208.0) * size.height
        barnBox.path = CGPath(rect: CGRect(x: bBarnX, y: bBarnRoofY - bBarnH, width: bBarnW, height: bBarnH), transform: nil)
        barnBox.position = .zero
        debugContainer.addChild(barnBox)
        debugBarnBox = barnBox

        // Floor line (static)
        let floorY = (1.0 - 182.0/208.0) * size.height
        let line = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: floorY))
        path.addLine(to: CGPoint(x: size.width, y: floorY))
        line.path        = path
        line.strokeColor = floorColor.withAlphaComponent(0.7)
        line.lineWidth   = 1.5
        line.zPosition   = 50
        debugContainer.addChild(line)
        debugFloorLine = line

        debugContainer.isHidden = !showDebugBoxes
    }

    private func updateDebugOverlay(_ planes: [PlaneState]) {
        guard showDebugBoxes else { debugContainer.isHidden = true; return }
        debugContainer.isHidden = false

        // C++ mirrored constants (world space, 0–1)
        let planHW: CGFloat = (24.0/256.0) / 3.0 * 2.0 / 2.0   // hitboxSizeX/2
        let planHH: CGFloat = (24.0/208.0) / 3.0 * 2.0 / 2.0   // hitboxSizeY/2
        let pilHW:  CGFloat = (7.0/256.0)  / 2.0
        let pilHH:  CGFloat = (12.0/208.0)  / 2.0
        let chuteW: CGFloat = (20.0/256.0)
        let chuteH: CGFloat = (18.0/208.0)
        let chuteOffY: CGFloat = 1.375 * chuteH

        for i in 0..<2 {
            let p = planes[i]
            let boxes = debugPlaneBoxes[i]

            // Plane hitbox (hidden when dead with no pilot)
            let planeBox = boxes[0]
            if !p.isDead || p.hasJumped {
                let px = CGFloat(p.x)
                let py = CGFloat(p.y)
                let sx = (px - planHW) * size.width
                let sy = (1.0 - (py + planHH)) * size.height
                planeBox.path = CGPath(rect: CGRect(x: sx, y: sy,
                    width: planHW*2*size.width, height: planHH*2*size.height), transform: nil)
                planeBox.isHidden = p.isDead
            } else {
                planeBox.isHidden = true
            }

            // Pilot hitbox
            let pilotBox = boxes[1]
            let chuteBox = boxes[2]
            if p.hasJumped && !p.pilotIsDead {
                let pilx = CGFloat(p.pilotX)
                let pily = CGFloat(p.pilotY)
                let ps = CGRect(
                    x: (pilx - pilHW) * size.width,
                    y: (1.0 - (pily + pilHH)) * size.height,
                    width: pilHW*2*size.width, height: pilHH*2*size.height)
                pilotBox.path = CGPath(rect: ps, transform: nil)
                pilotBox.isHidden = false

                // Chute hitbox: top-left = (x - chuteW/2, y - chuteOffY), size = chuteW×chuteH
                if p.pilotChuteOpen {
                    let cs = CGRect(
                        x: (pilx - chuteW/2) * size.width,
                        y: (1.0 - (pily - chuteOffY + chuteH)) * size.height,
                        width: chuteW * size.width, height: chuteH * size.height)
                    chuteBox.path = CGPath(rect: cs, transform: nil)
                    chuteBox.isHidden = false
                } else {
                    chuteBox.isHidden = true
                }
            } else {
                pilotBox.isHidden = true
                chuteBox.isHidden = true
            }
        }
    }

    // ── Scene construction ─────────────────────────────────────────────────

    private func buildStaticScene() {
        let bgTexture = SKTexture(imageNamed: "backround_\(bgIndex)")
        bgNode = SKSpriteNode(texture: bgTexture)
        bgNode.size     = size
        bgNode.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        bgNode.zPosition = -10
        addChild(bgNode)

        // Position barn so its roof aligns with C++ barn::planeCollisionY (the actual collision top)
        let barnRoofWorldY: CGFloat = 163.904 / 208.0
        let bw = size.width  * barnSizeX
        let bh = size.height * barnSizeY
        let barnSprite = SKSpriteNode(texture: SKTexture(imageNamed: "barn"))
        barnSprite.size     = CGSize(width: bw, height: bh)
        barnSprite.position = CGPoint(
            x: size.width * 0.5,
            y: (1.0 - barnRoofWorldY) * size.height - bh * 0.5)
        barnSprite.zPosition = 5
        addChild(barnSprite)
        barnNode = barnSprite
    }

    private func buildDynamicNodes() {
        for i in 0..<2 {
            // Load texture explicitly so we can read its size reliably before
            // setting the node size (SKSpriteNode(imageNamed:) can report 0×0
            // on the first frame when the texture is not yet in the catalog).
            let texture = SKTexture(imageNamed: planeImageNames[i])
            let texSize = texture.size()
            let fixedHeight: CGFloat = 24
            let aspect: CGFloat = texSize.height > 0 ? texSize.width / texSize.height : 1.0
            let sprite = SKSpriteNode(texture: texture)
            sprite.size      = CGSize(width: fixedHeight * aspect, height: fixedHeight)
            // Tint fallback: if texture missing the sprite shows as a solid color
            sprite.color          = planeColors[i]
            sprite.colorBlendFactor = texSize.width > 0 ? 0.0 : 1.0
            sprite.zPosition = 10
            addChild(sprite)
            planeNodes[i] = sprite

            // Pilot sprite (starts with fall frame 0; texture/size updated each frame)
            let pilot = SKSpriteNode(texture: pilotFallTextures[i][0])
            pilot.size       = CGSize(width: 15, height: 22)
            pilot.zPosition  = 12
            pilot.isHidden   = true
            addChild(pilot)
            pilotNodes[i] = pilot

            // Chute — bottom-center anchored so it hangs above the pilot
            let chute = SKSpriteNode(texture: SKTexture(imageNamed: "pilot_parachute"))
            chute.size        = CGSize(width: 44, height: 38)   // 638:703 ≈ 0.91 aspect
            chute.anchorPoint = CGPoint(x: 0.5, y: 0)          // bottom-center
            chute.zPosition   = 11                              // behind pilot (12)
            chute.isHidden    = true
            addChild(chute)
            chuteNodes[i] = chute

            // Score label
            let score = SKLabelNode(fontNamed: "Helvetica-Bold")
            score.fontSize     = 16
            score.fontColor    = planeColors[i]
            score.zPosition    = 20
            score.text         = "Score: 0"
            score.horizontalAlignmentMode = (i == 0) ? .left : .right
            score.verticalAlignmentMode   = .top
            score.position = CGPoint(
                x: i == 0 ? 10 : size.width - 10,
                y: size.height - 10)
            addChild(score)
            scoreLabels[i] = score

            // HP bar background
            let barBg = SKShapeNode(rectOf: CGSize(width: 60, height: 8), cornerRadius: 2)
            barBg.fillColor   = SKColor(white: 0.2, alpha: 0.8)
            barBg.strokeColor = .clear
            barBg.zPosition   = 20
            barBg.position = CGPoint(
                x: i == 0 ? 40 : size.width - 40,
                y: size.height - 34)
            addChild(barBg)
            hpBarBg[i] = barBg

            // HP bar fill
            let barFg = SKShapeNode(rectOf: CGSize(width: 60, height: 8), cornerRadius: 2)
            barFg.fillColor   = SKColor(red: 0.31, green: 0.86, blue: 0.31, alpha: 1)
            barFg.strokeColor = .clear
            barFg.zPosition   = 21
            barFg.position    = barBg.position
            addChild(barFg)
            hpBarFg[i] = barFg
        }

        // Offline/online mode badge
        modeLabel = SKLabelNode(fontNamed: "Helvetica")
        modeLabel.fontSize   = 13
        modeLabel.fontColor  = SKColor(red: 0.90, green: 0.75, blue: 0.30, alpha: 1)
        modeLabel.zPosition  = 20
        modeLabel.text       = bridge.isOffline ? "OFFLINE vs BOT" : "ONLINE"
        modeLabel.horizontalAlignmentMode = .center
        modeLabel.position = CGPoint(x: size.width * 0.5, y: size.height - 18)
        addChild(modeLabel)

        // Win overlay label (hidden by default)
        winLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
        winLabel.fontSize  = 40
        winLabel.fontColor = .white
        winLabel.zPosition = 30
        winLabel.isHidden  = true
        winLabel.horizontalAlignmentMode = .center
        winLabel.verticalAlignmentMode   = .center
        winLabel.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        addChild(winLabel)

        // Zeppelin with score display
        let zeppelinTexture = SKTexture(imageNamed: "zeppilin")
        zeppelinTexture.filteringMode = .linear
        zeppilinNode = SKSpriteNode(texture: zeppelinTexture)
        zeppilinNode.size = CGSize(width: 80, height: 44)
        zeppilinNode.zPosition = 15
        zeppilinY = 0.2
        zeppilinNode.position = CGPoint(x: size.width * 0.5, y: size.height * (1.0 - zeppilinY))
        addChild(zeppilinNode)

        // Score labels on zeppelin
        for i in 0..<2 {
            let scoreLabel = SKLabelNode(fontNamed: "AmericanTypewriter")
            scoreLabel.fontSize = 16
            scoreLabel.fontColor = planeColors[i]
            scoreLabel.zPosition = 16
            scoreLabel.text = "0"
            scoreLabel.horizontalAlignmentMode = (i == 0) ? .right : .left
            scoreLabel.position = CGPoint(
                x: size.width * 0.5 + (i == 0 ? -6 : 10),
                y: size.height * (1.0 - zeppilinY) - 2
            )
            addChild(scoreLabel)
            zeppilinScoreLabels[i] = scoreLabel
        }
    }

    // ── Clouds ─────────────────────────────────────────────────────────────

    private func startCloudSpawner() {
        // Pre-populate with a few clouds so screen isn't empty at start
        for _ in 0..<4 {
            spawnCloud(preplace: true)
        }
        // Then keep spawning new ones at random intervals
        scheduleNextCloud()
    }

    private func scheduleNextCloud() {
        let delay = TimeInterval.random(in: 3.0...7.0)
        run(.sequence([.wait(forDuration: delay), .run { [weak self] in
            self?.spawnCloud(preplace: false)
            self?.scheduleNextCloud()
        }]))
    }

    private func spawnCloud(preplace: Bool) {
        let texture = cloudTextures.randomElement()!
        let node    = SKSpriteNode(texture: texture)

        // Random size: width 80–160pt, preserve aspect ratio
        let w = CGFloat.random(in: 80...160)
        let aspect = texture.size().width / max(texture.size().height, 1)
        node.size      = CGSize(width: w, height: w / aspect)
        node.zPosition = 1   // in front of background, behind game elements
        node.alpha     = Bool.random() ? 0.5 : 1.0

        // Semi-transparent clouds may randomly float in front of everything (but below HUD)
        if node.alpha == 0.5 && Bool.random() {
            node.zPosition = 18
        }

        // Y: upper 70% of screen (sky area)
        let yMin = size.height * 0.30
        let yMax = size.height * 0.90
        let y    = CGFloat.random(in: yMin...yMax)

        // Direction: randomly drift left or right
        let goingLeft  = Bool.random()
        let speed      = CGFloat.random(in: 20...50)   // pts/sec
        let startX: CGFloat
        let endX:   CGFloat

        if preplace {
            // Scatter across the full width at start
            startX = CGFloat.random(in: 0...size.width)
            endX   = goingLeft ? -node.size.width : size.width + node.size.width
        } else {
            // Enter from off-screen edge
            startX = goingLeft ? size.width + node.size.width : -node.size.width
            endX   = goingLeft ? -node.size.width             : size.width + node.size.width
        }

        node.position = CGPoint(x: startX, y: y)
        addChild(node)

        let distance = abs(endX - startX)
        let duration = TimeInterval(distance / speed)
        node.run(.sequence([
            .moveTo(x: endX, duration: duration),
            .removeFromParent()
        ]))
    }

    // ── Update ─────────────────────────────────────────────────────────────

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdateTime == 0 ? 0 : currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        guard let state = bridge.currentState(),
              let planes  = state.planes,
              let bullets = state.bullets,
              planes.count == 2
        else { return }

        updatePlanes(planes, dt: dt)
        updateSparks(dt: dt)
        updateBullets(bullets)
        updateZeppelin(dt: dt)
        updateHUD(planes: planes, state: state)
        updateDebugOverlay(planes)
    }

    // ── Planes & pilots ────────────────────────────────────────────────────

    private func updatePlanes(_ planes: [PlaneState], dt: TimeInterval) {
        for i in 0..<2 {
            let p = planes[i]

            if p.isDead {
                // Trigger explosion once on the alive → dead transition
                // (covers both direct death and abandoned-plane crash after pilot ejects)
                if !prevIsDead[i] {
                    let deathPos = planeNodes[i].position
                    spawnExplosion(at: deathPos)
                    spawnSparks(worldX: lastWorldX[i], worldY: lastWorldY[i],
                                dir: lastPlaneDir[i], speed: lastPlaneSpeed[i])
                    AudioManager.shared.playSound("explosion")
                }
                planeNodes[i].isHidden = true
                smokeTimer[i] = 0
                fireTimer[i]  = 0
                prevFireFrame[i] = -1
                prevIsDead[i] = true
                // Reset animation so it restarts from idle after respawn
                if i == 0 && greenIsAnimating {
                    planeNodes[0].removeAction(forKey: "fly")
                    planeNodes[0].texture = greenIdleTexture
                    greenIsAnimating = false
                } else if i == 1 && redIsAnimating {
                    planeNodes[1].removeAction(forKey: "fly")
                    planeNodes[1].texture = redIdleTexture
                    redIsAnimating = false
                }
            } else if !p.isDead {
                // Track HP changes for hit_plane sound
                if p.hp < prevHP[i] && p.hp > 0 {
                    AudioManager.shared.playSound("hit_plane")
                }
                prevHP[i] = Int(p.hp)
                prevIsDead[i] = false
                planeNodes[i].isHidden = false

                // Cache for spark spawning (position resets to 0 in C++ on death)
                lastWorldX[i]     = p.x
                lastWorldY[i]     = p.y
                lastPlaneDir[i]   = p.dir
                lastPlaneSpeed[i] = p.speed

                let pos = worldToScreen(x: CGFloat(p.x), y: CGFloat(p.y))
                planeNodes[i].position = pos

                // Convert game direction (0=up, clockwise) to SpriteKit angle.
                // A sprite naturally facing right needs zRotation = π/2 - rad so that:
                //   dir=90  (right) → zRot = 0  (facing right) ✓
                //   dir=0   (up)    → zRot = π/2 (facing up)   ✓
                // planeBaseAngles[i] offsets red (left-facing) sprite by +π.
                let rad = CGFloat(p.dir) * .pi / 180.0
                planeNodes[i].zRotation = .pi / 2.0 - rad + planeBaseAngles[i]

                // Dim sprite when under spawn protection
                planeNodes[i].alpha = p.protectionRemaining > 0
                    ? CGFloat(0.5 + 0.5 * sin(Double(p.protectionRemaining) * 10))
                    : 1.0

                // Biplane animation: animate while flying, idle frame on ground
                if i == 0 {
                    let shouldAnimate = !p.isOnGround
                    if shouldAnimate && !greenIsAnimating {
                        planeNodes[0].run(greenFlyAction, withKey: "fly")
                        greenIsAnimating = true
                    } else if !shouldAnimate && greenIsAnimating {
                        planeNodes[0].removeAction(forKey: "fly")
                        planeNodes[0].texture = greenIdleTexture
                        greenIsAnimating = false
                    }
                } else if i == 1 {
                    let shouldAnimate = !p.isOnGround
                    if shouldAnimate && !redIsAnimating {
                        planeNodes[1].run(redFlyAction, withKey: "fly")
                        redIsAnimating = true
                    } else if !shouldAnimate && redIsAnimating {
                        planeNodes[1].removeAction(forKey: "fly")
                        planeNodes[1].texture = redIdleTexture
                        redIsAnimating = false
                    }
                }

                // ── Smoke (hp == 1): spawn a puff every 0.075s, independent of anim
                if p.hp <= 1 && !p.isDead {
                    smokeTimer[i] += dt
                    if smokeTimer[i] >= 0.06 {
                        smokeTimer[i] = 0
                        spawnTrace(textures: smokeTextures, at: pos, size: 20, zPos: 11,
                                   timePerFrame: 0.15, behind: nil)
                    }
                } else {
                    smokeTimer[i] = 0
                }

                // ── Fire (hp == 0): spawn a flare every 0.075s
                let curFire = Int(p.fireFrame)
                let fireActive = (p.hp == 0)
                let fireStarted = fireActive && (prevFireFrame[i] < 0 || (prevFireFrame[i] == 2 && curFire == 0))
                if fireStarted {
                    spawnTrace(textures: fireTextures, at: pos, size: 24, zPos: 12,
                               timePerFrame: 0.075, behind: nil)
                }
                prevFireFrame[i] = fireActive ? curFire : -1
            }

            // Pilot
            if p.hasJumped {
                // Track if pilot just jumped
                if !prevHasJumped[i] {
                    prevHasJumped[i] = true
                }
                let ppos = worldToScreen(x: CGFloat(p.pilotX), y: CGFloat(p.pilotY))
                
                if p.pilotIsDead {
                    if !prevPilotIsDead[i] {
                        AudioManager.shared.playSound("pilot_death")
                    }
                    
                    // Show angel animation
                    let angelIdx = Int(max(0, p.pilotAngelFrame)) % 4
                    pilotNodes[i].texture = pilotAngelTextures[angelIdx]
                    pilotNodes[i].size = CGSize(width: 20, height: 30)
                    pilotNodes[i].xScale = 1
                    pilotNodes[i].position = ppos
                    pilotNodes[i].isHidden = false
                    chuteNodes[i].isHidden = true
                    
                    prevPilotIsDead[i] = true
                } else {
                    pilotNodes[i].position = ppos

                    let isRunning = p.pilotIsRunning
                    // Use C++ frames directly — they freeze when idle, so no Swift timer needed
                    let runIdx  = Int(p.pilotRunFrame)  % 4
                    let fallIdx = Int(max(0, p.pilotFallFrame)) % 3
                    
                    // Track running transition for hit_ground sound
                    if isRunning && !prevIsRunning[i] {
                        AudioManager.shared.playSound("hit_ground")
                    }
                    prevIsRunning[i] = isRunning

                    if isRunning && p.pilotIsMoving {
                        pilotNodes[i].texture = pilotRunTextures[i][runIdx]
                        pilotNodes[i].size    = CGSize(width: 19.5, height: 24.2)
                        // dir=90 means moving left in practice; flip accordingly
                        let movingRight = Int(p.pilotDir) >= 180
                        pilotFacingRight[i]  = movingRight
                        pilotNodes[i].xScale = movingRight ? 1 : -1
                        // Raise run sprite so feet align with ground
                        pilotNodes[i].position = CGPoint(x: ppos.x, y: ppos.y)
                    } else if Float(p.pilotY) > 0.85 {
                        // On ground, idle — preserve aspect ratio with size adjustments
                        let tex = pilotIdleTextures[i]
                        let aspect = tex.size().width / tex.size().height
                        pilotNodes[i].texture = tex
                        pilotNodes[i].size    = CGSize(width: 26 * aspect * 1.10 * 0.85 * 1.3, height: 26 * 0.85 * 1.1)
                        pilotNodes[i].xScale  = pilotFacingRight[i] ? 1 : -1
                        pilotNodes[i].position = CGPoint(x: ppos.x, y: ppos.y)
                    } else {
                        // Falling (free-fall or chute) — pilot hangs below chute
                        pilotNodes[i].texture = pilotFallTextures[i][fallIdx]
                        pilotNodes[i].size    = CGSize(width: 15.6, height: 24.2)
                        pilotNodes[i].xScale  = 1
                        pilotNodes[i].position = ppos
                        
                        // Track falling for fall_loop sound
                        let isFalling = Float(p.pilotY) <= 0.85 && !p.pilotChuteOpen
                        if isFalling && !prevPilotIsFalling[i] {
                            AudioManager.shared.playSound("fall_loop")
                        }
                        prevPilotIsFalling[i] = isFalling
                    }

                    // Chute — anchor is bottom-center; attach to TOP of pilot sprite
                    if p.pilotChuteOpen {
                        // Track chute opening for chute_loop sound
                        if !prevChuteOpen[i] {
                            AudioManager.shared.playSound("chute_loop")
                        }
                        prevChuteOpen[i] = true
                        
                        // Track chute breaking for hit_chute sound
                        if p.pilotChuteBroken && !prevChuteBroken[i] {
                            AudioManager.shared.playSound("hit_chute")
                        }
                        prevChuteBroken[i] = p.pilotChuteBroken
                        
                        chuteNodes[i].isHidden = false
                        chuteNodes[i].position = CGPoint(x: ppos.x, y: ppos.y + 11)
                        chuteNodes[i].color          = p.pilotChuteBroken ? SKColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1) : .white
                        chuteNodes[i].colorBlendFactor = p.pilotChuteBroken ? 0.5 : 0
                    } else {
                        prevChuteOpen[i] = false
                        prevChuteBroken[i] = false
                        chuteNodes[i].isHidden = true
                    }
                    
                    pilotNodes[i].isHidden = false
                    
                    prevPilotIsDead[i] = false
                }
            } else {
                // Pilot not jumped - track rescue/pickup
                if prevHasJumped[i] {
                    AudioManager.shared.playSound("pilot_rescue")
                }
                prevHasJumped[i] = false
                prevChuteOpen[i] = false
                prevChuteBroken[i] = false
                prevIsRunning[i] = false
                prevPilotIsFalling[i] = false
                chuteLoopPlaying[i] = false
                fallLoopPlaying[i] = false
                pilotNodes[i].isHidden = true
                chuteNodes[i].isHidden = true
                pilotAnimTimer[i] = 0
                pilotAnimFrame[i] = 0
            }
        }
    }
    
    private func updateZeppelin(dt: TimeInterval) {
        guard dt > 0 else { return }

        // ── Random direction change timer ───────────────────────────────────
        zeppilinDirChangeTimer += dt
        if zeppilinDirChangeTimer >= zeppilinNextDirChange {
            zeppilinDirChangeTimer = 0
            zeppilinNextDirChange  = TimeInterval.random(in: 2.0...5.0)

            // Pick a new random velocity, keeping current rough direction
            // but adding some variance so it doesn't feel too mechanical
            let speedX = CGFloat.random(in: 0.006...0.020)
            let speedY = CGFloat.random(in: 0.003...0.012)
            zeppilinVX = Bool.random() ? speedX : -speedX
            zeppilinVY = Bool.random() ? speedY : -speedY
        }

        // ── Edge avoidance — flip axis when approaching boundaries ─────────
        let marginX: CGFloat = 0.15   // world-space margin from left/right
        let minY:    CGFloat = 0.05   // world-space top boundary
        let maxY:    CGFloat = 0.45   // world-space bottom boundary (keep above barn/pilots)

        if zeppilinX < marginX        { zeppilinVX =  abs(zeppilinVX) }   // too far left  → go right
        if zeppilinX > 1.0 - marginX  { zeppilinVX = -abs(zeppilinVX) }   // too far right → go left
        if zeppilinY < minY           { zeppilinVY =  abs(zeppilinVY) }   // too high      → descend
        if zeppilinY > maxY           { zeppilinVY = -abs(zeppilinVY) }   // too low       → ascend

        // ── Integrate position ──────────────────────────────────────────────
        zeppilinX += zeppilinVX * CGFloat(dt)
        zeppilinY += zeppilinVY * CGFloat(dt)

        // Clamp to safe bounds so a large dt spike can't escape
        zeppilinX = zeppilinX.clamped(to: marginX...(1.0 - marginX))
        zeppilinY = zeppilinY.clamped(to: minY...maxY)

        // ── Update node & score label positions ─────────────────────────────
        let screenPos = worldToScreen(x: zeppilinX, y: zeppilinY)
        zeppilinNode.position = screenPos

        // Score labels sit left/right of the gondola centre
        for i in 0..<2 {
            zeppilinScoreLabels[i].position = CGPoint(
                x: screenPos.x + (i == 0 ? -6 : 10),
                y: screenPos.y - 2
            )
        }
    }

    // ── Explosion spawner ───────────────────────────────────────────────────
    // Plays the 8-frame explosion once at a fixed position then removes itself.
    private func spawnExplosion(at pos: CGPoint) {
        let node = SKSpriteNode(texture: explodeTextures[0])
        node.size      = CGSize(width: 72, height: 72)
        node.position  = pos
        node.zPosition = 20  // above everything
        addChild(node)
        AudioManager.shared.playSound("explosion")
        node.run(.sequence([
            .group([
                .animate(with: explodeTextures, timePerFrame: 0.06, resize: false, restore: false),
                .sequence([
                    .wait(forDuration: 0.24),          // visible for first ~4 frames
                    .fadeOut(withDuration: 0.24)       // fade during last 4 frames
                ])
            ]),
            .removeFromParent()
        ]))
    }

    // ── Explosion sparks ────────────────────────────────────────────────────
    // Constants mirrored from biplanes-revival constants.hpp / explosion::spark
    private enum SparkConst {
        static let count        = 25
        static let colorTime: Float = 0.035
        static let gravity: Float   = 0.75
        static let speedMin: Float  = 0.4
        static let speedMax: Float  = 0.6
        static let speedMask: Float = Float(count) / 1.0123456789
        static let dirRange: Float  = 75.0              // degrees
        static let dirOffset: Float = dirRange * 0.2    // 15°
        static let bounceSpeed: Float = 0.1
        static let maxBounces   = 2
        // World-coord collision boundaries (y: 0=top, 1=bottom)
        static let groundY: Float     = 182.0 / 208.0   // ≈ 0.875
        static let barnRoofY: Float   = 168.48 / 208.0  // ≈ 0.810
        static let barnLeftX: Float   = 0.5 - (36.0/256.0) * 0.475
        static let barnRightX: Float  = barnLeftX + (36.0/256.0) * 0.95
    }

    private func spawnSparks(worldX: Float, worldY: Float, dir: Float, speed: Float) {
        let n = SparkConst.count
        let dirFactor    = sin(dir * .pi / 180.0)
        let speedFactor  = speed  // relative; original divides by maxSpeedBoosted ≈ 0.4
        let dirOffsetVal = SparkConst.dirOffset * dirFactor * (speedFactor / 0.4)

        for i in 0..<n {
            let t = Float(i) / Float(n)
            let sparkDir = dirOffsetVal + SparkConst.dirRange * (-0.5 + t + 0.45 * dirFactor / Float(n))
            let speedVar = (SparkConst.speedMask).truncatingRemainder(dividingBy: t + 0.001)
            let sparkSpeed = SparkConst.speedMin + speedVar * (SparkConst.speedMax - SparkConst.speedMin)
            let rad = sparkDir * Float.pi / 180.0
            let vx  = sin(rad) * sparkSpeed
            let vy  = -cos(rad) * sparkSpeed  // negative: upward in our SDL-style y

            let node = SKShapeNode(rectOf: CGSize(width: 2, height: 2))
            node.fillColor   = GameScene.sparkColors[0]
            node.strokeColor = .clear
            node.zPosition   = 19
            addChild(node)

            activeSparks.append(SparkState(
                x: worldX, y: worldY, vx: vx, vy: vy,
                bounces: 0, colorTimer: 0, colorIndex: 0, node: node
            ))
        }
    }

    private func updateSparks(dt: TimeInterval) {
        let fdt = Float(dt)
        var i = 0
        while i < activeSparks.count {
            var s = activeSparks[i]

            // Color cycling
            s.colorTimer += fdt
            if s.colorTimer >= SparkConst.colorTime {
                s.colorTimer -= SparkConst.colorTime
                s.colorIndex = (s.colorIndex + 1) % GameScene.sparkColors.count
                s.node.fillColor = GameScene.sparkColors[s.colorIndex]
            }

            // Physics
            s.vx -= s.vx * fdt          // X drag
            s.vy += SparkConst.gravity * fdt  // gravity (y increases downward)
            s.x  += s.vx * fdt
            s.y  += s.vy * fdt
            // Horizontal wrap
            s.x = (s.x.truncatingRemainder(dividingBy: 1.0) + 1.0).truncatingRemainder(dividingBy: 1.0)

            // Ground & barn collision (only while falling: vy > 0)
            if s.vy > 0 {
                if s.bounces >= SparkConst.maxBounces {
                    s.node.removeFromParent()
                    activeSparks.remove(at: i)
                    continue
                }

                let onBarnX = s.x >= SparkConst.barnLeftX && s.x <= SparkConst.barnRightX
                let hitBarn  = onBarnX && s.y >= SparkConst.barnRoofY
                let hitGround = !onBarnX && s.y >= SparkConst.groundY

                if hitBarn || hitGround {
                    s.y  = hitBarn ? SparkConst.barnRoofY : SparkConst.groundY
                    s.vy = -SparkConst.bounceSpeed
                    s.bounces += 1
                }
            }

            // Update screen position
            s.node.position = worldToScreen(x: CGFloat(s.x), y: CGFloat(s.y))
            activeSparks[i] = s
            i += 1
        }
    }

    // ── Smoke / fire trace spawner ──────────────────────────────────────────
    // Spawns a transient sprite at a fixed screen position. The puff plays its
    // animation once while fading out and scaling up, then removes itself.
    // `behind`: if provided, offsets the spawn point opposite to the plane's heading.
    private func spawnTrace(textures: [SKTexture], at pos: CGPoint,
                            size: CGFloat, zPos: CGFloat,
                            timePerFrame: TimeInterval, behind: CGFloat?) {
        let node = SKSpriteNode(texture: textures[0])
        node.size      = CGSize(width: size, height: size)
        node.zPosition = zPos
        node.alpha     = 0.85

        if let dir = behind {
            let rad = CGFloat(dir + 180) * .pi / 180.0
            node.position = CGPoint(
                x: pos.x + sin(rad) * size * 0.6,
                y: pos.y - cos(rad) * size * 0.6
            )
        } else {
            node.position = pos
        }

        addChild(node)

        let totalDuration = timePerFrame * Double(textures.count)
        node.run(.sequence([
            .group([
                .animate(with: textures, timePerFrame: timePerFrame, resize: false, restore: false),
                .fadeOut(withDuration: totalDuration),
                .scale(to: 1.6, duration: totalDuration)
            ]),
            .removeFromParent()
        ]))
    }

    // ── Bullets ────────────────────────────────────────────────────────────

    private func updateBullets(_ bullets: [BulletState]) {
        // Detect new bullets fired
        if bullets.count > prevBulletCount {
            AudioManager.shared.playSound("shoot")
        }
        prevBulletCount = bullets.count
        
        while bulletPool.count < bullets.count {
            let node = SKShapeNode(circleOfRadius: 3)
            node.fillColor   = SKColor(red: 1.0, green: 1.0, blue: 0.24, alpha: 1)
            node.strokeColor = .clear
            node.zPosition   = 9
            addChild(node)
            bulletPool.append(node)
        }

        for (idx, b) in bullets.enumerated() {
            bulletPool[idx].isHidden = false
            bulletPool[idx].position = worldToScreen(x: CGFloat(b.x), y: CGFloat(b.y))
        }
        for idx in bullets.count..<bulletPool.count {
            bulletPool[idx].isHidden = true
        }
    }

    // ── HUD ────────────────────────────────────────────────────────────────

    private func updateHUD(planes: [PlaneState], state: BiplanesBridgeState) {
        for i in 0..<2 {
            let p = planes[i]
            scoreLabels[i].text = "Score: \(p.score)"
            zeppilinScoreLabels[i].text = "\(p.score)"

            let fraction = CGFloat(max(0, p.hp)) / 3.0
            let fullWidth: CGFloat = 60
            let filled = fullWidth * fraction
            let bar = SKShapeNode(rectOf: CGSize(width: max(2, filled), height: 8), cornerRadius: 2)
            bar.fillColor   = fraction > 0.5
                ? SKColor(red: 0.31, green: 0.86, blue: 0.31, alpha: 1)
                : SKColor(red: 0.86, green: 0.55, blue: 0.20, alpha: 1)
            bar.strokeColor = .clear
            hpBarFg[i].path = bar.path
            hpBarFg[i].fillColor = bar.fillColor
        }

        if state.roundFinished {
            winLabel.isHidden = false
            
            if !prevRoundFinished {
                if state.winnerId == 0 || state.winnerId == 1 {
                    AudioManager.shared.playSound("victory")
                }
                
                // Play defeat sound if this player lost
                let playerId = bridge.playerId
                if state.winnerId != playerId && state.winnerId >= 0 {
                    AudioManager.shared.playSound("defeat")
                }
            }
            
            if state.winnerId == 0 {
                winLabel.text      = "🟢 Green Wins!"
                winLabel.fontColor = planeColors[0]
            } else if state.winnerId == 1 {
                winLabel.text      = "🔴 Red Wins!"
                winLabel.fontColor = planeColors[1]
            } else {
                winLabel.text      = "Draw"
                winLabel.fontColor = .white
            }
        } else {
            winLabel.isHidden = true
        }

        prevRoundFinished = state.roundFinished
    }

    // ── Coordinate helpers ─────────────────────────────────────────────────

    /// World space [0..1] (Y=0 at top) → SpriteKit points (Y=0 at bottom).
    private func worldToScreen(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(
            x: x * size.width,
            y: (1.0 - y) * size.height
        )
    }
}


extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
