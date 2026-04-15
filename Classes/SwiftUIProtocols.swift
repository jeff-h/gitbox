import Foundation
import AppKit
import Combine

// MARK: - Modern Swift UI Protocols

/// Protocol for view controllers that can be observed and notified of changes
@objc protocol ObservableViewController {
    func bind(to repository: SwiftGitRepository)
    func unbind()
    func refresh()
}

/// Protocol for view controllers that handle git operations
@objc protocol GitViewController: ObservableViewController {
    var repository: SwiftGitRepository? { get set }
    var currentTask: SwiftGitTask? { get set }
    
    func handleError(_ error: Error)
    func showProgress(_ task: SwiftGitTask)
    func hideProgress()
}

/// Protocol for view controllers that can be refreshed
@objc protocol RefreshableViewController {
    func refresh()
    func refreshIfNeeded()
}

/// Protocol for view controllers that support undo/redo
@objc protocol UndoableViewController {
    var undoManager: UndoManager? { get }
    func registerUndo(withTarget target: Any, selector: Selector, object: Any?)
}

// MARK: - Base Swift View Controller

@objc class SwiftBaseViewController: NSViewController, ObservableViewController, GitViewController {
    
    // MARK: - Properties
    
    @objc dynamic var repository: SwiftGitRepository? {
        didSet {
            if let oldRepo = oldValue {
                unbind()
            }
            if let newRepo = repository {
                bind(to: newRepo)
            }
        }
    }
    
    @objc dynamic var currentTask: SwiftGitTask? {
        didSet {
            if let task = currentTask {
                showProgress(task)
            } else {
                hideProgress()
            }
        }
    }
    
    // Combine support for modern reactive patterns
    @available(macOS 10.15, *)
    var cancellables: Set<AnyCancellable> = []
    
    private var observations: [NSKeyValueObservation] = []
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        refreshIfNeeded()
    }
    
    deinit {
        unbind()
    }
    
    // MARK: - Setup
    
    @objc func setupUI() {
        // Override in subclasses
    }
    
    // MARK: - ObservableViewController
    
    func bind(to repository: SwiftGitRepository) {
        unbind() // Clean up existing bindings
        
        // Observe repository changes
        let observation = repository.observe(\.localBranches, options: [.new, .old]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        observations.append(observation)
        
        // Setup Combine bindings if available
        if #available(macOS 10.15, *) {
            setupCombineBindings(repository: repository)
        }
    }
    
    func unbind() {
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        
        if #available(macOS 10.15, *) {
            cancellables.removeAll()
        }
    }
    
    func refresh() {
        // Override in subclasses
    }
    
    // MARK: - GitViewController
    
    func handleError(_ error: Error) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            
            if let window = self.view.window {
                alert.beginSheetModal(for: window) { _ in }
            } else {
                alert.runModal()
            }
        }
    }
    
    func showProgress(_ task: SwiftGitTask) {
        // Override in subclasses or use default implementation
        DispatchQueue.main.async {
            // Could show a progress indicator
        }
    }
    
    func hideProgress() {
        // Override in subclasses or use default implementation
        DispatchQueue.main.async {
            // Could hide progress indicator
        }
    }
    
    // MARK: - Modern Reactive Patterns
    
    @available(macOS 10.15, *)
    private func setupCombineBindings(repository: SwiftGitRepository) {
        // Example of modern reactive binding
        // This would be extended based on specific needs
        
        // Observe repository changes and update UI
        NotificationCenter.default
            .publisher(for: .init("RepositoryDidChange"))
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Convenience Methods
    
    @objc func executeTask(_ task: SwiftGitTask, completion: @escaping (Bool) -> Void = { _ in }) {
        currentTask = task
        
        GitTaskManager.shared.execute(task: task) { [weak self] result in
            DispatchQueue.main.async {
                self?.currentTask = nil
                
                switch result {
                case .success:
                    completion(true)
                case .failure(let error):
                    self?.handleError(error)
                    completion(false)
                }
            }
        }
    }
    
    @available(macOS 10.15, *)
    func executeTaskAsync(_ task: SwiftGitTask) async throws {
        currentTask = task
        defer { currentTask = nil }
        
        try await GitTaskManager.shared.execute(task: task)
    }
}

// MARK: - RefreshableViewController Extension

extension SwiftBaseViewController: RefreshableViewController {
    
