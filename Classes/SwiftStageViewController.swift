import Foundation
import AppKit
import Combine

// MARK: - Modern Swift Stage View Controller

@objc class SwiftStageViewController: SwiftBaseViewController {
    
    // MARK: - Properties
    
    @objc dynamic var stage: SwiftGitStage? {
        didSet {
            updateUI()
        }
    }
    
    @objc dynamic var commitMessage: String = "" {
        didSet {
            updateCommitButton()
        }
    }
    
    // UI Elements
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var commitMessageTextView: NSTextView!
    @IBOutlet weak var commitButton: NSButton!
    @IBOutlet weak var stageAllButton: NSButton!
    @IBOutlet weak var unstageAllButton: NSButton!
    @IBOutlet weak var changesCountLabel: NSTextField!
    
    // Programmatically created UI (if no XIB)
    private var changesTableView: NSTableView?
    private var scrollView: NSScrollView?
    private var messageScrollView: NSScrollView?
    private var buttonStackView: NSStackView?
    
    // Data source
    private var allChanges: [SwiftGitChange] = []
    private var filteredChanges: [SwiftGitChange] = []
    
    // Modern reactive support
    @available(macOS 10.15, *)
    private var stageSubscription: AnyCancellable?
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupBindings()
    }
    
    override func bind(to repository: SwiftGitRepository) {
        super.bind(to: repository)
        
        // Observe stage changes
        let stageObservation = repository.observe(\.stage, options: [.new, .old]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.stage = repository.swiftStage
                self?.loadChanges()
            }
        }
        observations.append(stageObservation)
        
        // Setup modern reactive bindings
        if #available(macOS 10.15, *) {
            setupStageObservation(repository: repository)
        }
        
        // Initialize stage
        stage = repository.swiftStage
        loadChanges()
    }
    
    // MARK: - UI Setup
    
    override func setupUI() {
        super.setupUI()
        
        // If no XIB, create UI programmatically
        if tableView == nil {
            createProgrammaticUI()
        }
        
        setupStyling()
    }
    
    private func createProgrammaticUI() {
        // Create main stack view
        let mainStackView = NSStackView()
        mainStackView.orientation = .vertical
        mainStackView.spacing = 8
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mainStackView)
        
        // Create changes table view
        scrollView = NSScrollView()
        scrollView!.hasVerticalScroller = true
        scrollView!.hasHorizontalScroller = true
        scrollView!.autohidesScrollers = true
        scrollView!.translatesAutoresizingMaskIntoConstraints = false
        
        changesTableView = NSTableView()
        changesTableView!.delegate = self
        changesTableView!.dataSource = self
        changesTableView!.allowsMultipleSelection = true
        changesTableView!.allowsColumnReordering = false
        changesTableView!.allowsColumnResizing = true
        changesTableView!.allowsColumnSelection = false
        changesTableView!.alternatingRowBackgroundColors = [
            NSColor.controlAlternatingRowBackgroundColors[0],
            NSColor.controlAlternatingRowBackgroundColors[1]
        ]
        
        scrollView!.documentView = changesTableView
        
        // Create commit message area
        messageScrollView = NSScrollView()
        messageScrollView!.hasVerticalScroller = true
        messageScrollView!.autohidesScrollers = true
        messageScrollView!.translatesAutoresizingMaskIntoConstraints = false
        
        commitMessageTextView = NSTextView()
        commitMessageTextView!.delegate = self
        commitMessageTextView!.isRichText = false
        commitMessageTextView!.isAutomaticQuoteSubstitutionEnabled = false
        commitMessageTextView!.isAutomaticDashSubstitutionEnabled = false
        commitMessageTextView!.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        
        messageScrollView!.documentView = commitMessageTextView
        
        // Create button stack
        buttonStackView = NSStackView()
        buttonStackView!.orientation = .horizontal
        buttonStackView!.spacing = 8
        buttonStackView!.translatesAutoresizingMaskIntoConstraints = false
        
        stageAllButton = SwiftUIUtilities.createModernButton(
            title: "Stage All",
            action: #selector(stageAll(_:)),
            target: self
        )
        
        unstageAllButton = SwiftUIUtilities.createModernButton(
            title: "Unstage All",
            action: #selector(unstageAll(_:)),
            target: self
        )
        
        commitButton = SwiftUIUtilities.createModernButton(
            title: "Commit",
            action: #selector(commit(_:)),
            target: self
        )
        commitButton!.keyEquivalent = "\r"
        
        changesCountLabel = SwiftUIUtilities.createModernLabel(text: "0 changes")
        
        buttonStackView!.addArrangedSubview(stageAllButton!)
        buttonStackView!.addArrangedSubview(unstageAllButton!)
        buttonStackView!.addArrangedSubview(NSView()) // Spacer
        buttonStackView!.addArrangedSubview(changesCountLabel!)
        buttonStackView!.addArrangedSubview(commitButton!)
        
        // Add to main stack
        mainStackView.addArrangedSubview(scrollView!)
        mainStackView.addArrangedSubview(messageScrollView!)
        mainStackView.addArrangedSubview(buttonStackView!)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            mainStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            mainStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            mainStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            mainStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            
            scrollView!.heightAnchor.constraint(greaterThanOrEqualTo: view.heightAnchor, multiplier: 0.6),
            messageScrollView!.heightAnchor.constraint(equalToConstant: 100),
            buttonStackView!.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        // Use the programmatically created table view
        tableView = changesTableView
    }
    
    private func setupStyling() {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        
        // Style commit button
        commitButton?.bezelStyle = .rounded
        commitButton?.isEnabled = false
        
        // Style other buttons
        stageAllButton?.bezelStyle = .rounded
        unstageAllButton?.bezelStyle = .rounded
    }
    
    private func setupTableView() {
        guard let tableView = tableView else { return }
        
        // Create columns
        let statusColumn = NSTableColumn(identifier: .init("status"))
        statusColumn.title = "Status"
        statusColumn.width = 60
        statusColumn.minWidth = 60
        statusColumn.maxWidth = 80
        tableView.addTableColumn(statusColumn)
        
        let fileColumn = NSTableColumn(identifier: .init("file"))
        fileColumn.title = "File"
        fileColumn.width = 300
        fileColumn.minWidth = 200
        tableView.addTableColumn(fileColumn)
        
        let pathColumn = NSTableColumn(identifier: .init("path"))
        pathColumn.title = "Path"
        pathColumn.width = 200
        pathColumn.minWidth = 150
        tableView.addTableColumn(pathColumn)
        
        // Setup double-click action
        tableView.doubleAction = #selector(tableViewDoubleClicked(_:))
        tableView.target = self
        
        // Setup context menu
        let contextMenu = NSMenu()
        contextMenu.addItem(withTitle: "Stage", action: #selector(stageSelectedFiles(_:)), keyEquivalent: "")
        contextMenu.addItem(withTitle: "Unstage", action: #selector(unstageSelectedFiles(_:)), keyEquivalent: "")
        contextMenu.addItem(.separator())
        contextMenu.addItem(withTitle: "Revert", action: #selector(revertSelectedFiles(_:)), keyEquivalent: "")
        contextMenu.addItem(withTitle: "Delete", action: #selector(deleteSelectedFiles(_:)), keyEquivalent: "")
        contextMenu.addItem(.separator())
        contextMenu.addItem(withTitle: "Show in Finder", action: #selector(showInFinder(_:)), keyEquivalent: "")
        
        tableView.menu = contextMenu
    }
    
    private func setupBindings() {
        // Bind commit message text view
        commitMessageTextView?.delegate = self
        
        // Setup KVO for commit message
        observe(\.commitMessage, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateCommitButton()
            }
        }
    }
    
    // MARK: - Modern Reactive Bindings
    
    @available(macOS 10.15, *)
    private func setupStageObservation(repository: SwiftGitRepository) {
        stageSubscription = repository.stagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stage in
                self?.stage = stage
                self?.loadChanges()
            }
    }
    
    // MARK: - Data Loading
    
    private func loadChanges() {
        guard let stage = stage else {
            allChanges = []
            filteredChanges = []
            tableView?.reloadData()
            updateUI()
            return
        }
        
        // Combine all changes
        allChanges = stage.swiftStagedChanges + stage.swiftUnstagedChanges + stage.swiftUntrackedChanges
        filteredChanges = allChanges
        
        // Sort by path
        filteredChanges.sort { $0.filePath < $1.filePath }
        
        // Update UI
        tableView?.reloadData()
        updateUI()
    }
    
    // MARK: - UI Updates
    
    private func updateUI() {
        updateChangesCount()
        updateCommitButton()
        updateStageButtons()
    }
    
    private func updateChangesCount() {
        let count = allChanges.count
        changesCountLabel?.stringValue = "\(count) change\(count == 1 ? "" : "s")"
    }
    
    private func updateCommitButton() {
        let hasMessage = !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasStagedChanges = stage?.swiftStagedChanges.isEmpty == false
        commitButton?.isEnabled = hasMessage && hasStagedChanges
    }
    
    private func updateStageButtons() {
        let hasUnstagedChanges = !(stage?.swiftUnstagedChanges.isEmpty ?? true) || !(stage?.swiftUntrackedChanges.isEmpty ?? true)
        let hasStagedChanges = !(stage?.swiftStagedChanges.isEmpty ?? true)
        
        stageAllButton?.isEnabled = hasUnstagedChanges
        unstageAllButton?.isEnabled = hasStagedChanges
    }
    
    // MARK: - Actions
    
    @IBAction func stageAll(_ sender: Any?) {
        guard let stage = stage else { return }
        
        let changes = stage.swiftUnstagedChanges + stage.swiftUntrackedChanges
        guard !changes.isEmpty else { return }
        
        executeStageTask(changes: changes, isStaging: true)
    }
    
    @IBAction func unstageAll(_ sender: Any?) {
        guard let stage = stage else { return }
        
        let changes = stage.swiftStagedChanges
        guard !changes.isEmpty else { return }
        
        executeStageTask(changes: changes, isStaging: false)
    }
    
    @IBAction func commit(_ sender: Any?) {
        guard let repo = repository, let stage = stage else { return }
        
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty && !stage.swiftStagedChanges.isEmpty else { return }
        
        let task = GitCommitTask(repository: repo, message: message)
        executeTask(task) { [weak self] success in
            if success {
                self?.commitMessage = ""
                self?.commitMessageTextView?.string = ""
                self?.loadChanges()
            }
        }
    }
    
    @IBAction func stageSelectedFiles(_ sender: Any?) {
        let selectedChanges = getSelectedChanges()
        let unstagedChanges = selectedChanges.filter { !$0.isStaged }
        
        guard !unstagedChanges.isEmpty else { return }
        executeStageTask(changes: unstagedChanges, isStaging: true)
    }
    
    @IBAction func unstageSelectedFiles(_ sender: Any?) {
        let selectedChanges = getSelectedChanges()
        let stagedChanges = selectedChanges.filter { $0.isStaged }
        
        guard !stagedChanges.isEmpty else { return }
        executeStageTask(changes: stagedChanges, isStaging: false)
    }
    
    @IBAction func revertSelectedFiles(_ sender: Any?) {
        let selectedChanges = getSelectedChanges()
        let revertableChanges = selectedChanges.filter { !$0.isStaged && $0.changeType != .untracked }
        
        guard !revertableChanges.isEmpty else { return }
        
        // Show confirmation dialog
        let alert = NSAlert()
        alert.messageText = "Revert Changes"
        alert.informativeText = "Are you sure you want to revert the selected changes? This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Revert")
        alert.addButton(withTitle: "Cancel")
        
        alert.beginSheetModal(for: view.window!) { response in
            if response == .alertFirstButtonReturn {
                self.executeRevertTask(changes: revertableChanges)
            }
        }
    }
    
    @IBAction func deleteSelectedFiles(_ sender: Any?) {
        let selectedChanges = getSelectedChanges()
        
        guard !selectedChanges.isEmpty else { return }
        
        // Show confirmation dialog
        let alert = NSAlert()
        alert.messageText = "Delete Files"
        alert.informativeText = "Are you sure you want to delete the selected files? This cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        alert.beginSheetModal(for: view.window!) { response in
            if response == .alertFirstButtonReturn {
                self.executeDeleteTask(changes: selectedChanges)
            }
        }
    }
    
    @IBAction func showInFinder(_ sender: Any?) {
        let selectedChanges = getSelectedChanges()
        guard let repo = repository, let firstChange = selectedChanges.first else { return }
        
        let fileURL = repo.url.appendingPathComponent(firstChange.filePath)
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: repo.path)
    }
    
    @IBAction func tableViewDoubleClicked(_ sender: Any?) {
        guard let tableView = sender as? NSTableView else { return }
        
        let row = tableView.clickedRow
        guard row >= 0 && row < filteredChanges.count else { return }
        
        let change = filteredChanges[row]
        
        // Toggle staging status
        if change.isStaged {
            executeStageTask(changes: [change], isStaging: false)
        } else {
            executeStageTask(changes: [change], isStaging: true)
        }
    }
    
    // MARK: - Task Execution
    
    private func executeStageTask(changes: [SwiftGitChange], isStaging: Bool) {
        guard let stage = stage else { return }
        
        if isStaging {
            stage.objcStageChanges(changes) { [weak self] in
                self?.loadChanges()
            }
        } else {
            stage.objcUnstageChanges(changes) { [weak self] in
                self?.loadChanges()
            }
        }
    }
    
    private func executeRevertTask(changes: [SwiftGitChange]) {
        guard let stage = stage else { return }
        
        stage.objcRevertChanges(changes) { [weak self] in
            self?.loadChanges()
        }
    }
    
    private func executeDeleteTask(changes: [SwiftGitChange]) {
        guard let stage = stage else { return }
        
        stage.deleteFiles(in: changes.map { $0 as GitChange }) { [weak self] in
            self?.loadChanges()
        }
    }
    
    // MARK: - Helper Methods
    
    private func getSelectedChanges() -> [SwiftGitChange] {
        guard let tableView = tableView else { return [] }
        
        let selectedRows = tableView.selectedRowIndexes
        return selectedRows.compactMap { row in
            guard row < filteredChanges.count else { return nil }
            return filteredChanges[row]
        }
    }
    
    private func getChangeIcon(for change: SwiftGitChange) -> NSImage? {
        switch change.changeType {
        case .added:
            return NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: "Added")
        case .modified:
            return NSImage(systemSymbolName: "pencil.circle.fill", accessibilityDescription: "Modified")
        case .deleted:
            return NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "Deleted")
        case .renamed:
            return NSImage(systemSymbolName: "arrow.right.circle.fill", accessibilityDescription: "Renamed")
        case .untracked:
            return NSImage(systemSymbolName: "questionmark.circle.fill", accessibilityDescription: "Untracked")
        case .conflicted:
            return NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Conflicted")
        default:
            return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Changed")
        }
    }
}

