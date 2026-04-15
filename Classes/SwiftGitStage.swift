import Foundation

// MARK: - Swift Git Change Implementation

@objc class SwiftGitChange: NSObject, GitChange {
    
    @objc dynamic var filePath: String = ""
    @objc dynamic var changeType: GitChangeType = .modified
    @objc dynamic var isStaged: Bool = false
    @objc dynamic var isConflicted: Bool = false
    
    // Additional properties for richer change information
    @objc dynamic var oldFilePath: String? = nil  // For renames
    @objc dynamic var linesAdded: Int = 0
    @objc dynamic var linesRemoved: Int = 0
    @objc dynamic var binaryFile: Bool = false
    
    // MARK: - Initialization
    
    @objc init(filePath: String, changeType: GitChangeType, isStaged: Bool = false) {
        self.filePath = filePath
        self.changeType = changeType
        self.isStaged = isStaged
        super.init()
    }
    
    // MARK: - Factory Methods
    
    @objc static func added(file: String, staged: Bool = false) -> SwiftGitChange {
        return SwiftGitChange(filePath: file, changeType: .added, isStaged: staged)
    }
    
    @objc static func modified(file: String, staged: Bool = false) -> SwiftGitChange {
        return SwiftGitChange(filePath: file, changeType: .modified, isStaged: staged)
    }
    
    @objc static func deleted(file: String, staged: Bool = false) -> SwiftGitChange {
        return SwiftGitChange(filePath: file, changeType: .deleted, isStaged: staged)
    }
    
    @objc static func renamed(from oldPath: String, to newPath: String, staged: Bool = false) -> SwiftGitChange {
        let change = SwiftGitChange(filePath: newPath, changeType: .renamed, isStaged: staged)
        change.oldFilePath = oldPath
        return change
    }
    
    @objc static func untracked(file: String) -> SwiftGitChange {
        return SwiftGitChange(filePath: file, changeType: .untracked, isStaged: false)
    }
    
    @objc static func conflicted(file: String) -> SwiftGitChange {
        let change = SwiftGitChange(filePath: file, changeType: .conflicted, isStaged: false)
        change.isConflicted = true
        return change
    }
    
    // MARK: - Computed Properties
    
    var fileName: String {
        return (filePath as NSString).lastPathComponent
    }
    
    var fileExtension: String {
        return (filePath as NSString).pathExtension
    }
    
    var displayName: String {
        if changeType == .renamed, let oldPath = oldFilePath {
            return "\(fileName) ← \((oldPath as NSString).lastPathComponent)"
        }
        return fileName
    }
    
    var statusSymbol: String {
        return changeType.shortName
    }
    
    var canBeStaged: Bool {
        return changeType != .untracked || changeType != .conflicted
    }
    
    var canBeUnstaged: Bool {
        return isStaged
    }
    
    var canBeReverted: Bool {
        return !isStaged && changeType != .untracked
    }
    
    // MARK: - Comparison
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SwiftGitChange else { return false }
        return filePath == other.filePath && 
               changeType == other.changeType &&
               isStaged == other.isStaged
    }
    
    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(filePath)
        hasher.combine(changeType)
        hasher.combine(isStaged)
        return hasher.finalize()
    }
    
    // MARK: - Description
    
    override var description: String {
        return "GitChange(\(statusSymbol) \(filePath)\(isStaged ? " [staged]" : "")\(isConflicted ? " [conflict]" : ""))"
    }
}

// MARK: - Swift Git Stage Implementation

@objc class SwiftGitStage: NSObject, GitStage {
    
    // MARK: - Properties
    
    @objc dynamic var stagedChanges: [GitChange] = []
    @objc dynamic var unstagedChanges: [GitChange] = []
    @objc dynamic var untrackedChanges: [GitChange] = []
    @objc dynamic var currentCommitMessage: String = ""
    
    @objc weak var repository: SwiftGitRepository?
    
    // Swift-specific properties
    private var _stagedChanges: [SwiftGitChange] = [] {
        didSet {
            stagedChanges = _stagedChanges.map { $0 as GitChange }
        }
    }
    
