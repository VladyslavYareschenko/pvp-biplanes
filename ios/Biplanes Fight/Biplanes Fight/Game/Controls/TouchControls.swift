import UIKit

/*
 * Transparent overlay that provides a floating virtual joystick on the left
 * and two action buttons (Shoot / Eject) on the right.
 *
 * Joystick — appears where the thumb first touches in the left half of the screen.
 *   X-axis  → pitch  (left = turn left, right = turn right)
 *   Y-axis  → throttle (pull up = increase, push down = decrease / idle)
 *
 * Action buttons are fixed in the lower-right corner.
 */
final class TouchControlsView: UIView {

    private let bridge: BiplanesBridge

    private let baseRadius: CGFloat = 68
    private let knobRadius: CGFloat = 30
    private let deadFraction: CGFloat = 0.18

    var leftZoneMaxX: CGFloat = 0
    var rightZoneMinX: CGFloat = 0

    private var effectiveLeftZoneMaxX: CGFloat {
        leftZoneMaxX > 0 ? leftZoneMaxX : bounds.width * 0.5
    }
    private var effectiveRightZoneMinX: CGFloat {
        rightZoneMinX > 0 ? rightZoneMinX : bounds.width * 0.5
    }

    private let stickBase = UIView()
    private let stickKnob = UIView()

    private var stickCenter: CGPoint = .zero
    private var defaultStickCenter: CGPoint = .zero
    private var activeStickTouch: UITouch?

    private let shootBtn = TouchControlsView.makeRoundBtn(
        size: 72,
        imageName: "bullet"
    )
    private let jumpBtn = TouchControlsView.makeRoundBtn(
        size: 56,
        imageName: "parachute"
    )

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
        stickBase.layer.borderWidth = 2.5
        stickBase.layer.borderColor =
            UIColor.white.withAlphaComponent(0.35).cgColor
        stickBase.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        stickBase.isUserInteractionEnabled = false
        addSubview(stickBase)

        stickKnob.layer.cornerRadius = knobRadius
        stickKnob.backgroundColor = UIColor.white.withAlphaComponent(0.55)
        stickKnob.isUserInteractionEnabled = false
        addSubview(stickKnob)
    }

    private func setupButtons() {
        addSubview(shootBtn)
        addSubview(jumpBtn)

        shootBtn.addTarget(
            self,
            action: #selector(shootDown),
            for: [.touchDown, .touchDragEnter]
        )
        shootBtn.addTarget(
            self,
            action: #selector(shootUp),
            for: [
                .touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit,
            ]
        )

        jumpBtn.addTarget(
            self,
            action: #selector(jumpDown),
            for: [.touchDown, .touchDragEnter]
        )
        jumpBtn.addTarget(
            self,
            action: #selector(jumpUp),
            for: [
                .touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit,
            ]
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Default joystick position: center-left zone, slightly below vertical center
        let leftCenterX = effectiveLeftZoneMaxX * 0.5
        let leftCenterY = bounds.height * 0.62
        defaultStickCenter = CGPoint(x: leftCenterX, y: leftCenterY)
        if activeStickTouch == nil {
            showStick(at: defaultStickCenter)
        }

        let rightStart = effectiveRightZoneMinX
        let rightWidth = bounds.width - rightStart
        let cx = rightStart + rightWidth * 0.5

        let shootSide: CGFloat = 72
        let jumpSide: CGFloat = 56
        let gap: CGFloat = 24
        let totalH = shootSide + gap + jumpSide
        let groupTop = (bounds.height - totalH) * 0.5 + bounds.height * 0.1

        shootBtn.frame = CGRect(
            x: cx - shootSide / 2,
            y: groupTop + jumpSide + gap,
            width: shootSide,
            height: shootSide
        )
        shootBtn.layer.cornerRadius = shootSide / 2

        jumpBtn.frame = CGRect(
            x: cx - jumpSide / 2,
            y: groupTop,
            width: jumpSide,
            height: jumpSide
        )
        jumpBtn.layer.cornerRadius = jumpSide / 2
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard activeStickTouch == nil else { continue }
            let loc = touch.location(in: self)
            guard loc.x < effectiveLeftZoneMaxX else { continue }
            activeStickTouch = touch
            stickCenter = loc
            showStick(at: loc)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let active = activeStickTouch, touches.contains(active) else {
            return
        }
        updateJoystick(loc: active.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        releaseStickIfNeeded(touches)
    }

    override func touchesCancelled(
        _ touches: Set<UITouch>,
        with event: UIEvent?
    ) {
        releaseStickIfNeeded(touches)
    }

    private func showStick(at center: CGPoint) {
        stickCenter = center
        let d = baseRadius * 2
        stickBase.frame = CGRect(
            x: center.x - baseRadius,
            y: center.y - baseRadius,
            width: d,
            height: d
        )
        stickKnob.center = center
    }

    private func updateJoystick(loc: CGPoint) {
        let dx = loc.x - stickCenter.x
        let dy = loc.y - stickCenter.y
        let dist = hypot(dx, dy)
        let clamped = min(dist, baseRadius)
        let angle = atan2(dy, dx)
        stickKnob.center = CGPoint(
            x: stickCenter.x + cos(angle) * clamped,
            y: stickCenter.y + sin(angle) * clamped
        )

        let magnitude = Float(clamped / baseRadius)

        // Game convention: 0deg = up, clockwise positive.
        // atan2(dx, -dy) maps screen drag to that convention.
        let gameAngle = Float(atan2(dx, -dy) * 180.0 / .pi)
        bridge.setJoystick(gameAngle, magnitude: magnitude, active: true)
    }

    private func releaseStickIfNeeded(_ touches: Set<UITouch>) {
        guard let active = activeStickTouch, touches.contains(active) else {
            return
        }
        activeStickTouch = nil
        showStick(at: defaultStickCenter)  // return to resting position, stay visible
        bridge.setJoystick(0, magnitude: 0, active: false)
    }

    @objc private func shootDown() {
        bridge.setShoot(true)
        UIView.animate(withDuration: 0.05) {
            self.shootBtn.backgroundColor = UIColor.white.withAlphaComponent(
                0.50
            )
        }
    }

    @objc private func shootUp() {
        bridge.setShoot(false)
        UIView.animate(withDuration: 0.10) {
            self.shootBtn.backgroundColor = UIColor.white.withAlphaComponent(
                0.22
            )
        }
    }

    @objc private func jumpDown() {
        bridge.setJump(true)
        UIView.animate(withDuration: 0.05) {
            self.jumpBtn.backgroundColor = UIColor.white.withAlphaComponent(
                0.50
            )
        }
    }

    @objc private func jumpUp() {
        bridge.setJump(false)
        UIView.animate(withDuration: 0.10) {
            self.jumpBtn.backgroundColor = UIColor.white.withAlphaComponent(
                0.22
            )
        }
    }

    private static func makeRoundBtn(size: CGFloat, imageName: String)
        -> UIButton
    {
        let b = UIButton(type: .custom)
        if let img = UIImage(named: imageName) {
            let padding: CGFloat = size * 0.18
            b.setImage(img, for: .normal)
            b.imageView?.contentMode = .scaleAspectFit
            b.imageEdgeInsets = UIEdgeInsets(
                top: padding,
                left: padding,
                bottom: padding,
                right: padding
            )
        }
        b.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        b.layer.borderColor = UIColor.white.withAlphaComponent(0.40).cgColor
        b.layer.borderWidth = 1.5
        b.layer.masksToBounds = true
        return b
    }
}
