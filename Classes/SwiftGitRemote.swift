import Foundation

// MARK: - Swift Git Remote Implementation

@objc class SwiftGitRemote: NSObject, GitRemote {
    
    // MARK: - Properties
    
    @objc dynamic var alias: String = ""
    @objc dynamic var urlString: String = ""
    @objc dynamic var fetchRefspec: String = ""
    @objc dynamic var needsFetch: Bool = false
    
    @objc dynamic var branches: [GitReference] = []
    @objc weak var repository: SwiftGitRepository?
    
    private var _branches: [SwiftGitRef] = []
    
    // MARK: - Computed Properties
    
    var swiftBranches: [SwiftGitRef] {
        get { return _branches }
        set { 
            _branches = newValue
            branches = newValue.map { $0 as GitReference }
        }
    }
    
    var url: URL? {
        return URL(string: urlString)
    }
    
    var isValid: Bool {
        return !alias.isEmpty && !urlString.isEmpty
    }
    
    var isGitHub: Bool {
        return urlString.contains("github.com")
    }
    
    var isSSH: Bool {
        return urlString.hasPrefix("git@") || urlString.hasPrefix("ssh://")
    }
    
    var isHTTPS: Bool {
        return urlString.hasPrefix("https://")
    }
    
    var defaultBranch: GitReference? {
        // Try to find 'main' or 'master' branch
        let mainBranch = swiftBranches.first { $0.name == "main" || $0.name == "master" }
        return mainBranch ?? swiftBranches.first
    }
    
    var defaultFetchRefspec: String {
        if !fetchRefspec.isEmpty {
            return fetchRefspec
        }
        return "+refs/heads/*:refs/remotes/\(alias)/*"
    }
    
    // MARK: - Initialization
    
    @objc override init() {
        super.init()
    }
    
    @objc init(alias: String, urlString: String, fetchRefspec: String = "") {
        self.alias = alias
        self.urlString = urlString
        self.fetchRefspec = fetchRefspec.isEmpty ? "+refs/heads/*:refs/remotes/\(alias)/*" : fetchRefspec
        super.init()
    }
    
    // MARK: - Factory Methods
    
    @objc static func remote(alias: String, urlString: String) -> SwiftGitRemote {
        return SwiftGitRemote(alias: alias, urlString: urlString)
    }
    
    @objc static func githubRemote(alias: String, owner: String, repo: String, useSSH: Bool = false) -> SwiftGitRemote {
        let urlString = useSSH ? "git@github.com:\(owner)/\(repo).git" : "https://github.com/\(owner)/\(repo).git"
        return SwiftGitRemote(alias: alias, urlString: urlString)
    }
    
    // MARK: - Branch Management
    
    func isTransientBranch(_ branch: GitReference) -> Bool {
        guard let swiftBranch = branch as? SwiftGitRef else { return false }
        // Transient branches are typically temporary or pull request branches
        return swiftBranch.name.hasPrefix("pr/") || 
               swiftBranch.name.hasPrefix("pull/") ||
               swiftBranch.name.contains("/merge")
    }
    
    func addNewBranch(_ branch: GitReference) {
        guard let swiftBranch = branch as? SwiftGitRef else { return }
        swiftBranch.remoteAlias = alias
        
        // Don't add if already exists
        if !swiftBranches.contains(where: { $0.name == swiftBranch.name }) {
            swiftBranches.append(swiftBranch)
        }
    }
    
    @objc func addNewBranch(_ branch: SwiftGitRef) {
        addNewBranch(branch as GitReference)
    }
    
    @objc func removeBranch(_ branch: SwiftGitRef) {
        swiftBranches.removeAll { $0.name == branch.name }
    }
    
    @objc func branch(named name: String) -> SwiftGitRef? {
        return swiftBranches.first { $0.name == name }
    }
    
    @objc func updateBranches() {
        // Update all branches to ensure they have the correct remote alias
        for branch in swiftBranches {
            branch.remoteAlias = alias
        }
        needsFetch = false
    }
    
    @objc func updateNewBranches() {
        // Mark remote as needing fetch if there are new branches
        needsFetch = true
    }
    
    // MARK: - Comparison and Copying
    
