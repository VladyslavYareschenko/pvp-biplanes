import SpriteKit

/// SpriteKit scene that renders the game state from BiplanesBridge each frame.
/// Uses simple geometric shapes — no sprite textures yet.
final class GameScene: SKScene {

    // ── Constants ──────────────────────────────────────────────────────────

    // Barn constants mirroring core/include/constants.hpp
    private let barnSizeX: CGFloat    = 0.08
    private let barnCollisionY: CGFloat = 0.87

    // ── Nodes ──────────────────────────────────────────────────────────────

    // Planes
    private var planeNodes  = [SKShapeNode(), SKShapeNode()]
    private var dirNodes    = [SKShapeNode(), SKShapeNode()]   // direction arrows

    // Pilots
    private var pilotNodes  = [SKShapeNode(), SKShapeNode()]
    private var chuteNodes  = [SKShapeNode(), SKShapeNode()]

    // Bullets — reused pool
    private var bulletPool  = [SKShapeNode]()
    private var bulletCount = 0

    // HUD
    private var scoreLabels    = [SKLabelNode(), SKLabelNode()]
    private var hpBarBg        = [SKShapeNode(), SKShapeNode()]
    private var hpBarFg        = [SKShapeNode(), SKShapeNode()]
    private var modeLabel      = SKLabelNode()
    private var winLabel       = SKLabelNode()

    // Static scene
    private var groundNode     = SKShapeNode()
    private var barnNode       = SKShapeNode()

    private let bridge: BiplanesBridge

    // Plane colours: blue, red
    private let planeColors: [SKColor] = [
        SKColor(red: 0.31, green: 0.47, blue: 0.86, alpha: 1),
        SKColor(red: 0.86, green: 0.31, blue: 0.31, alpha: 1),
    ]

    // ── Init ───────────────────────────────────────────────────────────────

    init(bridge: BiplanesBridge, size: CGSize) {
        self.bridge = bridge
        super.init(size: size)
        backgroundColor = SKColor(red: 0.12, green: 0.12, blue: 0.20, alpha: 1)
        scaleMode = .resizeFill
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        buildStaticScene()
        buildDynamicNodes()
    }

    // ── Scene construction ─────────────────────────────────────────────────

    private func buildStaticScene() {
        // Ground
        let groundRect = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.03)
        groundNode = SKShapeNode(rect: groundRect)
        groundNode.fillColor   = SKColor(red: 0.31, green: 0.51, blue: 0.24, alpha: 1)
        groundNode.strokeColor = .clear
        groundNode.position    = .zero
        addChild(groundNode)

        // Barn
        let bw = size.width * barnSizeX
        let bh = size.height * 0.06
        let bx = size.width * 0.5 - bw * 0.5
        let by = size.height * (1.0 - barnCollisionY) - bh * 0.5
        barnNode = SKShapeNode(rect: CGRect(x: bx, y: by, width: bw, height: bh))
        barnNode.fillColor   = SKColor(red: 0.55, green: 0.35, blue: 0.20, alpha: 1)
        barnNode.strokeColor = SKColor(red: 0.40, green: 0.25, blue: 0.12, alpha: 1)
        barnNode.lineWidth   = 2
        addChild(barnNode)
    }

    private func buildDynamicNodes() {
        for i in 0..<2 {
            // Plane body
            let plane = SKShapeNode(rectOf: CGSize(width: 28, height: 12), cornerRadius: 3)
            plane.fillColor   = planeColors[i]
            plane.strokeColor = .clear
            plane.zPosition   = 10
            addChild(plane)
            planeNodes[i] = plane

            // Direction indicator
            let dir = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: 16))
            dir.path        = path
            dir.strokeColor = .yellow
            dir.lineWidth   = 2
            dir.zPosition   = 11
            addChild(dir)
            dirNodes[i] = dir

            // Pilot
            let pilot = SKShapeNode(rectOf: CGSize(width: 8, height: 8), cornerRadius: 2)
            pilot.fillColor   = SKColor(red: 1.0, green: 0.71, blue: 0.39, alpha: 1)
            pilot.strokeColor = .clear
            pilot.zPosition   = 12
            pilot.isHidden    = true
            addChild(pilot)
            pilotNodes[i] = pilot

            // Chute
            let chute = SKShapeNode(rectOf: CGSize(width: 22, height: 14), cornerRadius: 4)
            chute.fillColor   = SKColor(white: 0.85, alpha: 0.85)
            chute.strokeColor = .clear
            chute.zPosition   = 11
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
    }

    // ── Update ─────────────────────────────────────────────────────────────

    override func update(_ currentTime: TimeInterval) {
        let state = bridge.currentState()
        guard let planes  = state.planes  as? [PlaneState],
              let bullets = state.bullets as? [BulletState],
              planes.count == 2
        else { return }

        updatePlanes(planes)
        updateBullets(bullets)
        updateHUD(planes: planes, state: state)
    }

    // ── Planes & pilots ────────────────────────────────────────────────────

    private func updatePlanes(_ planes: [PlaneState]) {
        for i in 0..<2 {
            let p = planes[i]

            if p.isDead && !p.hasJumped {
                planeNodes[i].isHidden = true
                dirNodes[i].isHidden   = true
            } else if !p.isDead {
                planeNodes[i].isHidden = false
                dirNodes[i].isHidden   = false

                let pos = worldToScreen(x: CGFloat(p.x), y: CGFloat(p.y))
                planeNodes[i].position = pos
                dirNodes[i].position   = pos

                let rad = CGFloat(p.dir) * .pi / 180.0
                planeNodes[i].zRotation = -rad
                dirNodes[i].zRotation   = rad    // arrow points in flight dir
            }

            // Pilot
            if p.hasJumped {
                let ppos = worldToScreen(x: CGFloat(p.pilotX), y: CGFloat(p.pilotY))
                pilotNodes[i].isHidden  = p.pilotIsDead
                pilotNodes[i].position  = ppos

                // Chute
                if p.pilotChuteOpen && !p.pilotIsDead {
                    chuteNodes[i].isHidden  = false
                    chuteNodes[i].position  = CGPoint(x: ppos.x, y: ppos.y + 18)
                    chuteNodes[i].fillColor = p.pilotChuteBroken
                        ? SKColor(red: 0.78, green: 0.24, blue: 0.24, alpha: 0.85)
                        : SKColor(white: 0.85, alpha: 0.85)
                } else {
                    chuteNodes[i].isHidden = true
                }
            } else {
                pilotNodes[i].isHidden = true
                chuteNodes[i].isHidden = true
            }
        }
    }

    // ── Bullets ────────────────────────────────────────────────────────────

    private func updateBullets(_ bullets: [BulletState]) {
        // Grow pool if needed
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
        // Hide unused pool nodes
        for idx in bullets.count..<bulletPool.count {
            bulletPool[idx].isHidden = true
        }
    }

    // ── HUD ────────────────────────────────────────────────────────────────

    private func updateHUD(planes: [PlaneState], state: BiplanesBridgeState) {
        for i in 0..<2 {
            let p = planes[i]
            scoreLabels[i].text = "Score: \(p.score)"

            // HP bar: max hp = 3
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

        // Win overlay
        if state.roundFinished {
            winLabel.isHidden = false
            if state.winnerId == 0 {
                winLabel.text      = "🔵 Blue Wins!"
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
