import UIKit

/// Transparent overlay that renders virtual D-pad and action buttons.
/// Touch events on this view are routed to the bridge; the SKView underneath
/// receives no touches from the controls area.
final class TouchControlsView: UIView {

    private let bridge: BiplanesBridge

    // Current raw input state
    private var pitchLeft  = false { didSet { updatePitch() } }
    private var pitchRight = false { didSet { updatePitch() } }
    private var thrust     = false { didSet { bridge.setThrottle(thrust ? 1 : 0) } }

    init(bridge: BiplanesBridge, frame: CGRect) {
        self.bridge = bridge
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
        buildButtons()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // ── Layout ─────────────────────────────────────────────────────────────

    private func buildButtons() {
        // Left side: ◀  ▶  (pitch) and ▲ (thrust)
        let btnLeft   = makeButton(title: "◀", tag: Tag.pitchLeft)
        let btnRight  = makeButton(title: "▶", tag: Tag.pitchRight)
        let btnThrust = makeButton(title: "▲", tag: Tag.thrust)

        // Right side: shoot ● and jump ↑
        let btnShoot = makeButton(title: "●", tag: Tag.shoot)
        let btnJump  = makeButton(title: "↑", tag: Tag.jump)

        addSubview(btnLeft);  addSubview(btnRight)
        addSubview(btnThrust)
        addSubview(btnShoot); addSubview(btnJump)

        let pad: CGFloat = 20
        let sz:  CGFloat = 64
        let gap: CGFloat = 8

        // Anchor to bottom-left
        NSLayoutConstraint.activate([
            // Pitch row
            btnLeft.leadingAnchor.constraint(equalTo: leadingAnchor, constant: pad),
            btnLeft.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
            btnLeft.widthAnchor.constraint(equalToConstant: sz),
            btnLeft.heightAnchor.constraint(equalToConstant: sz),

            btnRight.leadingAnchor.constraint(equalTo: btnLeft.trailingAnchor, constant: gap),
            btnRight.bottomAnchor.constraint(equalTo: btnLeft.bottomAnchor),
            btnRight.widthAnchor.constraint(equalToConstant: sz),
            btnRight.heightAnchor.constraint(equalToConstant: sz),

            // Thrust above left
            btnThrust.centerXAnchor.constraint(equalTo: btnLeft.centerXAnchor),
            btnThrust.bottomAnchor.constraint(equalTo: btnLeft.topAnchor, constant: -gap),
            btnThrust.widthAnchor.constraint(equalToConstant: sz),
            btnThrust.heightAnchor.constraint(equalToConstant: sz),

            // Right side: anchor to bottom-right
            btnShoot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -pad),
            btnShoot.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -pad),
            btnShoot.widthAnchor.constraint(equalToConstant: sz),
            btnShoot.heightAnchor.constraint(equalToConstant: sz),

            btnJump.trailingAnchor.constraint(equalTo: btnShoot.leadingAnchor, constant: -gap),
            btnJump.bottomAnchor.constraint(equalTo: btnShoot.bottomAnchor),
            btnJump.widthAnchor.constraint(equalToConstant: sz),
            btnJump.heightAnchor.constraint(equalToConstant: sz),
        ])
    }

    private func makeButton(title: String, tag: Int) -> UIButton {
        let btn = UIButton(type: .custom)
        btn.tag = tag
        btn.setTitle(title, for: .normal)
        btn.titleLabel?.font = .boldSystemFont(ofSize: 24)
        btn.setTitleColor(.white, for: .normal)
        btn.backgroundColor = UIColor.white.withAlphaComponent(0.20)
        btn.layer.cornerRadius = 12
        btn.layer.borderColor  = UIColor.white.withAlphaComponent(0.40).cgColor
        btn.layer.borderWidth  = 1.5
        btn.translatesAutoresizingMaskIntoConstraints = false

        btn.addTarget(self, action: #selector(btnDown(_:)), for: [.touchDown, .touchDragEnter])
        btn.addTarget(self, action: #selector(btnUp(_:)),   for: [.touchUpInside, .touchUpOutside,
                                                                   .touchCancel, .touchDragExit])
        return btn
    }

    // ── Actions ────────────────────────────────────────────────────────────

    private enum Tag {
        static let pitchLeft  = 1
        static let pitchRight = 2
        static let thrust     = 3
        static let shoot      = 4
        static let jump       = 5
    }

    @objc private func btnDown(_ sender: UIButton) {
        switch sender.tag {
        case Tag.pitchLeft:  pitchLeft  = true
        case Tag.pitchRight: pitchRight = true
        case Tag.thrust:     thrust     = true
        case Tag.shoot:      bridge.setShoot(true)
        case Tag.jump:       bridge.setJump(true)
        default: break
        }
        UIView.animate(withDuration: 0.05) {
            sender.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        }
    }

    @objc private func btnUp(_ sender: UIButton) {
        switch sender.tag {
        case Tag.pitchLeft:  pitchLeft  = false
        case Tag.pitchRight: pitchRight = false
        case Tag.thrust:     thrust     = false
        case Tag.shoot:      bridge.setShoot(false)
        case Tag.jump:       bridge.setJump(false)
        default: break
        }
        UIView.animate(withDuration: 0.10) {
            sender.backgroundColor = UIColor.white.withAlphaComponent(0.20)
        }
    }

    // Combine left/right into a single pitch value
    private func updatePitch() {
        if pitchLeft && !pitchRight {
            bridge.setPitch(1)
        } else if pitchRight && !pitchLeft {
            bridge.setPitch(2)
        } else {
            bridge.setPitch(0)
        }
    }
}