    private var _unstagedChanges: [SwiftGitChange] = [] {
        didSet {
            unstagedChanges = _unstagedChanges.map { $0 as GitChange }
        }
    }
    
    private var _untrackedChanges: [SwiftGitChange] = [] {
        didSet {
            untrackedChanges = _untrackedChanges.map { $0 as GitChange }
        }
    }
    
    private var _isInTransaction: Bool = false
    
    // MARK: - Computed Properties
    
    var swiftStagedChanges: [SwiftGitChange] {
        get { return _stagedChanges }
        set { _stagedChanges = newValue }
    }
    
    var swiftUnstagedChanges: [SwiftGitChange] {
        get { return _unstagedChanges }
        set { _unstagedChanges = newValue }
    }
    
    var swiftUntrackedChanges: [SwiftGitChange] {
        get { return _untrackedChanges }
        set { _untrackedChanges = newValue }
    }
    
    var allChanges: [SwiftGitChange] {
        return swiftStagedChanges + swiftUnstagedChanges + swiftUntrackedChanges
    }
    
    var isRebaseConflict: Bool {
        guard let repo = repository else { return false }
        let rebaseDir = repo.gitDirectoryURL.appendingPathComponent("rebase-merge")
        return FileManager.default.directoryExists(atPath: rebaseDir.path)
    }
    
    var isDirty: Bool {
        return !swiftStagedChanges.isEmpty || !swiftUnstagedChanges.isEmpty || !swiftUntrackedChanges.isEmpty
    }
    
    var isStashable: Bool {
        return !swiftUnstagedChanges.isEmpty || !swiftStagedChanges.isEmpty
    }
    
    var isCommitable: Bool {
        return !swiftStagedChanges.isEmpty && !currentCommitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var totalPendingChanges: Int {
        return swiftStagedChanges.count + swiftUnstagedChanges.count + swiftUntrackedChanges.count
    }
    
    var defaultStashMessage: String {
        let files = allChanges.prefix(3).map { $0.fileName }
        let remainingCount = max(0, allChanges.count - 3)
        
        if files.isEmpty {
            return "WIP on \(repository?.swiftCurrentLocalRef?.name ?? "unknown")"
        }
        
        var message = files.joined(separator: ", ")
        if remainingCount > 0 {
            message += " and \(remainingCount) other\(remainingCount == 1 ? "" : "s")"
        }
        return message
    }
    
    // MARK: - Initialization
    
    @objc init(repository: SwiftGitRepository) {
        self.repository = repository
        super.init()
    }
    
    @objc override init() {
        super.init()
    }
    
    // MARK: - Stage Operations
    
    func updateConflictState() {
        // Update conflict state for all changes
        for change in allChanges {
            if change.changeType == .conflicted {
                change.isConflicted = true
            }
        }
    }
    
    func updateStage(completion: @escaping (Bool) -> Void) {
        guard let repo = repository else {
            completion(false)
            return
        }
        
        // This would integrate with the git status command
        DispatchQueue.global(qos: .userInitiated).async {
            // Simulate git status parsing
            Thread.sleep(forTimeInterval: 0.1)
            
            DispatchQueue.main.async {
                // For now, just notify no changes
                completion(false)
            }
        }
    }
    
    func stageChanges(_ changes: [GitChange], completion: @escaping () -> Void) {
        let swiftChanges = changes.compactMap { $0 as? SwiftGitChange }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Simulate git add command
            Thread.sleep(forTimeInterval: 0.1)
            
            DispatchQueue.main.async {
                // Move changes from unstaged to staged
                for change in swiftChanges {
                    change.isStaged = true
                    if let index = self.swiftUnstagedChanges.firstIndex(of: change) {
                        self.swiftUnstagedChanges.remove(at: index)
                    }
                    if let index = self.swiftUntrackedChanges.firstIndex(of: change) {
                        self.swiftUntrackedChanges.remove(at: index)
                    }
                    if !self.swiftStagedChanges.contains(change) {
                        self.swiftStagedChanges.append(change)
                    }
                }
                completion()
            }
        }
    }
    
