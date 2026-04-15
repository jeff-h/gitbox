import Foundation

// MARK: - Swift Git Reference Implementation

@objc class SwiftGitRef: NSObject, GitReference {
    
    // MARK: - Properties
    
    @objc dynamic var name: String = ""
    @objc dynamic var commitId: String = ""
    @objc dynamic var remoteAlias: String? = nil
    @objc dynamic var isTag: Bool = false
    @objc var configuredRemoteBranch: SwiftGitRef? = nil
    
    // MARK: - Computed Properties
    
    var referenceType: GitReferenceType {
        if isTag {
            return .tag
        } else if isRemoteBranch {
            return .remoteBranch
        } else if isLocalBranch {
            return .localBranch
        } else {
            return .commit
        }
    }
    
    var isLocalBranch: Bool {
        return remoteAlias == nil && !isTag && !name.isEmpty
    }
    
    var isRemoteBranch: Bool {
        return remoteAlias != nil && !isTag
    }
    
    var displayName: String {
        if isTag {
            return "🏷️ \(name)"
        } else if isRemoteBranch {
            return "🌐 \(nameWithRemoteAlias)"
        } else if isLocalBranch {
            return "🌿 \(name)"
        } else {
            return "📝 \(commitId.prefix(8))"
        }
    }
    
    var commitish: String {
        if !name.isEmpty {
            return isRemoteBranch ? nameWithRemoteAlias : name
        } else {
            return commitId
        }
    }
    
    var nameWithRemoteAlias: String {
        guard let alias = remoteAlias, !alias.isEmpty else {
            return name
        }
        return "\(alias)/\(name)"
    }
    
    // MARK: - Initialization
    
    @objc override init() {
        super.init()
    }
    
    @objc init(name: String, commitId: String = "", remoteAlias: String? = nil, isTag: Bool = false) {
        self.name = name
        self.commitId = commitId
        self.remoteAlias = remoteAlias
        self.isTag = isTag
        super.init()
    }
    
    @objc convenience init(commitId: String) {
        self.init(name: "", commitId: commitId)
    }
    
    // MARK: - Factory Methods
    
    @objc static func localBranch(name: String, commitId: String = "") -> SwiftGitRef {
        return SwiftGitRef(name: name, commitId: commitId, remoteAlias: nil, isTag: false)
    }
    
    @objc static func remoteBranch(name: String, remoteAlias: String, commitId: String = "") -> SwiftGitRef {
        return SwiftGitRef(name: name, commitId: commitId, remoteAlias: remoteAlias, isTag: false)
    }
    
    @objc static func tag(name: String, commitId: String = "") -> SwiftGitRef {
        return SwiftGitRef(name: name, commitId: commitId, remoteAlias: nil, isTag: true)
    }
    
    @objc static func commit(id: String) -> SwiftGitRef {
        return SwiftGitRef(commitId: id)
    }
    
    // MARK: - Name Manipulation
    
    @objc func setNameWithRemoteAlias(_ nameWithAlias: String) {
        let components = nameWithAlias.components(separatedBy: "/")
        if components.count >= 2 {
            remoteAlias = components[0]
            name = components.dropFirst().joined(separator: "/")
        } else {
            remoteAlias = nil
            name = nameWithAlias
        }
    }
    
    // MARK: - Comparison
    
    func isEqual(to other: GitReference) -> Bool {
        guard let otherRef = other as? SwiftGitRef else { return false }
        return isEqual(to: otherRef)
    }
    
    @objc func isEqual(to other: SwiftGitRef) -> Bool {
        return name == other.name &&
               commitId == other.commitId &&
               remoteAlias == other.remoteAlias &&
               isTag == other.isTag
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? SwiftGitRef else { return false }
        return isEqual(to: other)
    }
    
    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(name)
        hasher.combine(commitId)
        hasher.combine(remoteAlias)
        hasher.combine(isTag)
        return hasher.finalize()
    }
    
    // MARK: - Description
    
    override var description: String {
        var desc = "GitRef("
        desc += "name: \(name)"
        if !commitId.isEmpty {
            desc += ", commitId: \(commitId.prefix(8))"
        }
        if let alias = remoteAlias {
            desc += ", remote: \(alias)"
        }
        if isTag {
            desc += ", tag"
        }
        desc += ")"
        return desc
    }
    
    override var debugDescription: String {
        return description
    }
}

// MARK: - Objective-C Bridge Extensions

extension SwiftGitRef {
    
    // Bridge methods to maintain compatibility with existing Objective-C code
    
    @objc var objcNameWithRemoteAlias: String {
        return nameWithRemoteAlias
    }
    
    @objc var objcIsLocalBranch: Bool {
        return isLocalBranch
    }
    
    @objc var objcIsRemoteBranch: Bool {
        return isRemoteBranch
    }
    
    @objc var objcDisplayName: String {
        return displayName
    }
    
    @objc var objcCommitish: String {
        return commitish
    }
    
    @objc func objcIsEqual(to other: SwiftGitRef) -> Bool {
        return isEqual(to: other)
    }
}

// MARK: - Collection Extensions

extension Array where Element == SwiftGitRef {
    
    var localBranches: [SwiftGitRef] {
        return filter { $0.isLocalBranch }
    }
    
    var remoteBranches: [SwiftGitRef] {
        return filter { $0.isRemoteBranch }
    }
    
    var tags: [SwiftGitRef] {
        return filter { $0.isTag }
    }
    
    func references(for remoteAlias: String) -> [SwiftGitRef] {
        return filter { $0.remoteAlias == remoteAlias }
    }
    
    func reference(named name: String) -> SwiftGitRef? {
        return first { $0.name == name }
    }
    
    func reference(withCommitId commitId: String) -> SwiftGitRef? {
        return first { $0.commitId == commitId }
    }
    
    func sortedByName() -> [SwiftGitRef] {
        return sorted { $0.name < $1.name }
    }
    
    func sortedByType() -> [SwiftGitRef] {
        return sorted { lhs, rhs in
            if lhs.referenceType != rhs.referenceType {
                return lhs.referenceType.rawValue < rhs.referenceType.rawValue
            }
            return lhs.name < rhs.name
        }
    }
}