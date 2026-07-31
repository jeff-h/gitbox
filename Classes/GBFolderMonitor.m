#import "OAFSEventStream.h"
#import "GBFolderMonitor.h"

@interface GBFolderMonitor ()
@property(nonatomic, strong) NSDate* folderResumeDate;
@property(nonatomic, strong) NSDate* dotgitResumeDate;
@property(nonatomic, assign) NSInteger folderPauseCounter;
@property(nonatomic, assign) NSInteger dotgitPauseCounter;
@property(nonatomic, assign, readwrite) BOOL folderIsUpdated;
@property(nonatomic, assign, readwrite) BOOL dotgitIsUpdated;
@property(nonatomic, assign, readwrite) BOOL dotgitIsPaused;
@end

@implementation GBFolderMonitor

@synthesize eventStream;
@synthesize path;
@synthesize gitDirPath;
@synthesize target;
@synthesize action;
@synthesize folderResumeDate;
@synthesize dotgitResumeDate;
@synthesize folderPauseCounter;
@synthesize dotgitPauseCounter;
@synthesize folderIsUpdated;
@synthesize dotgitIsUpdated;
@synthesize dotgitIsPaused;

- (void) dealloc
{
	// using setters to correctly remove the path and the observer from eventStream
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	if (path) [eventStream removePath:path];
	NSString* externalGitDirPath = [self externalGitDirPath];
	if (externalGitDirPath) [eventStream removePath:externalGitDirPath];
	 eventStream = nil;
}

- (void) setEventStream:(OAFSEventStream *)newEventStream
{
	if (newEventStream == eventStream) return;

	NSString* externalGitDirPath = [self externalGitDirPath];

	if (path) [eventStream removePath:path];
	if (externalGitDirPath) [eventStream removePath:externalGitDirPath];
	if (eventStream) [[NSNotificationCenter defaultCenter] removeObserver:self
																	 name:OAFSEventStreamNotification
																   object:eventStream];

	eventStream = newEventStream;

	if (eventStream) [[NSNotificationCenter defaultCenter] addObserver:self
															  selector:@selector(eventStreamDidUpdate:)
																  name:OAFSEventStreamNotification
																object:eventStream];
	if (path) [eventStream addPath:path];
	if (externalGitDirPath) [eventStream addPath:externalGitDirPath];
}

- (void) setPath:(NSString *)aPath
{
	if (aPath == path) return;

	NSString* oldExternalGitDirPath = [self externalGitDirPath];

	if (path) [eventStream removePath:path];

	path = [aPath copy];

	if (path) [eventStream addPath:path];

	// Whether the git dir needs its own watch root depends on path, so recheck.
	[self updateExternalGitDirPathWatchFrom:oldExternalGitDirPath];
}

- (void) setGitDirPath:(NSString*)aPath
{
	if (aPath == gitDirPath || [aPath isEqualToString:gitDirPath]) return;

	NSString* oldExternalGitDirPath = [self externalGitDirPath];

	gitDirPath = [aPath copy];

	[self updateExternalGitDirPathWatchFrom:oldExternalGitDirPath];
}

// The git dir needs its own watch root only when it lies outside the working tree
// (linked worktrees, submodules); otherwise the folder watch already covers it.
- (NSString*) externalGitDirPath
{
	if (!gitDirPath) return nil;
	if (path && [gitDirPath hasPrefix:[path stringByAppendingString:@"/"]]) return nil;
	return gitDirPath;
}

- (void) updateExternalGitDirPathWatchFrom:(NSString*)oldExternalGitDirPath
{
	NSString* newExternalGitDirPath = [self externalGitDirPath];
	if (oldExternalGitDirPath == newExternalGitDirPath) return;
	if (oldExternalGitDirPath && [oldExternalGitDirPath isEqualToString:newExternalGitDirPath]) return;

	if (oldExternalGitDirPath) [eventStream removePath:oldExternalGitDirPath];
	if (newExternalGitDirPath) [eventStream addPath:newExternalGitDirPath];
}

- (void) pauseDotGit
{
	self.dotgitPauseCounter++;
}

- (void) resumeDotGit
{
	self.dotgitPauseCounter--;
	if (self.dotgitPauseCounter == 0) 
	{
		self.dotgitResumeDate = [NSDate date];
	}
}

