import UIKit
import SpriteKit

/// Hosts the SpriteKit view, owns the bridge, and manages app lifecycle events.
final class GameViewController: UIViewController {

    private let bridge: BiplanesBridge
    private var skView: SKView!
    private var scene: GameScene!

    init(bridge: BiplanesBridge) {
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // ── Lifecycle ──────────────────────────────────────────────────────────

    override func viewDidLoad() {
        super.viewDidLoad()

        skView = SKView(frame: view.bounds)
        skView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        skView.ignoresSiblingOrder = true
        skView.showsFPS   = false
        skView.showsNodeCount = false
        view.addSubview(skView)

        scene = GameScene(bridge: bridge, size: view.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)

        // Touch controls overlay (placed above SKView)
        let controls = TouchControlsView(bridge: bridge, frame: view.bounds)
        controls.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(controls)

        // Back button
        let backBtn = UIButton(type: .system)
        backBtn.setTitle("✕", for: .normal)
        backBtn.titleLabel?.font = .boldSystemFont(ofSize: 22)
        backBtn.setTitleColor(.white, for: .normal)
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        backBtn.addTarget(self, action: #selector(didTapBack), for: .touchUpInside)
        view.addSubview(backBtn)
        NSLayoutConstraint.activate([
            backBtn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            backBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        bridge.stop()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    @objc private func didTapBack() {
        bridge.stop()
        dismiss(animated: true)
    }
}
