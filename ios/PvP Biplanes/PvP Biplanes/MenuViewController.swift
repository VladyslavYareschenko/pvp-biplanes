import UIKit

final class MenuViewController: UIViewController {

    private let titleLabel   = UILabel()
    private let botButton    = UIButton(type: .system)
    private let onlineButton = UIButton(type: .system)
    private let hostField    = UITextField()
    private let portField    = UITextField()
    private let stack        = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.12, green: 0.12, blue: 0.20, alpha: 1)
        buildUI()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }

    private func buildUI() {
        titleLabel.text          = "PvP Biplanes"
        titleLabel.font          = .boldSystemFont(ofSize: 36)
        titleLabel.textColor     = .white
        titleLabel.textAlignment = .center

        hostField.placeholder    = "Server IP (e.g. 192.168.1.5)"
        hostField.text           = "192.168.4.153"
        hostField.borderStyle    = .roundedRect
        hostField.keyboardType   = .numbersAndPunctuation
        hostField.backgroundColor = UIColor.white.withAlphaComponent(0.9)

        portField.placeholder    = "Port"
        portField.text           = "55123"
        portField.borderStyle    = .roundedRect
        portField.keyboardType   = .numberPad
        portField.backgroundColor = UIColor.white.withAlphaComponent(0.9)

        configure(button: botButton,    title: "▶  Play vs Bot",    color: .systemGreen)
        configure(button: onlineButton, title: "🌐  Play Online",   color: .systemBlue)

        botButton.addTarget(self, action: #selector(didTapBot),    for: .touchUpInside)
        onlineButton.addTarget(self, action: #selector(didTapOnline), for: .touchUpInside)

        let networkRow = UIStackView(arrangedSubviews: [hostField, portField])
        networkRow.axis      = .horizontal
        networkRow.spacing   = 8
        networkRow.distribution = .fill
        portField.widthAnchor.constraint(equalToConstant: 80).isActive = true

        stack.axis         = .vertical
        stack.spacing      = 16
        stack.alignment    = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        [titleLabel, botButton, networkRow, onlineButton].forEach { stack.addArrangedSubview($0) }

        for sv in [networkRow, botButton, onlineButton] {
            sv.widthAnchor.constraint(equalToConstant: 300).isActive = true
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func configure(button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 20)
        button.backgroundColor  = color
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 10
    }

    @objc private func didTapBot() {
        let bridge = BiplanesBridge()
        bridge.startOfflineMode()
        push(bridge: bridge)
    }

    @objc private func didTapOnline() {
        let host = hostField.text?.trimmingCharacters(in: .whitespaces) ?? "127.0.0.1"
        let port = UInt16(portField.text ?? "55123") ?? 55123

        let bridge = BiplanesBridge()

        onlineButton.isEnabled = false
        onlineButton.setTitle("Connecting…", for: .normal)

        bridge.startOnlineMode(host, port: port) { [weak self] success, error in
            guard let self else { return }
            self.onlineButton.isEnabled = true
            self.onlineButton.setTitle("🌐  Play Online", for: .normal)

            if success {
                self.push(bridge: bridge)
            } else {
                let msg = error ?? "Unknown error"
                let alert = UIAlertController(title: "Connection Failed",
                                              message: msg,
                                              preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    private func push(bridge: BiplanesBridge) {
        let vc = GameViewController(bridge: bridge)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }
}