    func refreshIfNeeded() {
        // Check if refresh is needed and call refresh()
        refresh()
    }
}

// MARK: - UndoableViewController Extension

extension SwiftBaseViewController: UndoableViewController {
    
    func registerUndo(withTarget target: Any, selector: Selector, object: Any?) {
        undoManager?.registerUndo(withTarget: target, selector: selector, object: object)
    }
}

// MARK: - Modern Data Binding Helpers

@objc class SwiftUIBindingHelper: NSObject {
    
    @objc static func bind<T: AnyObject>(_ object: T, keyPath: ReferenceWritableKeyPath<T, String>, to textField: NSTextField) {
        // Set initial value
        textField.stringValue = object[keyPath: keyPath]
        
        // Bind textfield changes to object
        textField.target = object
        textField.action = #selector(textFieldDidChange(_:))
        
        // Store binding info for later use
        objc_setAssociatedObject(textField, "boundObject", object, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(textField, "boundKeyPath", keyPath, .OBJC_ASSOCIATION_RETAIN)
    }
    
    @objc static func bind<T: AnyObject>(_ object: T, keyPath: ReferenceWritableKeyPath<T, Bool>, to button: NSButton) {
        // Set initial value
        button.state = object[keyPath: keyPath] ? .on : .off
        
        // Bind button changes to object
        button.target = object
        button.action = #selector(buttonDidChange(_:))
        
        // Store binding info for later use
        objc_setAssociatedObject(button, "boundObject", object, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(button, "boundKeyPath", keyPath, .OBJC_ASSOCIATION_RETAIN)
    }
    
    @objc private func textFieldDidChange(_ sender: NSTextField) {
        // This would be implemented to update the bound object
        // For simplicity, we'll leave this as a placeholder
    }
    
    @objc private func buttonDidChange(_ sender: NSButton) {
        // This would be implemented to update the bound object
        // For simplicity, we'll leave this as a placeholder
    }
}

// MARK: - Modern UI Components

@objc class SwiftProgressOverlay: NSView {
    
    private var progressIndicator: NSProgressIndicator!
    private var messageLabel: NSTextField!
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }
    
    private func setupUI() {
        // Create semi-transparent background
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        
        // Create progress indicator
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .spinning
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressIndicator)
        
        // Create message label
        messageLabel = NSTextField()
        messageLabel.isEditable = false
        messageLabel.isBezeled = false
        messageLabel.drawsBackground = false
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.alignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            progressIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
            
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 10),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
        ])
    }
    
    @objc func show(message: String) {
        messageLabel.stringValue = message
        progressIndicator.startAnimation(nil)
        isHidden = false
    }
    
    @objc func hide() {
        progressIndicator.stopAnimation(nil)
        isHidden = true
    }
}

// MARK: - Reactive Extensions

extension SwiftGitRepository {
    
    // Modern reactive way to observe changes
    @available(macOS 10.15, *)
    var localBranchesPublisher: AnyPublisher<[SwiftGitRef], Never> {
        return Publishers.KeyValueObservation(self, keyPath: \.localBranches)
            .map { $0.compactMap { $0 as? SwiftGitRef } }
            .eraseToAnyPublisher()
    }
    
    @available(macOS 10.15, *)
    var remotesPublisher: AnyPublisher<[SwiftGitRemote], Never> {
        return Publishers.KeyValueObservation(self, keyPath: \.remotes)
            .map { $0.compactMap { $0 as? SwiftGitRemote } }
            .eraseToAnyPublisher()
    }
    
    @available(macOS 10.15, *)
    var stagePublisher: AnyPublisher<SwiftGitStage?, Never> {
        return Publishers.KeyValueObservation(self, keyPath: \.stage)
            .map { $0 as? SwiftGitStage }
            .eraseToAnyPublisher()
    }
}

// MARK: - Modern UI Utilities

@objc class SwiftUIUtilities: NSObject {
    
    @objc static func createModernButton(title: String, action: Selector, target: Any?) -> NSButton {
        let button = NSButton()
        button.title = title
        button.bezelStyle = .rounded
        button.target = target as AnyObject?
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
    
    @objc static func createModernTextField(placeholder: String) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.bezelStyle = .roundedBezel
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }
    
    @objc static func createModernLabel(text: String) -> NSTextField {
        let label = NSTextField()
        label.stringValue = text
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}