    func unstageChanges(_ changes: [GitChange], completion: @escaping () -> Void) {
        let swiftChanges = changes.compactMap { $0 as? SwiftGitChange }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Simulate git reset command
            Thread.sleep(forTimeInterval: 0.1)
            
            DispatchQueue.main.async {
                // Move changes from staged to unstaged
                for change in swiftChanges {
                    change.isStaged = false
                    if let index = self.swiftStagedChanges.firstIndex(of: change) {
                        self.swiftStagedChanges.remove(at: index)
                    }
                    if change.changeType == .untracked {
                        if !self.swiftUntrackedChanges.contains(change) {
                            self.swiftUntrackedChanges.append(change)
                        }
                    } else {
                        if !self.swiftUnstagedChanges.contains(change) {
                            self.swiftUnstagedChanges.append(change)
                        }
                    }
                }
                completion()
            }
        }
    }
    
    func stageAll(completion: @escaping () -> Void) {
        let allUnstagedChanges = swiftUnstagedChanges + swiftUntrackedChanges
        stageChanges(allUnstagedChanges.map { $0 as GitChange }, completion: completion)
    }
    
    func revertChanges(_ changes: [GitChange], completion: @escaping () -> Void) {
        let swiftChanges = changes.compactMap { $0 as? SwiftGitChange }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Simulate git checkout command
            Thread.sleep(forTimeInterval: 0.1)
            
            DispatchQueue.main.async {
                // Remove changes from unstaged (they're reverted)
                for change in swiftChanges {
                    if !change.isStaged {
                        if let index = self.swiftUnstagedChanges.firstIndex(of: change) {
                            self.swiftUnstagedChanges.remove(at: index)
                        }
                    }
                }
                completion()
            }
        }
    }
    
    @objc func deleteFiles(in changes: [GitChange], completion: @escaping () -> Void) {
        let swiftChanges = changes.compactMap { $0 as? SwiftGitChange }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Simulate file deletion
            Thread.sleep(forTimeInterval: 0.1)
            
            DispatchQueue.main.async {
                // Remove changes and mark as deleted
                for change in swiftChanges {
                    // Remove from all arrays
                    if let index = self.swiftStagedChanges.firstIndex(of: change) {
                        self.swiftStagedChanges.remove(at: index)
                    }
                    if let index = self.swiftUnstagedChanges.firstIndex(of: change) {
                        self.swiftUnstagedChanges.remove(at: index)
                    }
                    if let index = self.swiftUntrackedChanges.firstIndex(of: change) {
                        self.swiftUntrackedChanges.remove(at: index)
                    }
                    
                    // Add as deleted if it was tracked
                    if change.changeType != .untracked {
                        let deletedChange = SwiftGitChange.deleted(file: change.filePath, staged: false)
                        self.swiftUnstagedChanges.append(deletedChange)
                    }
                }
                completion()
            }
        }
    }
    
    // MARK: - Transaction Support
    
    @objc func beginStageTransaction(completion: @escaping () -> Void) {
        _isInTransaction = true
        completion()
    }
    
    @objc func endStageTransaction() {
        _isInTransaction = false
    }
    
    // MARK: - Convenience Methods
    
    @objc func change(forFilePath filePath: String) -> SwiftGitChange? {
        return allChanges.first { $0.filePath == filePath }
    }
    
    @objc func stagedChange(forFilePath filePath: String) -> SwiftGitChange? {
        return swiftStagedChanges.first { $0.filePath == filePath }
    }
    
    @objc func unstagedChange(forFilePath filePath: String) -> SwiftGitChange? {
        return swiftUnstagedChanges.first { $0.filePath == filePath }
    }
    
    @objc func untrackedChange(forFilePath filePath: String) -> SwiftGitChange? {
        return swiftUntrackedChanges.first { $0.filePath == filePath }
    }
    
    // MARK: - Filtering
    
    func changes(ofType type: GitChangeType) -> [SwiftGitChange] {
        return allChanges.filter { $0.changeType == type }
    }
    
    func changes(matching pattern: String) -> [SwiftGitChange] {
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        return allChanges.filter { change in
            guard let regex = regex else { return false }
            let range = NSRange(location: 0, length: change.filePath.count)
            return regex.firstMatch(in: change.filePath, options: [], range: range) != nil
        }
    }
    
    var conflictedChanges: [SwiftGitChange] {
        return allChanges.filter { $0.isConflicted }
    }
    
    var binaryChanges: [SwiftGitChange] {
        return allChanges.filter { $0.binaryFile }
    }
    
    // MARK: - Description
    
    override var description: String {
        return "GitStage(staged: \(swiftStagedChanges.count), unstaged: \(swiftUnstagedChanges.count), untracked: \(swiftUntrackedChanges.count))"
    }
    
    override var debugDescription: String {
        var desc = "GitStage(\n"
        desc += "  staged: \(swiftStagedChanges.map { $0.filePath })\n"
        desc += "  unstaged: \(swiftUnstagedChanges.map { $0.filePath })\n"
        desc += "  untracked: \(swiftUntrackedChanges.map { $0.filePath })\n"
        desc += "  message: \"\(currentCommitMessage)\"\n"
        desc += ")"
        return desc
    }
}

