import UIKit

class LaunchViewController: UIViewController {

    private let progressView = UIProgressView(progressViewStyle: .default)
    private var progressTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupBackground()
        setupProgressBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateProgress()
    }

    deinit {
        progressTimer?.invalidate()
    }

    private func setupBackground() {
        let backgroundImageView = UIImageView()
        backgroundImageView.image = UIImage(named: "LaunchBackground")
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        backgroundImageView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(backgroundImageView)

        NSLayoutConstraint.activate([
            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupProgressBar() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        progressView.trackTintColor = UIColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1.0)
        progressView.progress = 0.0
        progressView.layer.cornerRadius = 2
        progressView.clipsToBounds = true

        view.addSubview(progressView)
        
        let verticalConstraint = NSLayoutConstraint(
            item: progressView,
            attribute: .centerY,
            relatedBy: .equal,
            toItem: view,
            attribute: .bottom,
            multiplier: 0.75,
            constant: 0
        )

        NSLayoutConstraint.activate([
            progressView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            verticalConstraint,
            progressView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.5),
            progressView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    private func animateProgress() {
        var progress: Float = 0.0
        let increment: Float = 0.02
        
        _ = AudioManager.shared

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            progress += increment
            self.progressView.setProgress(progress, animated: true)

            if progress >= 0.9 {
                timer.invalidate()
                self.progressTimer = nil
                self.onLoadingComplete()
            }
        }
    }


    private func onLoadingComplete() {
        guard let window = view.window else { return }

        let mainVC = MenuViewController()

        UIView.transition(
            with: window,
            duration: 0.4,
            options: .transitionCrossDissolve,
            animations: { window.rootViewController = mainVC }
        )
    }
}
