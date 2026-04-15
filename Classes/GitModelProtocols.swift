import Foundation

// MARK: - Git Model Protocols

/// Protocol for Git references (branches, tags, etc.)
@objc protocol GitReference {
    var name: String { get set }
    var commitId: String { get set }
    var remoteAlias: String? { get set }
    var isTag: Bool { get set }
    
    var isLocalBranch: Bool { get }
    var isRemoteBranch: Bool { get }
    var displayName: String { get }
    var commitish: String { get }
    
    func isEqual(to other: GitReference) -> Bool
}

/// Protocol for Git remotes
@objc protocol GitRemote {
    var alias: String { get set }
    var urlString: String { get set }
    var fetchRefspec: String { get set }
    var branches: [GitReference] { get set }
    var needsFetch: Bool { get set }
    
    var defaultBranch: GitReference? { get }
    var defaultFetchRefspec: String { get }
    
    func isTransientBranch(_ branch: GitReference) -> Bool
    func addNewBranch(_ branch: GitReference)
}

/// Protocol for Git staging area
@objc protocol GitStage {
    var stagedChanges: [GitChange] { get set }
    var unstagedChanges: [GitChange] { get set }
    var untrackedChanges: [GitChange] { get set }
    var currentCommitMessage: String { get set }
    
    var isRebaseConflict: Bool { get }
    var isDirty: Bool { get }
    var isStashable: Bool { get }
    var isCommitable: Bool { get }
    var totalPendingChanges: Int { get }
    var defaultStashMessage: String { get }
    
    func updateConflictState()
    func stageChanges(_ changes: [GitChange], completion: @escaping () -> Void)
    func unstageChanges(_ changes: [GitChange], completion: @escaping () -> Void)
    func stageAll(completion: @escaping () -> Void)
    func revertChanges(_ changes: [GitChange], completion: @escaping () -> Void)
}

/// Protocol for Git changes/diffs
@objc protocol GitChange {
    var filePath: String { get set }
    var changeType: GitChangeType { get set }
    var isStaged: Bool { get set }
    var isConflicted: Bool { get set }
}

/// Protocol for Git repository
@objc protocol GitRepository {
    var url: URL { get set }
    var path: String { get }
    var dotGitURL: URL? { get set }
    var localBranches: [GitReference] { get set }
    var remotes: [GitRemote] { get set }
    var tags: [GitReference] { get set }
    var currentLocalRef: GitReference? { get set }
    var currentRemoteBranch: GitReference? { get set }
    var stage: GitStage? { get set }
    var lastError: Error? { get set }
    
    var isValidRepository: Bool { get }
    var totalPendingChanges: Int { get }
    
    func updateRemotes(completion: @escaping () -> Void)
    func updateLocalRefs(completion: @escaping (Bool) -> Void)
    func checkoutRef(_ ref: GitReference, completion: @escaping () -> Void)
    func commit(message: String, completion: @escaping () -> Void)
    func fetch(completion: @escaping () -> Void)
    func push(force: Bool, completion: @escaping () -> Void)
}

// MARK: - Swift Enums

@objc enum GitChangeType: Int, CaseIterable {
    case added = 0
    case modified = 1
    case deleted = 2
    case renamed = 3
    case copied = 4
    case untracked = 5
    case conflicted = 6
    
    var displayName: String {
        switch self {
        case .added: return "Added"
        case .modified: return "Modified"
        case .deleted: return "Deleted"
        case .renamed: return "Renamed"
        case .copied: return "Copied"
        case .untracked: return "Untracked"
        case .conflicted: return "Conflicted"
        }
    }
    
    var shortName: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        case .untracked: return "?"
        case .conflicted: return "!"
        }
    }
}

@objc enum GitReferenceType: Int, CaseIterable {
    case localBranch = 0
    case remoteBranch = 1
    case tag = 2
    case commit = 3
    
    var displayName: String {
        switch self {
        case .localBranch: return "Local Branch"
        case .remoteBranch: return "Remote Branch"
        case .tag: return "Tag"
        case .commit: return "Commit"
        }
    }
}

@objc enum GitTaskStatus: Int, CaseIterable {
    case pending = 0
    case running = 1
    case completed = 2
    case failed = 3
    case cancelled = 4
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

// MARK: - Result Types

enum GitResult<T> {
    case success(T)
    case failure(Error)
    
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    var isFailure: Bool {
        return !isSuccess
    }
    
    var value: T? {
        if case .success(let value) = self { return value }
        return nil
    }
    
    var error: Error? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

// MARK: - Async/Await Support

@available(macOS 10.15, *)
extension GitRepository {
    
    func updateRemotes() async throws {
        try await withCheckedThrowingContinuation { continuation in
            updateRemotes {
                continuation.resume()
            }
        }
    }
    
    func updateLocalRefs() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            updateLocalRefs { didChange in
                continuation.resume(returning: didChange)
            }
        }
    }
    
    func checkoutRef(_ ref: GitReference) async throws {
        try await withCheckedThrowingContinuation { continuation in
            checkoutRef(ref) {
                continuation.resume()
            }
        }
    }
    
    func commit(message: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            commit(message: message) {
                continuation.resume()
            }
        }
    }
    
    func fetch() async throws {
        try await withCheckedThrowingContinuation { continuation in
            fetch {
                continuation.resume()
            }
        }
    }
    
    func push(force: Bool = false) async throws {
        try await withCheckedThrowingContinuation { continuation in
            push(force: force) {
                continuation.resume()
            }
        }
    }
}

// MARK: - Observable Support

@objc class GitObservable: NSObject {
    private var observers: [String: [(Any) -> Void]] = [:]
    
    @objc func addObserver<T>(for keyPath: String, callback: @escaping (T) -> Void) {
        let wrappedCallback: (Any) -> Void = { value in
            if let typedValue = value as? T {
                callback(typedValue)
            }
        }
        
        if observers[keyPath] == nil {
            observers[keyPath] = []
        }
        observers[keyPath]?.append(wrappedCallback)
    }
    
    @objc func notifyObservers<T>(for keyPath: String, value: T) {
        observers[keyPath]?.forEach { callback in
            callback(value)
        }
    }
    
    @objc func removeObservers(for keyPath: String) {
        observers[keyPath] = nil
    }
}