// MARK: - NSTableViewDataSource

extension SwiftStageViewController: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return filteredChanges.count
    }
}

// MARK: - NSTableViewDelegate

extension SwiftStageViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filteredChanges.count else { return nil }
        
        let change = filteredChanges[row]
        let identifier = tableColumn?.identifier ?? .init("")
        
        switch identifier.rawValue {
        case "status":
            let cellView = NSTableCellView()
            let imageView = NSImageView()
            imageView.image = getChangeIcon(for: change)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(imageView)
            
            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
                imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16)
            ])
            
            return cellView
            
        case "file":
            let cellView = NSTableCellView()
            let textField = NSTextField()
            textField.isEditable = false
            textField.isBezeled = false
            textField.drawsBackground = false
            textField.stringValue = change.fileName
            textField.font = NSFont.systemFont(ofSize: 13)
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(textField)
            
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])
            
            // Style based on staging status
            if change.isStaged {
                textField.textColor = NSColor.systemGreen
            } else if change.changeType == .untracked {
                textField.textColor = NSColor.systemBlue
            } else {
                textField.textColor = NSColor.labelColor
            }
            
            return cellView
            
        case "path":
            let cellView = NSTableCellView()
            let textField = NSTextField()
            textField.isEditable = false
            textField.isBezeled = false
            textField.drawsBackground = false
            textField.stringValue = (change.filePath as NSString).deletingLastPathComponent
            textField.font = NSFont.systemFont(ofSize: 11)
            textField.textColor = NSColor.secondaryLabelColor
            textField.translatesAutoresizingMaskIntoConstraints = false
            cellView.addSubview(textField)
            
            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])
            
            return cellView
            
        default:
            return nil
        }
    }
}

// MARK: - NSTextViewDelegate

extension SwiftStageViewController: NSTextViewDelegate {
    
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        
        if textView == commitMessageTextView {
            commitMessage = textView.string
            stage?.currentCommitMessage = commitMessage
        }
    }
}