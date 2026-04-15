import Foundation

// MARK: - Swift Git Task System

// Protocol for async git operations
@objc protocol GitTask {
    var repository: SwiftGitRepository? { get set }
    var status: GitTaskStatus { get }
    var progress: Double { get }
    var progressMessage: String { get }
    var error: Error? { get }
    
    func execute(completion: @escaping (GitResult<Any>) -> Void)
    func cancel()
}

// Base class for git tasks
@objc class SwiftGitTask: NSObject, GitTask {
    
    @objc dynamic var repository: SwiftGitRepository?
    @objc dynamic var status: GitTaskStatus = .pending
    @objc dynamic var progress: Double = 0.0
    @objc dynamic var progressMessage: String = ""
    @objc dynamic var error: Error?
    
    private var isCancelled: Bool = false
    
    // MARK: - Initialization
    
    @objc init(repository: SwiftGitRepository) {
        self.repository = repository
        super.init()
    }
    
    @objc override init() {
        super.init()
    }
    
    // MARK: - Task Execution
    
    func execute(completion: @escaping (GitResult<Any>) -> Void) {
        guard !isCancelled else {
            completion(.failure(GitTaskError.cancelled))
            return
        }
        
        status = .running
        
        // Subclasses should override this method
        performTask { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let value):
                self.status = .completed
                self.progress = 1.0
                completion(.success(value))
            case .failure(let error):
                self.status = .failed
                self.error = error
                completion(.failure(error))
            }
        }
    }
    
    // Override in subclasses
    @objc func performTask(completion: @escaping (GitResult<Any>) -> Void) {
        // Default implementation - just succeed
        completion(.success(()))
    }
    
    @objc func cancel() {
        isCancelled = true
        status = .cancelled
    }
    
    // MARK: - Convenience Methods
    
    @objc func updateProgress(_ progress: Double, message: String) {
        self.progress = progress
        self.progressMessage = message
    }
    
    @objc class func task(withRepository repository: SwiftGitRepository) -> SwiftGitTask {
        return SwiftGitTask(repository: repository)
    }
}

// MARK: - Specific Git Tasks

@objc class GitStatusTask: SwiftGitTask {
    
    override func performTask(completion: @escaping (GitResult<Any>) -> Void) {
        guard let repo = repository else {
            completion(.failure(GitTaskError.noRepository))
            return
        }
        
        updateProgress(0.1, message: "Reading repository status...")
        
        // Simulate git status command
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.2)
            
            DispatchQueue.main.async {
                self.updateProgress(0.8, message: "Parsing status...")
                
                // In a real implementation, this would parse git status output
                let changes = [
                    SwiftGitChange.modified(file: "README.md", staged: false),
                    SwiftGitChange.added(file: "newfile.txt", staged: true),
                    SwiftGitChange.untracked(file: "temp.log")
                ]
                
                repo.swiftStage?.swiftStagedChanges = changes.filter { $0.isStaged }
                repo.swiftStage?.swiftUnstagedChanges = changes.filter { !$0.isStaged && $0.changeType != .untracked }
                repo.swiftStage?.swiftUntrackedChanges = changes.filter { $0.changeType == .untracked }
                
                self.updateProgress(1.0, message: "Status updated")
                completion(.success(changes))
            }
        }
    }
}

@objc class GitFetchTask: SwiftGitTask {
    
    @objc var remote: SwiftGitRemote?
    @objc var silently: Bool = false
    
    @objc init(repository: SwiftGitRepository, remote: SwiftGitRemote?, silently: Bool = false) {
        self.remote = remote
        self.silently = silently
        super.init(repository: repository)
    }
    
    override func performTask(completion: @escaping (GitResult<Any>) -> Void) {
        guard let repo = repository else {
            completion(.failure(GitTaskError.noRepository))
            return
        }
        
        let remoteName = remote?.alias ?? "origin"
        updateProgress(0.1, message: "Fetching from \(remoteName)...")
        
        // Simulate git fetch command
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.5)
            
            DispatchQueue.main.async {
                self.updateProgress(0.8, message: "Updating references...")
                
                // In a real implementation, this would execute git fetch
                // and parse the output to update remote branches
                
                self.updateProgress(1.0, message: "Fetch completed")
                completion(.success(()))
            }
        }
    }
}

@objc class GitCommitTask: SwiftGitTask {
    
    @objc var message: String = ""
    
    @objc init(repository: SwiftGitRepository, message: String) {
        self.message = message
        super.init(repository: repository)
    }
    
