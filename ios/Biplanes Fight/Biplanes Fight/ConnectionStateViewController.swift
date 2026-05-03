import UIKit

final class ConnectionStateViewController: UIViewController {
    
    private let bridge: BiplanesBridge
    private let messageLabel = UILabel()
    private let cancelButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .large)
    private var stateMonitorTimer: Timer?
    var onGameReady: (() -> Void)?
    
    init(bridge: BiplanesBridge) {
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) { fatalError("not used") }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor(white: 0, alpha: 0.8)
        
        let container = UIView()
        container.backgroundColor = UIColor(
            red: 0.12,
            green: 0.12,
            blue: 0.20,
            alpha: 0.95
        )
        container.layer.cornerRadius = 16
        container.clipsToBounds = true
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
        ])
        
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 16, weight: .medium)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 2
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(messageLabel)
        
        spinner.color = .white
        spinner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(spinner)
        
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = .boldSystemFont(ofSize: 16)
        cancelButton.setTitleColor(.systemRed, for: .normal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(didTapCancel), for: .touchUpInside)
        container.addSubview(cancelButton)
        
        NSLayoutConstraint.activate([
            spinner.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            
            messageLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            
            cancelButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            cancelButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
        
        spinner.startAnimating()
        updateMessage()
        
        // Monitor connection state changes
        stateMonitorTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.monitorState()
        }
    }
    
    deinit {
        stateMonitorTimer?.invalidate()
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }
    override var prefersStatusBarHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge {
        .all
    }
    
    private func updateMessage() {
        let state = bridge.connectionState
        let newMessage: String
        
        switch state {
        case .connecting:
            newMessage = "Connecting to server"
        case .waitingForPlayers:
            newMessage = "Fueling up the planes..."
        case .running:
            newMessage = "Game starting..."
        @unknown default:
            newMessage = "Connecting..."
        }
        
        if messageLabel.text != newMessage {
            messageLabel.text = newMessage
        }
    }
    
    private func monitorState() {
        updateMessage()
        
        let state = bridge.connectionState
        if state == .running {
            stateMonitorTimer?.invalidate()
            stateMonitorTimer = nil
            onGameReady?()
        }
    }
    
    @objc private func didTapCancel() {
        stateMonitorTimer?.invalidate()
        stateMonitorTimer = nil
        bridge.stop()
        dismiss(animated: true)
    }
}
