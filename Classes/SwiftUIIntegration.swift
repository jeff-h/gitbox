import Foundation
import AppKit
import SwiftUI

// MARK: - SwiftUI Integration for Modern UI Components

/// A hosting view controller that embeds SwiftUI views in AppKit
@available(macOS 10.15, *)
@objc class SwiftUIHostingViewController<Content: View>: NSViewController {
    
    private let rootView: Content
    private var hostingView: NSHostingView<Content>!
    
    init(rootView: Content) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        hostingView = NSHostingView(rootView: rootView)
        self.view = hostingView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure hosting view
        hostingView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    func updateRootView(_ newRootView: Content) {
        hostingView.rootView = newRootView
    }
}

// MARK: - SwiftUI Views for Git Operations

@available(macOS 10.15, *)
struct GitRepositoryView: View {
    @ObservedObject var repository: SwiftGitRepositoryObservable
    @State private var selectedTab = 0
    
    var body: some View {
        VStack {
            // Repository header
            GitRepositoryHeaderView(repository: repository)
            
            // Main content tabs
            TabView(selection: $selectedTab) {
                GitStageView(stage: repository.stage)
                    .tabItem {
                        Label("Changes", systemImage: "square.and.pencil")
                    }
                    .tag(0)
                
                GitHistoryView(repository: repository)
                    .tabItem {
                        Label("History", systemImage: "clock")
                    }
                    .tag(1)
                
                GitBranchesView(repository: repository)
                    .tabItem {
                        Label("Branches", systemImage: "arrow.branch")
                    }
                    .tag(2)
                
                GitRemotesView(repository: repository)
                    .tabItem {
                        Label("Remotes", systemImage: "network")
                    }
                    .tag(3)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

@available(macOS 10.15, *)
struct GitRepositoryHeaderView: View {
    @ObservedObject var repository: SwiftGitRepositoryObservable
    
    var body: some View {
        HStack {
            // Repository info
            VStack(alignment: .leading) {
                Text(repository.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(repository.currentBranch)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status indicators
            HStack {
                if repository.hasChanges {
                    Label("\(repository.changesCount)", systemImage: "pencil.circle.fill")
                        .foregroundColor(.orange)
                }
                
                if repository.needsFetch {
                    Label("Fetch", systemImage: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                }
                
                if repository.hasUnpushedCommits {
                    Label("Push", systemImage: "arrow.up.circle.fill")
                        .foregroundColor(.green)
                }
            }
            .font(.caption)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

@available(macOS 10.15, *)
struct GitStageView: View {
    @ObservedObject var stage: SwiftGitStageObservable
    @State private var commitMessage: String = ""
    @State private var selectedChanges: Set<String> = []
    
    var body: some View {
        VStack {
            // Changes list
            List(stage.allChanges, id: \.filePath, selection: $selectedChanges) { change in
                GitChangeRowView(change: change)
                    .contextMenu {
                        Button(change.isStaged ? "Unstage" : "Stage") {
                            toggleStaging(for: change)
                        }
                        
                        Divider()
                        
                        Button("Revert") {
                            revertChange(change)
                        }
                        .disabled(change.isStaged || change.changeType == .untracked)
                        
                        Button("Delete") {
                            deleteChange(change)
                        }
                    }
            }
            
            Divider()
            
            // Commit area
            VStack {
                TextEditor(text: $commitMessage)
                    .font(.monospaced(.body)())
                    .frame(height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.separatorColor), lineWidth: 1)
                    )
                
                HStack {
                    Button("Stage All") {
                        stageAll()
                    }
                    .disabled(stage.unstagedChanges.isEmpty)
                    
                    Button("Unstage All") {
                        unstageAll()
                    }
                    .disabled(stage.stagedChanges.isEmpty)
                    
                    Spacer()
                    
                    Text("\(stage.allChanges.count) changes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Commit") {
                        commitChanges()
                    }
                    .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || stage.stagedChanges.isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
            .padding()
        }
    }
    
    private func toggleStaging(for change: SwiftGitChangeObservable) {
        if change.isStaged {
            stage.unstage([change])
        } else {
            stage.stage([change])
        }
    }
    
    private func revertChange(_ change: SwiftGitChangeObservable) {
        stage.revert([change])
    }
    
    private func deleteChange(_ change: SwiftGitChangeObservable) {
        stage.delete([change])
    }
    
    private func stageAll() {
        stage.stageAll()
    }
    
    private func unstageAll() {
        stage.unstageAll()
    }
    
    private func commitChanges() {
        stage.commit(message: commitMessage)
        commitMessage = ""
    }
}

@available(macOS 10.15, *)
struct GitChangeRowView: View {
    @ObservedObject var change: SwiftGitChangeObservable
    
    var body: some View {
        HStack {
            // Status icon
            Image(systemName: change.statusIcon)
                .foregroundColor(change.statusColor)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 16, height: 16)
            
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(change.fileName)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(change.isStaged ? .green : .primary)
                
                if !change.directoryPath.isEmpty {
                    Text(change.directoryPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Staging status
            if change.isStaged {
                Text("Staged")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 2)
    }
}

@available(macOS 10.15, *)
struct GitHistoryView: View {
    @ObservedObject var repository: SwiftGitRepositoryObservable
    
    var body: some View {
        List(repository.commits, id: \.id) { commit in
            GitCommitRowView(commit: commit)
        }
        .onAppear {
            repository.loadCommits()
        }
    }
}

@available(macOS 10.15, *)
struct GitCommitRowView: View {
    let commit: GitCommitObservable
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(commit.shortHash)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(commit.relativeDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(commit.message)
                .font(.body)
                .lineLimit(2)
            
            Text(commit.author)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

@available(macOS 10.15, *)
struct GitBranchesView: View {
    @ObservedObject var repository: SwiftGitRepositoryObservable
    @State private var selectedBranch: String?
    
    var body: some View {
        VStack {
            HStack {
                Text("Branches")
                    .font(.headline)
                
                Spacer()
                
                Button("New Branch") {
                    createNewBranch()
                }
            }
            .padding()
            
            List(repository.branches, id: \.name, selection: $selectedBranch) { branch in
                GitBranchRowView(branch: branch, isCurrent: branch.name == repository.currentBranch)
                    .contextMenu {
                        Button("Checkout") {
                            repository.checkout(branch: branch)
                        }
                        .disabled(branch.name == repository.currentBranch)
                        
                        Button("Delete") {
                            repository.delete(branch: branch)
                        }
                        .disabled(branch.name == repository.currentBranch)
                    }
            }
        }
    }
    
    private func createNewBranch() {
        // This would show a sheet for creating a new branch
    }
}

@available(macOS 10.15, *)
struct GitBranchRowView: View {
    let branch: SwiftGitRefObservable
    let isCurrent: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "arrow.branch")
                .foregroundColor(isCurrent ? .green : .secondary)
            
            Text(branch.name)
                .font(.system(.body, design: .monospaced))
                .fontWeight(isCurrent ? .semibold : .regular)
            
            Spacer()
            
            if isCurrent {
                Text("current")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            }
        }
    }
}

@available(macOS 10.15, *)
struct GitRemotesView: View {
    @ObservedObject var repository: SwiftGitRepositoryObservable
    
    var body: some View {
        VStack {
            HStack {
                Text("Remotes")
                    .font(.headline)
                
                Spacer()
                
                Button("Add Remote") {
                    addRemote()
                }
            }
            .padding()
            
            List(repository.remotes, id: \.alias) { remote in
                GitRemoteRowView(remote: remote)
                    .contextMenu {
                        Button("Fetch") {
                            repository.fetch(remote: remote)
                        }
                        
                        Button("Remove") {
                            repository.remove(remote: remote)
                        }
                    }
            }
        }
    }
    
    private func addRemote() {
        // This would show a sheet for adding a new remote
    }
}

@available(macOS 10.15, *)
struct GitRemoteRowView: View {
    let remote: SwiftGitRemoteObservable
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(remote.alias)
                    .font(.headline)
                
                Spacer()
                
                if remote.needsFetch {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            
            Text(remote.url)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("\(remote.branchCount) branches")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Observable Wrappers for SwiftUI

@available(macOS 10.15, *)
class SwiftGitRepositoryObservable: ObservableObject {
    @Published var name: String = ""
    @Published var currentBranch: String = ""
    @Published var hasChanges: Bool = false
    @Published var changesCount: Int = 0
    @Published var needsFetch: Bool = false
    @Published var hasUnpushedCommits: Bool = false
    @Published var branches: [SwiftGitRefObservable] = []
    @Published var remotes: [SwiftGitRemoteObservable] = []
    @Published var commits: [GitCommitObservable] = []
    @Published var stage: SwiftGitStageObservable = SwiftGitStageObservable()
    
    private var repository: SwiftGitRepository?
    
    func bind(to repository: SwiftGitRepository) {
        self.repository = repository
        updateFromRepository()
    }
    
    private func updateFromRepository() {
        guard let repo = repository else { return }
        
        name = repo.url.lastPathComponent
        currentBranch = repo.swiftCurrentLocalRef?.name ?? "No branch"
        hasChanges = repo.totalPendingChanges > 0
        changesCount = repo.totalPendingChanges
        
        // Update branches
        branches = repo.swiftLocalBranches.map { SwiftGitRefObservable(ref: $0) }
        
        // Update remotes
        remotes = repo.swiftRemotes.map { SwiftGitRemoteObservable(remote: $0) }
        
        // Update stage
        if let repoStage = repo.swiftStage {
            stage.bind(to: repoStage)
        }
    }
    
    func loadCommits() {
        // This would load commits from the repository
        commits = []
    }
    
    func checkout(branch: SwiftGitRefObservable) {
        // Implementation for checkout
    }
    
    func delete(branch: SwiftGitRefObservable) {
        // Implementation for delete branch
    }
    
    func fetch(remote: SwiftGitRemoteObservable) {
        // Implementation for fetch
    }
    
    func remove(remote: SwiftGitRemoteObservable) {
        // Implementation for remove remote
    }
}

@available(macOS 10.15, *)
class SwiftGitStageObservable: ObservableObject {
    @Published var allChanges: [SwiftGitChangeObservable] = []
    @Published var stagedChanges: [SwiftGitChangeObservable] = []
    @Published var unstagedChanges: [SwiftGitChangeObservable] = []
    
    private var stage: SwiftGitStage?
    
    func bind(to stage: SwiftGitStage) {
        self.stage = stage
        updateFromStage()
    }
    
    private func updateFromStage() {
        guard let stage = stage else { return }
        
        allChanges = stage.allChanges.map { SwiftGitChangeObservable(change: $0) }
        stagedChanges = stage.swiftStagedChanges.map { SwiftGitChangeObservable(change: $0) }
        unstagedChanges = stage.swiftUnstagedChanges.map { SwiftGitChangeObservable(change: $0) }
    }
    
    func stage(_ changes: [SwiftGitChangeObservable]) {
        // Implementation for staging
    }
    
    func unstage(_ changes: [SwiftGitChangeObservable]) {
        // Implementation for unstaging
    }
    
    func revert(_ changes: [SwiftGitChangeObservable]) {
        // Implementation for reverting
    }
    
    func delete(_ changes: [SwiftGitChangeObservable]) {
        // Implementation for deleting
    }
    
    func stageAll() {
        // Implementation for stage all
    }
    
    func unstageAll() {
        // Implementation for unstage all
    }
    
    func commit(message: String) {
        // Implementation for commit
    }
}

@available(macOS 10.15, *)
class SwiftGitChangeObservable: ObservableObject {
    @Published var filePath: String = ""
    @Published var fileName: String = ""
    @Published var directoryPath: String = ""
    @Published var isStaged: Bool = false
    @Published var changeType: GitChangeType = .modified
    
    private var change: SwiftGitChange?
    
    init(change: SwiftGitChange) {
        self.change = change
        updateFromChange()
    }
    
    private func updateFromChange() {
        guard let change = change else { return }
        
        filePath = change.filePath
        fileName = change.fileName
        directoryPath = (change.filePath as NSString).deletingLastPathComponent
        isStaged = change.isStaged
        changeType = change.changeType
    }
    
    var statusIcon: String {
        switch changeType {
        case .added: return "plus.circle.fill"
        case .modified: return "pencil.circle.fill"
        case .deleted: return "minus.circle.fill"
        case .renamed: return "arrow.right.circle.fill"
        case .untracked: return "questionmark.circle.fill"
        case .conflicted: return "exclamationmark.triangle.fill"
        default: return "circle.fill"
        }
    }
    
    var statusColor: Color {
        switch changeType {
        case .added: return .green
        case .modified: return .orange
        case .deleted: return .red
        case .renamed: return .blue
        case .untracked: return .gray
        case .conflicted: return .red
        default: return .primary
        }
    }
}

@available(macOS 10.15, *)
class SwiftGitRefObservable: ObservableObject {
    @Published var name: String = ""
    @Published var isRemote: Bool = false
    @Published var isTag: Bool = false
    
    private var ref: SwiftGitRef?
    
    init(ref: SwiftGitRef) {
        self.ref = ref
        updateFromRef()
    }
    
    private func updateFromRef() {
        guard let ref = ref else { return }
        
        name = ref.name
        isRemote = ref.isRemoteBranch
        isTag = ref.isTag
    }
}

@available(macOS 10.15, *)
class SwiftGitRemoteObservable: ObservableObject {
    @Published var alias: String = ""
    @Published var url: String = ""
    @Published var branchCount: Int = 0
    @Published var needsFetch: Bool = false
    
    private var remote: SwiftGitRemote?
    
    init(remote: SwiftGitRemote) {
        self.remote = remote
        updateFromRemote()
    }
    
    private func updateFromRemote() {
        guard let remote = remote else { return }
        
        alias = remote.alias
        url = remote.urlString
        branchCount = remote.swiftBranches.count
        needsFetch = remote.needsFetch
    }
}

@available(macOS 10.15, *)
class GitCommitObservable: ObservableObject {
    let id: String
    let shortHash: String
    let message: String
    let author: String
    let relativeDate: String
    
    init(id: String, shortHash: String, message: String, author: String, relativeDate: String) {
        self.id = id
        self.shortHash = shortHash
        self.message = message
        self.author = author
        self.relativeDate = relativeDate
    }
}

// MARK: - SwiftUI Bridge for AppKit

@available(macOS 10.15, *)
@objc class SwiftUIBridge: NSObject {
    
    @objc static func createRepositoryView(repository: SwiftGitRepository) -> NSViewController {
        let observableRepository = SwiftGitRepositoryObservable()
        observableRepository.bind(to: repository)
        
        let swiftUIView = GitRepositoryView(repository: observableRepository)
        return SwiftUIHostingViewController(rootView: swiftUIView)
    }
    
    @objc static func createStageView(stage: SwiftGitStage) -> NSViewController {
        let observableStage = SwiftGitStageObservable()
        observableStage.bind(to: stage)
        
        let swiftUIView = GitStageView(stage: observableStage)
        return SwiftUIHostingViewController(rootView: swiftUIView)
    }
}