    override func performTask(completion: @escaping (GitResult<Any>) -> Void) {
        guard let repo = repository else {
            completion(.failure(GitTaskError.noRepository))
            return
        }
        
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(GitTaskError.invalidMessage))
            return
        }
        
        guard let stage = repo.swiftStage, !stage.swiftStagedChanges.isEmpty else {
            completion(.failure(GitTaskError.nothingToCommit))
            return
        }
        
        updateProgress(0.1, message: "Creating commit...")
        
        // Simulate git commit command
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.3)
            
            DispatchQueue.main.async {
                self.updateProgress(0.8, message: "Updating index...")
                
                // In a real implementation, this would execute git commit
                // Clear staged changes after commit
                stage.swiftStagedChanges.removeAll()
                stage.currentCommitMessage = ""
                
                self.updateProgress(1.0, message: "Commit created")
                completion(.success(()))
            }
        }
    }
}

@objc class GitPushTask: SwiftGitTask {
    
    @objc var force: Bool = false
    @objc var localRef: SwiftGitRef?
    @objc var remoteRef: SwiftGitRef?
    
    @objc init(repository: SwiftGitRepository, force: Bool = false) {
        self.force = force
        super.init(repository: repository)
    }
    
    override func performTask(completion: @escaping (GitResult<Any>) -> Void) {
        guard let repo = repository else {
            completion(.failure(GitTaskError.noRepository))
            return
        }
        
        let branchName = repo.swiftCurrentLocalRef?.name ?? "current branch"
        updateProgress(0.1, message: "Pushing \(branchName)...")
        
        // Simulate git push command
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.8)
            
            DispatchQueue.main.async {
                self.updateProgress(0.9, message: "Updating remote...")
                
                // In a real implementation, this would execute git push
                // and handle authentication, progress, etc.
                
                self.updateProgress(1.0, message: "Push completed")
                completion(.success(()))
            }
        }
    }
}

@objc class GitCheckoutTask: SwiftGitTask {
    
    @objc var ref: SwiftGitRef
    @objc var newBranchName: String?
    
    @objc init(repository: SwiftGitRepository, ref: SwiftGitRef, newBranchName: String? = nil) {
        self.ref = ref
        self.newBranchName = newBranchName
        super.init(repository: repository)
    }
    
    override func performTask(completion: @escaping (GitResult<Any>) -> Void) {
        guard let repo = repository else {
            completion(.failure(GitTaskError.noRepository))
            return
        }
        
        let targetName = newBranchName ?? ref.name
        updateProgress(0.1, message: "Checking out \(targetName)...")
        
        // Simulate git checkout command
        DispatchQueue.global(qos: .userInitiated).async {
            Thread.sleep(forTimeInterval: 0.4)
            
            DispatchQueue.main.async {
                self.updateProgress(0.8, message: "Updating working directory...")
                
                // In a real implementation, this would execute git checkout
                repo.swiftCurrentLocalRef = self.ref
                
                self.updateProgress(1.0, message: "Checkout completed")
                completion(.success(()))
            }
        }
    }
}

// MARK: - Task Manager

@objc class GitTaskManager: NSObject {
    
    @objc static let shared = GitTaskManager()
    
    private var activeTasks: [SwiftGitTask] = []
    private let queue = DispatchQueue(label: "com.gitbox.task-manager", qos: .userInitiated)
    
    // MARK: - Task Management
    
    @objc func execute(task: SwiftGitTask, completion: @escaping (GitResult<Any>) -> Void) {
        queue.async {
            self.activeTasks.append(task)
            
            task.execute { result in
                self.queue.async {
                    if let index = self.activeTasks.firstIndex(of: task) {
                        self.activeTasks.remove(at: index)
                    }
                }
                completion(result)
            }
        }
    }
    
    @objc func cancelAllTasks() {
        queue.async {
            for task in self.activeTasks {
                task.cancel()
            }
            self.activeTasks.removeAll()
        }
    }
    
    @objc func cancelTasks(for repository: SwiftGitRepository) {
        queue.async {
            let tasksToCancel = self.activeTasks.filter { $0.repository === repository }
            for task in tasksToCancel {
                task.cancel()
            }
            self.activeTasks.removeAll { $0.repository === repository }
        }
    }
    
    @objc var activeTaskCount: Int {
        return activeTasks.count
    }
    
    @objc var hasActiveTasks: Bool {
        return !activeTasks.isEmpty
    }
}

// MARK: - Task Errors

enum GitTaskError: Error, LocalizedError {
    case noRepository
    case invalidMessage
    case nothingToCommit
    case cancelled
    case authenticationFailed
    case networkError
    case conflictDetected
    case unknown(String)
    
    var errorDescription: String? {
        switch self {
        case .noRepository:
            return "No repository available"
        case .invalidMessage:
            return "Invalid commit message"
        case .nothingToCommit:
            return "Nothing to commit"
        case .cancelled:
            return "Task was cancelled"
        case .authenticationFailed:
            return "Authentication failed"
        case .networkError:
            return "Network error"
        case .conflictDetected:
            return "Merge conflict detected"
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Async/Await Support

@available(macOS 10.15, *)
extension SwiftGitTask {
    
    func execute() async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            execute { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

@available(macOS 10.15, *)
extension GitTaskManager {
    
    func execute(task: SwiftGitTask) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            execute(task: task) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}