    @objc func copyInterestingData(from otherRemote: SwiftGitRemote) -> Bool {
        guard alias == otherRemote.alias else { return false }
        
        var didChange = false
        
        if urlString != otherRemote.urlString {
            urlString = otherRemote.urlString
            didChange = true
        }
        
        if fetchRefspec != otherRemote.fetchRefspec {
            fetchRefspec = otherRemote.fetchRefspec
            didChange = true
        }
        
        // Update branches
        let oldBranchNames = Set(swiftBranches.map { $0.name })
        let newBranchNames = Set(otherRemote.swiftBranches.map { $0.name })
        
        if oldBranchNames != newBranchNames {
            swiftBranches = otherRemote.swiftBranches.map { branch in
                let newBranch = SwiftGitRef(name: branch.name, commitId: branch.commitId, remoteAlias: alias, isTag: false)
                return newBranch
            }
            didChange = true
        }
        
        return didChange
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SwiftGitRemote else { return false }
        return alias == other.alias && urlString == other.urlString
    }
    
    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(alias)
        hasher.combine(urlString)
        return hasher.finalize()
    }
    
    // MARK: - Async Operations
    
    @available(macOS 10.15, *)
    func updateBranches() async throws {
        try await withCheckedThrowingContinuation { continuation in
            updateBranchesSilently(true) {
                continuation.resume()
            }
        }
    }
    
    @objc func updateBranchesSilently(_ silently: Bool, withBlock block: @escaping () -> Void) {
        // This would integrate with the existing GBTask system
        // For now, we'll just call the block
        DispatchQueue.global(qos: .userInitiated).async {
            // Simulate async work
            Thread.sleep(forTimeInterval: 0.1)
            
            DispatchQueue.main.async {
                self.updateBranches()
                block()
            }
        }
    }
    
    // MARK: - Description
    
    override var description: String {
        return "GitRemote(alias: \(alias), url: \(urlString), branches: \(swiftBranches.count))"
    }
    
    override var debugDescription: String {
        var desc = "GitRemote(\n"
        desc += "  alias: \(alias)\n"
        desc += "  url: \(urlString)\n"
        desc += "  fetchRefspec: \(fetchRefspec)\n"
        desc += "  needsFetch: \(needsFetch)\n"
        desc += "  branches: [\n"
        for branch in swiftBranches {
            desc += "    \(branch.name)\n"
        }
        desc += "  ]\n"
        desc += ")"
        return desc
    }
}

// MARK: - Objective-C Bridge Extensions

extension SwiftGitRemote {
    
    @objc var objcBranches: [SwiftGitRef] {
        return swiftBranches
    }
    
    @objc var objcDefaultBranch: SwiftGitRef? {
        return defaultBranch as? SwiftGitRef
    }
    
    @objc var objcDefaultFetchRefspec: String {
        return defaultFetchRefspec
    }
    
    @objc var objcIsValid: Bool {
        return isValid
    }
    
    @objc var objcIsGitHub: Bool {
        return isGitHub
    }
    
    @objc var objcIsSSH: Bool {
        return isSSH
    }
    
    @objc var objcIsHTTPS: Bool {
        return isHTTPS
    }
    
    @objc func objcPushedAndNewBranches() -> [SwiftGitRef] {
        // This would need to be implemented based on the repository's local branches
        return swiftBranches
    }
    
    @objc func objcCopyInterestingData(from otherRemote: SwiftGitRemote) -> Bool {
        return copyInterestingData(from: otherRemote)
    }
}

// MARK: - Collection Extensions

extension Array where Element == SwiftGitRemote {
    
    func remote(withAlias alias: String) -> SwiftGitRemote? {
        return first { $0.alias == alias }
    }
    
    func remote(withURL urlString: String) -> SwiftGitRemote? {
        return first { $0.urlString == urlString }
    }
    
    var originRemote: SwiftGitRemote? {
        return remote(withAlias: "origin")
    }
    
    var upstreamRemote: SwiftGitRemote? {
        return remote(withAlias: "upstream")
    }
    
    var needingFetch: [SwiftGitRemote] {
        return filter { $0.needsFetch }
    }
    
    var validRemotes: [SwiftGitRemote] {
        return filter { $0.isValid }
    }
    
    func sortedByAlias() -> [SwiftGitRemote] {
        return sorted { $0.alias < $1.alias }
    }
}