- (void) pauseFolder
{
	self.folderPauseCounter++;
}

- (void) resumeFolder
{
	self.folderPauseCounter--;
	if (self.folderPauseCounter == 0) 
	{
		self.folderResumeDate = [NSDate date];
	}
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<GBFolderMonitor:%p path=%@ eventStream=%@ target=%@ action=%@>", self, self.path, self.eventStream, self.target, self.action ? NSStringFromSelector(self.action) : nil];
}



#pragma mark Private


- (void) eventStreamDidUpdate:(NSNotification*)aNotification
{
	NSArray* events = [[aNotification userInfo] objectForKey:@"events"];
	if (!events)
	{
		NSLog(@"GBFolderMonitor: no 'events' key in notification userInfo!");
		return;
	}
	
	if (!self.path)
	{
		//NSLog(@"GBFolderMonitor: self.path = nil, but did receive a notification! %@", aNotification);
		return;
	}
	
	BOOL folderDidChange = NO;
	BOOL dotgitDidChange = NO;

	// Git state may live outside the working tree (linked worktrees, submodules),
	// so classify events against the resolved git dir, not <path>/.git.
	NSString* dotGitPath = self.gitDirPath;

	for (OAFSEvent* event in events)
	{
		if (dotGitPath && [event containedInFolder:dotGitPath])
		{
			dotgitDidChange = YES;
		}
		else if ([event containedInFolder:self.path])
		{
			folderDidChange = YES;
		}
		if (dotgitDidChange && folderDidChange) break;
	}
	
	if (!folderDidChange && !dotgitDidChange) return;
	
	// When folder on pause, should skip all events. 
	// Also we check if it was on pause less than <latency> sec. ago to skip those events too 
	// because they originate from the paused state.
	
	if (self.folderPauseCounter)
	{
		//NSLog(@"GBFolderMonitor: folder is on pause, skipping events: %@", events);
		return;
	}
	if (self.folderResumeDate)
	{
		NSTimeInterval timeSinceResume = [[NSDate date] timeIntervalSinceDate:self.folderResumeDate]; 
		if (timeSinceResume <= self.eventStream.latency)
		{
			// NSLog(@"GBFolderMonitor: folder was on pause %f sec. ago (event latency %f), skipping events: %@", timeSinceResume, self.eventStream.latency, events);
			return;
		}
	}
	
	BOOL skipDotGitEvents = NO;
	
	if (self.dotgitPauseCounter)
	{
		NSLog(@"GBFolderMonitor: .git is on pause");
		skipDotGitEvents = YES;
	}
	else
	{
		if (self.dotgitResumeDate)
		{
			NSTimeInterval timeSinceResume = [[NSDate date] timeIntervalSinceDate:self.dotgitResumeDate]; 
			if (timeSinceResume <= self.eventStream.latency)
			{
				NSLog(@"GBFolderMonitor: .git was on pause %f sec. ago (event latency %f)", timeSinceResume, self.eventStream.latency);
				skipDotGitEvents = YES;
			}
		}
	}
	
	if (skipDotGitEvents)
	{
		if (!folderDidChange)
		{
			NSLog(@"GBFolderMonitor: only .git changed and .git is on pause, skipping events: %@", events);
			return;
		}
		else
		{
			NSLog(@"GBFolderMonitor: .git is on pause, but the folder changed");
		}
	}
	
	self.folderIsUpdated = folderDidChange;
	self.dotgitIsUpdated = dotgitDidChange;
	self.dotgitIsPaused = skipDotGitEvents;
	
	//  NSLog(@"GBFolderMonitor: publishing status:%@%@%@",
	//        (self.folderIsUpdated ? @" folderIsUpdated" : @""),
	//        (self.dotgitIsUpdated ? @", dotgitIsUpdated" : @""),
	//        (self.dotgitIsPaused ? @", dotgitIsPaused" : @"")
	//        );
	
	if (!self.target || !self.action)
	{
		NSLog(@"WARNING: GBFolderMonitor: target or action is not set! Cannot publish status for events: %@", events);
	}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	if (self.action) [self.target performSelector:self.action withObject:self];
#pragma clang diagnostic pop
	
	// reset flags after calling target.action
	self.folderIsUpdated = NO;
	self.dotgitIsUpdated = NO;
	self.dotgitIsPaused = NO;
}




@end
