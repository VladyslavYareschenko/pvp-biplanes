import SpriteKit
import UIKit

/*
 * Hosts the SpriteKit view, owns the bridge, and manages app lifecycle events.
 */
final class GameViewController: UIViewController {

    // Game area is 4:3; sidebars host the controls.
    private let gameAspect: CGFloat = 4.0 / 3.0

    // Minimum sidebar width required to use sidebar layout for controls.
    private let minSidebarWidth: CGFloat = 80

    private let bridge: BiplanesBridge
    private var skView: SKView!
    private var scene: GameScene!
    private var controlsView: TouchControlsView!

    init(bridge: BiplanesBridge) {
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        let isIPad = UIDevice.current.userInterfaceIdiom == .pad
        let bgIndex = Int.random(in: 1...3)
        let bgImage = UIImage(named: "backround_\(bgIndex)")

        skView = SKView()
        skView.translatesAutoresizingMaskIntoConstraints = false
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false
        view.addSubview(skView)

        if isIPad {
            NSLayoutConstraint.activate([
                skView.topAnchor.constraint(equalTo: view.topAnchor),
                skView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                skView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                skView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        } else {
            func blurred(_ image: UIImage?, radius: CGFloat) -> UIImage? {
                guard let img = image, let ci = CIImage(image: img) else {
                    return image
                }
                let filter = CIFilter(name: "CIGaussianBlur")
                filter?.setValue(ci, forKey: kCIInputImageKey)
                filter?.setValue(radius, forKey: kCIInputRadiusKey)
                guard let output = filter?.outputImage else { return image }
                let ctx = CIContext()
                guard let cg = ctx.createCGImage(output, from: ci.extent) else {
                    return image
                }
                return UIImage(cgImage: cg)
            }

            let blurredBg = blurred(bgImage, radius: 12)

            func makeBlurredPanel() -> UIView {
                let container = UIView()
                container.clipsToBounds = true
                container.translatesAutoresizingMaskIntoConstraints = false

                let imgView = UIImageView(image: blurredBg)
                imgView.contentMode = .scaleAspectFill
                imgView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(imgView)
                NSLayoutConstraint.activate([
                    imgView.topAnchor.constraint(equalTo: container.topAnchor),
                    imgView.bottomAnchor.constraint(
                        equalTo: container.bottomAnchor
                    ),
                    imgView.leadingAnchor.constraint(
                        equalTo: container.leadingAnchor
                    ),
                    imgView.trailingAnchor.constraint(
                        equalTo: container.trailingAnchor
                    ),
                ])

                let overlay = UIView()
                overlay.backgroundColor = UIColor(white: 0, alpha: 0.35)
                overlay.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(overlay)
                NSLayoutConstraint.activate([
                    overlay.topAnchor.constraint(equalTo: container.topAnchor),
                    overlay.bottomAnchor.constraint(
                        equalTo: container.bottomAnchor
                    ),
                    overlay.leadingAnchor.constraint(
                        equalTo: container.leadingAnchor
                    ),
                    overlay.trailingAnchor.constraint(
                        equalTo: container.trailingAnchor
                    ),
                ])
                return container
            }

            let leftPanel = makeBlurredPanel()
            let rightPanel = makeBlurredPanel()
            view.addSubview(leftPanel)
            view.addSubview(rightPanel)

            NSLayoutConstraint.activate([
                skView.topAnchor.constraint(equalTo: view.topAnchor),
                skView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                skView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                skView.widthAnchor.constraint(
                    equalTo: skView.heightAnchor,
                    multiplier: gameAspect
                ),

                leftPanel.topAnchor.constraint(equalTo: view.topAnchor),
                leftPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                leftPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                leftPanel.trailingAnchor.constraint(
                    equalTo: skView.leadingAnchor
                ),

                rightPanel.topAnchor.constraint(equalTo: view.topAnchor),
                rightPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                rightPanel.leadingAnchor.constraint(
                    equalTo: skView.trailingAnchor
                ),
                rightPanel.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor
                ),
            ])
        }

        // Use a canonical scene height so all element proportions look correct on
        // every device.  iPhone uses its actual screen height; iPad uses the iPhone
        // 16 Pro landscape reference (393 pt) so SpriteKit's aspectFit scales the
        // fixed 4:3 coordinate space up to fill the iPad screen (~2.6× on 12.9").
        let screen = UIScreen.main.bounds
        let sceneH = min(screen.width, screen.height)
        let canonicalH: CGFloat = isIPad ? 393 : sceneH
        scene = GameScene(
            bridge: bridge,
            size: CGSize(width: canonicalH * gameAspect, height: canonicalH),
            bgIndex: bgIndex
        )
        scene.scaleMode = .aspectFit
        skView.presentScene(scene)

        controlsView = TouchControlsView(bridge: bridge)
        controlsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsView)
        NSLayoutConstraint.activate([
            controlsView.topAnchor.constraint(equalTo: view.topAnchor),
            controlsView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            controlsView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controlsView.trailingAnchor.constraint(
                equalTo: view.trailingAnchor
            ),
        ])

        let backBtn = UIButton(type: .system)
        backBtn.setTitle("✕", for: .normal)
        backBtn.titleLabel?.font = .boldSystemFont(ofSize: 18)
        backBtn.setTitleColor(
            UIColor.white.withAlphaComponent(0.7),
            for: .normal
        )
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        backBtn.addTarget(
            self,
            action: #selector(didTapBack),
            for: .touchUpInside
        )
        view.addSubview(backBtn)
        NSLayoutConstraint.activate([
            backBtn.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            backBtn.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -12
            ),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if UIDevice.current.userInterfaceIdiom == .pad {
            // On iPad the game fills the screen; place buttons closer to the edges
            // so they are not centered in the right half.
            let positionCoef: CGFloat = 0.25
            controlsView.edgesPositioningXCoef = positionCoef
        } else {
            let sidebarWidth = skView.frame.minX
            if sidebarWidth >= minSidebarWidth {
                controlsView.rightZoneMinX = skView.frame.maxX
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        bridge.stop()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        .all
    }

    @objc private func didTapBack() {
        bridge.stop()
        dismiss(animated: true)
    }
}
