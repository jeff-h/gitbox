// This class monitors repository folder for updates and renames.

@class OAFSEventStream;

@interface GBFolderMonitor : NSObject

@property(nonatomic, strong) OAFSEventStream* eventStream;
@property(nonatomic, copy) NSString* path;
// The repository's resolved common git dir. Set this alongside path: git state is classified
// against it, and it is watched as a separate root when it lies outside the working tree
// (linked worktrees, submodules).
@property(nonatomic, copy) NSString* gitDirPath;

// Action signature: 
// - (void) folderMonitorDidUpdate:(GBFolderMonitor*)monitor;
@property(nonatomic, weak) id target;
@property(nonatomic, assign) SEL action;

// These properties are available only during the action message to target.
// Don't use them outside your callback.
@property(nonatomic, assign, readonly) BOOL folderIsUpdated;
@property(nonatomic, assign, readonly) BOOL dotgitIsUpdated;
@property(nonatomic, assign, readonly) BOOL dotgitIsPaused;

- (void) pauseDotGit;
- (void) resumeDotGit;

- (void) pauseFolder;
- (void) resumeFolder;

@end