// MARK: - Objective-C Bridge Extensions

extension SwiftGitStage {
    
    @objc var objcStagedChanges: [SwiftGitChange] {
        return swiftStagedChanges
    }
    
    @objc var objcUnstagedChanges: [SwiftGitChange] {
        return swiftUnstagedChanges
    }
    
    @objc var objcUntrackedChanges: [SwiftGitChange] {
        return swiftUntrackedChanges
    }
    
    @objc var objcAllChanges: [SwiftGitChange] {
        return allChanges
    }
    
    @objc var objcIsRebaseConflict: Bool {
        return isRebaseConflict
    }
    
    @objc var objcIsDirty: Bool {
        return isDirty
    }
    
    @objc var objcIsStashable: Bool {
        return isStashable
    }
    
    @objc var objcIsCommitable: Bool {
        return isCommitable
    }
    
    @objc var objcTotalPendingChanges: Int {
        return totalPendingChanges
    }
    
    @objc var objcDefaultStashMessage: String {
        return defaultStashMessage
    }
    
    @objc func objcStageChanges(_ changes: [SwiftGitChange], completion: @escaping () -> Void) {
        stageChanges(changes.map { $0 as GitChange }, completion: completion)
    }
    
    @objc func objcUnstageChanges(_ changes: [SwiftGitChange], completion: @escaping () -> Void) {
        unstageChanges(changes.map { $0 as GitChange }, completion: completion)
    }
    
    @objc func objcStageAll(completion: @escaping () -> Void) {
        stageAll(completion: completion)
    }
    
    @objc func objcRevertChanges(_ changes: [SwiftGitChange], completion: @escaping () -> Void) {
        revertChanges(changes.map { $0 as GitChange }, completion: completion)
    }
    
    @objc func objcUpdateStage(completion: @escaping (Bool) -> Void) {
        updateStage(completion: completion)
    }
}

// MARK: - Collection Extensions

extension Array where Element == SwiftGitChange {
    
    var staged: [SwiftGitChange] {
        return filter { $0.isStaged }
    }
    
    var unstaged: [SwiftGitChange] {
        return filter { !$0.isStaged }
    }
    
    var conflicted: [SwiftGitChange] {
        return filter { $0.isConflicted }
    }
    
    var binary: [SwiftGitChange] {
        return filter { $0.binaryFile }
    }
    
    func changes(ofType type: GitChangeType) -> [SwiftGitChange] {
        return filter { $0.changeType == type }
    }
    
    func sortedByPath() -> [SwiftGitChange] {
        return sorted { $0.filePath < $1.filePath }
    }
    
    func sortedByType() -> [SwiftGitChange] {
        return sorted { lhs, rhs in
            if lhs.changeType != rhs.changeType {
                return lhs.changeType.rawValue < rhs.changeType.rawValue
            }
            return lhs.filePath < rhs.filePath
        }
    }
}