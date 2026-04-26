import UIKit

/// Transparent overlay that provides a floating virtual joystick on the left
/// and two action buttons (Shoot / Eject) on the right.
///
/// Joystick — appears where the thumb first touches in the left half of the screen.
///   X-axis  → pitch  (left = turn left, right = turn right)
///   Y-axis  → throttle (pull up = increase, push down = decrease / idle)
///
/// Action buttons are fixed in the lower-right corner.
final class TouchControlsView: UIView {

    private let bridge: BiplanesBridge

    private let baseRadius:   CGFloat = 68
    private let knobRadius:   CGFloat = 30
    private let deadFraction: CGFloat = 0.18

    private let stickBase = UIView()
    private let stickKnob = UIView()

    private var stickCenter:      CGPoint = .zero
    private var activeStickTouch: UITouch?

    private let shootBtn = TouchControlsView.makeRoundBtn(size: 72,  symbol: "🔫")
    private let jumpBtn  = TouchControlsView.makeRoundBtn(size: 56,  symbol: "⏏")


    init(bridge: BiplanesBridge) {
        self.bridge = bridge
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        setupJoystickVisuals()
        setupButtons()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupJoystickVisuals() {
        stickBase.layer.cornerRadius = baseRadius
        stickBase.layer.borderWidth  = 2.5
        stickBase.layer.borderColor  = UIColor.white.withAlphaComponent(0.35).cgColor
        stickBase.backgroundColor    = UIColor.white.withAlphaComponent(0.08)
        stickBase.isUserInteractionEnabled = false
        stickBase.isHidden = true
        addSubview(stickBase)

        stickKnob.layer.cornerRadius = knobRadius
        stickKnob.backgroundColor    = UIColor.white.withAlphaComponent(0.55)
        stickKnob.isUserInteractionEnabled = false
        stickKnob.isHidden = true
        addSubview(stickKnob)
    }

    private func setupButtons() {
        addSubview(shootBtn)
        addSubview(jumpBtn)

        shootBtn.addTarget(self, action: #selector(shootDown),
                           for: [.touchDown, .touchDragEnter])
        shootBtn.addTarget(self, action: #selector(shootUp),
                           for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])

        jumpBtn.addTarget(self, action: #selector(jumpDown),
                          for: [.touchDown, .touchDragEnter])
        jumpBtn.addTarget(self, action: #selector(jumpUp),
                          for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let pad: CGFloat       = 36
        let shootSide: CGFloat = 72
        let jumpSide: CGFloat  = 56
        let gap: CGFloat       = 20

        shootBtn.frame = CGRect(
            x: bounds.width  - shootSide - pad,
            y: bounds.height - shootSide - pad,
            width: shootSide, height: shootSide)
        shootBtn.layer.cornerRadius = shootSide / 2

        jumpBtn.frame = CGRect(
            x: shootBtn.frame.minX - jumpSide - gap,
            y: shootBtn.frame.midY - jumpSide / 2,
            width: jumpSide, height: jumpSide)
        jumpBtn.layer.cornerRadius = jumpSide / 2
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard activeStickTouch == nil else { continue }
            let loc = touch.location(in: self)
            guard loc.x < bounds.width * 0.5 else { continue }
            activeStickTouch = touch
            stickCenter = loc
            showStick(at: loc)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeStickTouch, touches.contains(active) else { return }
        updateJoystick(loc: active.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseStickIfNeeded(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseStickIfNeeded(touches)
    }

    private func showStick(at center: CGPoint) {
        let d = baseRadius * 2
        stickBase.frame = CGRect(x: center.x - baseRadius, y: center.y - baseRadius,
                                 width: d, height: d)
        stickKnob.frame = CGRect(x: center.x - knobRadius, y: center.y - knobRadius,
                                 width: knobRadius * 2, height: knobRadius * 2)
        stickBase.isHidden = false
        stickKnob.isHidden = false
    }

    private func updateJoystick(loc: CGPoint) {
        let dx   = loc.x - stickCenter.x
        let dy   = loc.y - stickCenter.y
        let dist = hypot(dx, dy)
        let clamped = min(dist, baseRadius)
        let angle   = atan2(dy, dx)
        stickKnob.center = CGPoint(
            x: stickCenter.x + cos(angle) * clamped,
            y: stickCenter.y + sin(angle) * clamped)

        let magnitude = Float(clamped / baseRadius)

        // Game convention: 0° = up, clockwise positive.
        // atan2(dx, -dy) maps screen drag to that convention.
        let gameAngle = Float(atan2(dx, -dy) * 180.0 / .pi)
        bridge.setJoystick(gameAngle, magnitude: magnitude, active: true)
    }

    private func releaseStickIfNeeded(_ touches: Set<UITouch>) {
        guard let active = activeStickTouch, touches.contains(active) else { return }
        activeStickTouch = nil
        stickBase.isHidden = true
        stickKnob.isHidden = true
        bridge.setJoystick(0, magnitude: 0, active: false)
    }

    @objc private func shootDown() {
        bridge.setShoot(true)
        UIView.animate(withDuration: 0.05) {
            self.shootBtn.backgroundColor = UIColor.white.withAlphaComponent(0.50)
        }
    }

    @objc private func shootUp() {
        bridge.setShoot(false)
        UIView.animate(withDuration: 0.10) {
            self.shootBtn.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        }
    }

    @objc private func jumpDown() {
        bridge.setJump(true)
        UIView.animate(withDuration: 0.05) {
            self.jumpBtn.backgroundColor = UIColor.white.withAlphaComponent(0.50)
        }
    }

    @objc private func jumpUp() {
        bridge.setJump(false)
        UIView.animate(withDuration: 0.10) {
            self.jumpBtn.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        }
    }

    private static func makeRoundBtn(size: CGFloat, symbol: String) -> UIButton {
        let b = UIButton(type: .custom)
        b.setTitle(symbol, for: .normal)
        b.titleLabel?.font    = .systemFont(ofSize: size * 0.40)
        b.backgroundColor     = UIColor.white.withAlphaComponent(0.22)
        b.layer.borderColor   = UIColor.white.withAlphaComponent(0.40).cgColor
        b.layer.borderWidth   = 1.5
        b.layer.masksToBounds = true
        return b
    }
}
