#import "GBGitConfig.h"
#import "GBRepository.h"
#import "GBRef.h"
#import "GBStage.h"
#import "GBChange.h"

#import "GBRepositoryController.h"
#import "GBStageViewController.h"
#import "GBFileEditingController.h"
#import "GBCommitPromptController.h"
#import "GBUserNameEmailController.h"
#import "GBStageShortcutHintDetector.h"
#import "GBStageMessageHistoryController.h"
#import "GBMainWindowController.h"
#import "GBRepositorySettingsController.h"

#import "NSArray+OAArrayHelpers.h"


// Header layout constants — single source of truth.
// Vertical stack from top to bottom:
//   kFieldTopInset
//   commit field (height variable: kIdleFieldHeight or kEditingFieldHeight)
//   kFieldButtonGap          (in editing mode only; collapses to kBottomInset in idle)
//   [commit button (only in editing mode)]
//   kBottomInset
static const CGFloat kFieldTopInset = 10.0;
static const CGFloat kFieldHorizontalInset = 20.0;
static const CGFloat kFieldButtonGap = 20.0;
static const CGFloat kBottomInset = 20.0;
static const CGFloat kCommitButtonHeight = 19.0;
static const CGFloat kIdleFieldHeight = 23.0;
static const CGFloat kEditingFieldHeight = 54.0;
static const CGFloat kFieldBottomIdle = kBottomInset;                                               // field sits kBottomInset above card bottom
static const CGFloat kFieldBottomEditing = kBottomInset + kCommitButtonHeight + kFieldButtonGap;    // room for button below field
static const CGFloat kIdleHeaderHeight = kFieldTopInset + kIdleFieldHeight + kBottomInset;                                                          // 53
static const CGFloat kEditingHeaderHeight = kFieldTopInset + kEditingFieldHeight + kFieldButtonGap + kCommitButtonHeight + kBottomInset;            // 123


@interface GBStageViewController ()
@property(nonatomic, strong) GBCommitPromptController* commitPromptController;
@property(nonatomic, strong) NSIndexSet* rememberedSelectionIndexes;
@property(nonatomic, strong) GBStageShortcutHintDetector* shortcutHintDetector;
@property(nonatomic, strong) GBStageMessageHistoryController* messageHistoryController;
@property(nonatomic, strong) NSUndoManager* textViewUndoManager;
@property(nonatomic, assign) BOOL alreadyValidatedUserNameAndEmail;
@property(nonatomic, strong) NSLayoutConstraint* headerHeightConstraint;
@property(nonatomic, strong) NSLayoutConstraint* fieldBottomConstraint;

@property(weak, nonatomic, readonly) GBStage* stage;

- (BOOL) isEditingCommitMessage;
- (void) resetMessageHistory;

- (void) updateViews;
- (void) updateHeader;
- (void) updateHeaderSizeAnimating:(BOOL)animating;
- (void) updateCommitButtonEnabledState;
- (void) syncHeaderAfterLeaving;

- (BOOL) validateCommit:(id)sender;
- (BOOL) validateReallyCommit:(id)sender;
- (BOOL) validateBranch;
- (NSString*) validCommitMessage;
- (void) validateUserNameAndEmailIfNeededWithBlock:(void(^)())block;

@end



@implementation GBStageViewController

@synthesize messageTextView;
@synthesize commitButton;
@synthesize commitPromptController;
@synthesize rememberedSelectionIndexes;
@synthesize shortcutHintLabel;
@synthesize shortcutHintDetector;
@synthesize messageHistoryController;
@synthesize textViewUndoManager;

@synthesize rebaseStatusLabel;
@synthesize rebaseCancelButton;
@synthesize rebaseSkipButton;
@synthesize rebaseContinueButton;


@synthesize alreadyValidatedUserNameAndEmail;

@dynamic stage;

#pragma mark Init

- (void) dealloc
{
	[self.shortcutHintDetector reset];
	self.shortcutHintDetector.view = nil;
	
	
}





#pragma mark Public API



- (void) setRepositoryController:(GBRepositoryController*)repoCtrl
{
	[super setRepositoryController:repoCtrl];
	self.commit = repoCtrl.repository.stage;
	[self resetMessageHistory];
}





#pragma mark Subclass API




- (BOOL) embedsHeaderInTable
{
	return NO;
}


- (void) setChanges:(NSArray *)aChanges
{
	if (aChanges && self.changes == aChanges) return;
	
	for (GBChange* change in self.changes)
	{
		if (change.delegate == (id)self) change.delegate = nil;
	}
	
	NSArray* selectedChanges = [[self selectedChanges] copy];
	
	[super setChanges:aChanges];
	
	for (GBChange* change in self.changes)
	{
		change.delegate = self;
	}
	
	NSClipView* clipView = [[self.tableView enclosingScrollView] contentView];
	NSRect visibleRect = [clipView documentVisibleRect];
	
	// Restore selection
	NSMutableSet* newSelectedChanges = [NSMutableSet set];
	NSArray* allChanges = [self.statusArrayController arrangedObjects];
	for (GBChange* selectedChange in selectedChanges)
	{
		// new revision is normally 00000000000 for all changes, so we don't use it.
		GBChange* changeByOldRevision = nil;
		GBChange* changeByURL = nil;
		for (GBChange* aChange in allChanges)
		{
			if (aChange.fileURL && ((selectedChange.srcURL && [aChange.fileURL isEqual:selectedChange.srcURL]) || 
									(selectedChange.dstURL && [aChange.fileURL isEqual:selectedChange.dstURL])))
			{
				changeByURL = aChange;
			}
			if (aChange.srcRevision && selectedChange.srcRevision && [aChange.srcRevision isEqualToString:selectedChange.srcRevision])
			{
				changeByOldRevision = aChange;
			}
		}
		
		// TODO: Support multiple URLs here.
		
		if (changeByURL)
		{
			//NSLog(@"changeByURL: %@ -> %@", selectedChange, changeByURL);
			[newSelectedChanges addObject:changeByURL];
		}
		else if (changeByOldRevision)
		{
			//NSLog(@"changeByOldRevision: %@ -> %@", selectedChange, changeByOldRevision);
			[newSelectedChanges addObject:changeByOldRevision];
		}
	}
	//NSLog(@"updated selection: %@ -> %@", selectedChanges, [newSelectedChanges allObjects]);
	[self.statusArrayController setSelectedObjects:[newSelectedChanges allObjects]];
	
	[self updateViews];
	
	// Restore scroll offset.
	[clipView scrollToPoint:[clipView constrainScrollPoint:visibleRect.origin]];
	[[self.tableView enclosingScrollView] reflectScrolledClipView:clipView];
}






#pragma mark NSViewController




- (void) loadView
{
	[super loadView];
	
	[self.tableView registerForDraggedTypes:[NSArray arrayWithObjects:(NSString *)kUTTypeFileURL, NSStringPboardType, NSFilenamesPboardType, nil]];
	[self.tableView setDraggingSourceOperationMask:NSDragOperationNone forLocal:YES];
	[self.tableView setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
	[self.tableView setVerticalMotionCanBeginDrag:YES];
	
	[self.messageTextView setTextContainerInset:NSMakeSize(0.0, 3.0)];
	[self.messageTextView setFont:[NSFont systemFontOfSize:12.0]];

	[self setupHeaderLayout];

	self.shortcutHintDetector = [GBStageShortcutHintDetector detectorWithView:self.shortcutHintLabel];
	
	[self updateViews];
}



#pragma mark GBRepositoryController


- (void) repositoryControllerDidUpdateStage:(GBRepositoryController*)repoCtrl
{
	self.changes = self.stage.changes;
}



#pragma mark Actions


- (IBAction) stageAll:(id)sender
{
	[self.repositoryController stageChanges:self.stage.changes withBlock:^{
		if (!self.stage.isRebaseConflict)
		{
			[[self.messageTextView window] makeFirstResponder:self.messageTextView];
		}
	}];
}

- (BOOL) validateStageAll:(id)sender
{
	return [self.stage.changes count] > 0;
}

- (IBAction) stageDoStage:(id)sender
{
	[self.repositoryController stageChanges:[self selectedChanges]];
}

- (BOOL) validateStageDoStage:(id)sender
{
	NSArray* selChanges = [self selectedChanges];
	if ([selChanges count] < 1) return NO;
	return ![selChanges allAreTrue:@selector(staged)];
}


- (IBAction) stageDoUnstage:(id)sender
{
	[self.repositoryController unstageChanges:[self selectedChanges]];
}
- (BOOL) validateStageDoUnstage:(id)sender
{
	NSArray* selChanges = [self selectedChanges];
	if ([selChanges count] < 1) return NO;
	return [selChanges anyIsTrue:@selector(staged)];
}


- (IBAction) stageDoStageUnstage:(id)sender
{
	NSArray* selChanges = [self selectedChanges];
	if ([selChanges allAreTrue:@selector(staged)])
	{
		[self.repositoryController unstageChanges:selChanges];
	}
	else
	{
		[self.repositoryController stageChanges:selChanges];
	}
}
- (BOOL) validateStageDoStageUnstage:(id)sender
{
	if ([sender isKindOfClass:[NSMenuItem class]])
	{
		NSMenuItem* item = sender;
		[item setTitle:NSLocalizedString(@"Stage", @"Command")];
		NSArray* selChanges = [self selectedChanges];
		if ([selChanges allAreTrue:@selector(staged)])
		{
			[item setTitle:NSLocalizedString(@"Unstage", @"Command")];
		}
	}
	
	NSArray* selChanges = [self selectedChanges];
	if ([selChanges count] < 1) return NO;
	return YES;
}


- (IBAction) stageIgnoreFile:(id)sender
{
	NSArray* selChanges = [self selectedChanges];
	if ([selChanges count] < 1) return;
	NSArray* paths = [selChanges valueForKey:@"pathForIgnore"];
	[self.repositoryController removePathsFromStage:paths block:^{
		GBRepositorySettingsController* ctrl = [GBRepositorySettingsController controllerWithTab:GBRepositorySettingsSummary 
																					  repository:self.repositoryController.repository];
		[ctrl.userInfo setObject:paths forKey:@"pathsForGitIgnore"];
		[ctrl presentSheetInMainWindow];
	}];
}
- (BOOL) validateStageIgnoreFile:(id)sender
{
	NSArray* selChanges = [self selectedChanges];
	if ([selChanges count] < 1) return NO;
	return YES;
}


- (IBAction) stageRevertFile:(id)sender
{
	id changes = [[self selectedChanges] copy];
	
	[[GBMainWindowController instance] criticalConfirmationWithMessage:NSLocalizedString(@"Revert selected files to last committed state?", @"Stage") 
														   description:NSLocalizedString(@"All non-committed changes will be lost.",@"Stage")
																	ok:nil 
															completion:^(BOOL confirmed) {
																if (confirmed)
																{
																	[self.repositoryController revertChanges:changes];
																}
															}];
}
- (BOOL) validateStageRevertFile:(id)sender
{
	// returns YES when non-empty and array has something to revert
	return ![[self selectedChanges] allAreTrue:@selector(isUntrackedFile)]; 
}

- (IBAction) stageDeleteFile:(id)sender
{
	id changes = [[self selectedChanges] copy];
	
	[[GBMainWindowController instance] criticalConfirmationWithMessage:NSLocalizedString(@"Delete selected files?", @"Stage")
														   description:NSLocalizedString(@"All non-committed changes will be lost.", @"Stage")
																	ok:nil 
															completion:^(BOOL confirmed) {
																if (confirmed)
																{
																	[self.repositoryController deleteFilesInChanges:changes];
																}
															}];
}

- (BOOL) validateStageDeleteFile:(id)sender
{
	// returns YES when non-empty and array has something to delete
	if ([[self selectedChanges] allAreTrue:@selector(isDeletedFile)]) return NO;
	if ([[self selectedChanges] allAreTrue:@selector(staged)]) return NO;
	return YES;
}

- (void) commitWithSheet:(id)sender
{
	//  
	//  if (!self.commitPromptController)
	//  {
	//    self.commitPromptController = [[[GBCommitPromptController alloc] initWithWindowNibName:@"GBCommitPromptController"] autorelease];
	//  }
	//  
	//  GBCommitPromptController* prompt = self.commitPromptController;
	//  GBRepositoryController* repoCtrl = self.repositoryController;
	//  
	//  prompt.messageHistory = self.repositoryController.commitMessageHistory;
	//  prompt.value = repoCtrl.cancelledCommitMessage ? repoCtrl.cancelledCommitMessage : @"";
	//  prompt.branchName = nil;
	//  
	//  [prompt updateWindow];
	//  
	//  NSString* currentBranchName = self.repositoryController.repository.currentLocalRef.name;
	//  
	//  if (currentBranchName && 
	//      repoCtrl.lastCommitBranchName && 
	//      ![repoCtrl.lastCommitBranchName isEqualToString:currentBranchName])
	//  {
	//    prompt.branchName = currentBranchName;
	//  }
	//  
	//  prompt.finishBlock = ^{
	//    repoCtrl.cancelledCommitMessage = @"";
	//    repoCtrl.lastCommitBranchName = currentBranchName;
	//    [repoCtrl commitWithMessage:prompt.value];
	//  };
	//  prompt.cancelBlock = ^{
	//    repoCtrl.cancelledCommitMessage = prompt.value;
	//  };
	//  
	//  [prompt runSheetInWindow:[[self view] window]];
}

- (IBAction) commit:(id)sender
{
	if ([self isEditingCommitMessage])
	{
		if ([self validateReallyCommit:sender])
		{
			[self.shortcutHintDetector reset];
			[self validateUserNameAndEmailIfNeededWithBlock:^{
				[self reallyCommit:sender];
				[self resetMessageHistory];
			}];
		}
	}
	else
	{
		[self.repositoryController stageChanges:[self selectedChanges] withBlock:^{
			
			if (!self.stage.isRebaseConflict)
			{
				[[self.messageTextView window] makeFirstResponder:self.messageTextView];
			}
		}];
	}
}


- (BOOL) validateCommit:(id)sender
{
	return [self.stage isCommitable] || [[self selectedChanges] count] > 0;
}

- (void) reallyReallyCommit
{
	NSString* msg = [self validCommitMessage];
	if (!msg) return;
	[self.repositoryController commitWithMessage:msg];
	[self.messageTextView setString:@""];
	self.stage.currentCommitMessage = nil;
	[[self.view window] makeFirstResponder:self.tableView];
	if (self.rememberedSelectionIndexes)
	{
		NSUInteger firstIndex = [self.rememberedSelectionIndexes firstIndex];
		if (firstIndex == NSNotFound) firstIndex = 1;
		[self.statusArrayController setSelectionIndex:firstIndex];
	}
	else
	{
		[self.statusArrayController setSelectionIndex:1];
	}
	[self updateCommitButtonEnabledState];
}

- (IBAction) reallyCommit:(id)sender
{
	if (self.stage.isRebaseConflict)
	{
		return;
	}
	
	if (![self validateBranch])
	{
		[[GBMainWindowController instance] criticalConfirmationWithMessage:NSLocalizedString(@"Commit outside a branch?",nil) 
															   description:NSLocalizedString(@"No local branch is selected. Do you really want to create a commit outside any branch?", nil) 
																		ok:NSLocalizedString(@"Yes",nil)
																completion:^(BOOL result){
																	if (result)
																	{
																		[self reallyReallyCommit];
																	}
																}];
		return;
	}
	
	[self reallyReallyCommit];
}

- (BOOL) validateReallyCommit:(id)sender
{
	return [self validateCommit:sender] && [self validCommitMessage];
}

- (NSString*) validCommitMessage
{
	NSString* msg = [[self.messageTextView string] copy];
	msg = [msg stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([msg length] < 1)
	{
		msg = nil;
	}
	return msg;
}

- (BOOL) validateBranch
{
	BOOL isValid = !!self.repositoryController.repository.currentLocalRef.name;
	return isValid;
}

- (IBAction) previousMessage:(id)_
{
	if (!self.messageHistoryController.email)
	{
		self.messageHistoryController.email = [[GBGitConfig userConfig] userEmail];
	}
	NSString* message = [self.messageHistoryController previousMessage];
	if (message)
	{
		[self.messageTextView setString:message];
		[self.messageTextView selectAll:nil];
		[self textDidChange:nil];
	}
}

- (IBAction) nextMessage:(id)sender
{
	if (!self.messageHistoryController.email)
	{
		self.messageHistoryController.email = [[GBGitConfig userConfig] userEmail];
	}
	NSString* message = [self.messageHistoryController nextMessage];
	if (message)
	{
		[self.messageTextView setString:message];
		[self.messageTextView selectAll:nil];
		[self textDidChange:nil];
	}
}






#pragma mark Private



- (GBStage*) stage
{
	return [self.commit asStage];
}

- (void) updateViews
{
	[self updateHeader];
	[self.tableView setNextKeyView:self.messageTextView];
	[[self.tableView enclosingScrollView] setFrame:[self.view bounds]];
	
	// Fix for Lion: scroll to the top when switching commit
	{
		NSScrollView* scrollView = self.tableView.enclosingScrollView;
		NSClipView* clipView = scrollView.contentView;
		[clipView scrollToPoint:NSMakePoint(0, 0)];
		[scrollView reflectScrolledClipView:clipView];
	}
}






#pragma mark GBChangeDelegate



- (void) stageChange:(GBChange*)aChange
{
	BOOL cmdPressed = ([[NSApp currentEvent] modifierFlags] & NSCommandKeyMask);
	if (![self.changes containsObject:aChange]) return;
	
	if (cmdPressed)
	{
		[self.repositoryController stageChanges:self.changes];
	}
	else
	{
		[self.repositoryController stageChanges:[NSArray arrayWithObject:aChange]];
	}
}

- (void) unstageChange:(GBChange*)aChange
{
	BOOL cmdPressed = ([[NSApp currentEvent] modifierFlags] & NSCommandKeyMask);
	if (![self.changes containsObject:aChange]) return;
	if (cmdPressed)
	{
		[self.repositoryController unstageChanges:self.changes];
	}
	else
	{
		[self.repositoryController unstageChanges:[NSArray arrayWithObject:aChange]];
	}
}

- (void) doubleClickChange:(GBChange *)aChange
{
	static BOOL alreadyClicked = NO;
	if (alreadyClicked) return;
	alreadyClicked = YES;
	[aChange launchDiffWithBlock:^{
	}];
	
	// reset flag on the next cycle when all doubleClicks are processed.
	dispatch_async(dispatch_get_main_queue(), ^{
		alreadyClicked = NO;
	});
}





#pragma mark NSTextViewDelegate


- (NSUndoManager*) undoManagerForTextView:(NSTextView *)aTextView
{
	if (!self.textViewUndoManager)
	{
		self.textViewUndoManager = [[NSUndoManager alloc] init];
	}
	return self.textViewUndoManager;
}

- (void) textView:(NSTextView*)aTextView willBecomeFirstResponder:(BOOL)result
{
	if (!result) return;
	self.rememberedSelectionIndexes = [self.statusArrayController selectionIndexes];
	[self.statusArrayController setSelectionIndexes:[NSIndexSet indexSet]];
	
	if (!self.stage.currentCommitMessage)
	{
		[self.messageTextView setString:@""];
	}
	
	self.stage.currentCommitMessage = [[self.messageTextView string] copy];
	if (!self.stage.currentCommitMessage)
	{
		self.stage.currentCommitMessage = @"";
	}
	[self updateHeaderSizeAnimating:YES];
	
	// Scrolls in animation helper, see below.
	//[self.tableView scrollToBeginningOfDocument:nil];
	
	// before we made a commit, lets try to fetch updates from the server so that user can avoid making a commit before pulling.
	[self.repositoryController setNeedsUpdateRemoteRefs];
}

- (void) textView:(NSTextView*)aTextView willResignFirstResponder:(BOOL)result
{
	if (!result) return;

	// Check the *new* first responder on the next runloop tick — by then it has been set.
	// If focus is still inside the stage column (file list, etc.) keep editing mode and just
	// stash the current text. Only collapse when focus has left the column entirely.
	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_main_queue(), ^{
		typeof(self) strongSelf = weakSelf;
		if (!strongSelf) return;

		NSResponder* fr = strongSelf.view.window.firstResponder;
		BOOL stillInColumn = ([fr isKindOfClass:[NSView class]] &&
		                      [(NSView*)fr isDescendantOf:strongSelf.view]);
		if (stillInColumn)
		{
			strongSelf.stage.currentCommitMessage = [[strongSelf.messageTextView string] copy];
		}
		else
		{
			[strongSelf syncHeaderAfterLeaving];
		}
	});
}

- (void) textDidBeginEditing:(NSNotification*)notification
{
	// User clicked / tabbed into the commit field. Move into editing mode and animate
	// the card growing to make room for the Commit button.
	if (self.stage.currentCommitMessage == nil)
	{
		self.stage.currentCommitMessage = [[self.messageTextView string] copy] ?: @"";
	}
	[self updateHeaderSizeAnimating:YES];
}

- (void) textView:(NSTextView*)aTextView didCancel:(id)sender
{
	if (self.rememberedSelectionIndexes)
	{
		[self.statusArrayController setSelectionIndexes:self.rememberedSelectionIndexes];
	}
	[[self.view window] makeFirstResponder:self.tableView];
}

- (void)textDidChange:(NSNotification *)aNotification
{
	self.stage.currentCommitMessage = [[self.messageTextView string] copy];
	[self updateHeaderSizeAnimating:NO];
}

- (BOOL)textView:(NSTextView *)aTextView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString
{
	if (affectedCharRange.location == [[aTextView string] length] && 
		affectedCharRange.length == 0 && 
		[replacementString isEqualToString:@"\t"])
	{
		[aTextView tryToPerform:@selector(cancel:) with:self];
		return NO;
	}
	[self.shortcutHintDetector textView:aTextView didChangeTextInRange:affectedCharRange replacementString:replacementString];
	return YES;
}

- (void) syncHeaderAfterLeaving
{
	NSString* msg = [self validCommitMessage];
	if (!msg) 
	{
		[self.shortcutHintDetector reset];
	}
	self.stage.currentCommitMessage = msg;
	// This toggling hack helps to reset cursor blinking when message view resigned first responder.
	[self.messageTextView setHidden:YES];
	[self.messageTextView setHidden:NO];
	[self updateHeaderSizeAnimating:YES];
}

- (void) updateHeader
{
	NSString* msg = [self.stage.currentCommitMessage copy];
	if (!msg) msg = @"";
	if (![[self.messageTextView string] isEqualToString:msg])
	{
		[self.messageTextView setString:msg]; // resets cursor position
	}
	[self updateHeaderSizeAnimating:NO];
	
	BOOL rebaseConflict = self.stage.isRebaseConflict;
	
	[self.rebaseStatusLabel setHidden:!rebaseConflict];
	[self.rebaseCancelButton setHidden:!rebaseConflict];
	[self.rebaseSkipButton setHidden:!rebaseConflict];
	[self.rebaseContinueButton setHidden:!rebaseConflict];
	
	[[self.messageTextView enclosingScrollView] setHidden:rebaseConflict];
}

- (void) setupHeaderLayout
{
	NSScrollView* tableScrollView = self.tableView.enclosingScrollView;
	NSView* container = self.view;

	self.headerView.translatesAutoresizingMaskIntoConstraints = NO;
	tableScrollView.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:self.headerView];

	self.headerHeightConstraint = [self.headerView.heightAnchor constraintEqualToConstant:kIdleHeaderHeight];

	[NSLayoutConstraint activateConstraints:@[
		[self.headerView.topAnchor constraintEqualToAnchor:container.topAnchor],
		[self.headerView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
		[self.headerView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
		self.headerHeightConstraint,
		[tableScrollView.topAnchor constraintEqualToAnchor:self.headerView.bottomAnchor],
		[tableScrollView.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
		[tableScrollView.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
		[tableScrollView.bottomAnchor constraintEqualToAnchor:container.bottomAnchor],
	]];

	NSScrollView* commitScrollView = [self.messageTextView enclosingScrollView];
	commitScrollView.translatesAutoresizingMaskIntoConstraints = NO;
	self.commitButton.translatesAutoresizingMaskIntoConstraints = NO;
	self.commitButton.hidden = YES;

	// Field bottom sits a variable distance above the card bottom.
	//   idle    → kBottomInset (no button)
	//   editing → kBottomInset + button height + gap above button
	self.fieldBottomConstraint = [commitScrollView.bottomAnchor constraintEqualToAnchor:self.headerView.bottomAnchor constant:-kFieldBottomIdle];

	[NSLayoutConstraint activateConstraints:@[
		[commitScrollView.topAnchor constraintEqualToAnchor:self.headerView.topAnchor constant:kFieldTopInset],
		[commitScrollView.leadingAnchor constraintEqualToAnchor:self.headerView.leadingAnchor constant:kFieldHorizontalInset],
		[commitScrollView.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor constant:-kFieldHorizontalInset],
		self.fieldBottomConstraint,

		[self.commitButton.bottomAnchor constraintEqualToAnchor:self.headerView.bottomAnchor constant:-kBottomInset],
		[self.commitButton.trailingAnchor constraintEqualToAnchor:self.headerView.trailingAnchor constant:-kFieldHorizontalInset],
		[self.commitButton.heightAnchor constraintEqualToConstant:kCommitButtonHeight],
	]];
}

- (void) updateHeaderSizeAnimating:(BOOL)animating
{
	// `animating` is ignored — height changes are instant. The flag is kept so callers
	// don't need updating, but animating the card height proved too prone to side-effects
	// (textfield contents flickering, layout glitches when navigating away/back).
	(void)animating;

	BOOL editing = (self.stage.currentCommitMessage != nil);

	if (editing)
	{
		[self.messageTextView setTextColor:[NSColor labelColor]];
		self.headerHeightConstraint.constant = kEditingHeaderHeight;
		self.fieldBottomConstraint.constant = -kFieldBottomEditing;
		self.commitButton.hidden = NO;
	}
	else
	{
		[self.messageTextView setString:NSLocalizedString(@"Commit...", @"Commit")];
		[self.messageTextView setTextColor:[NSColor secondaryLabelColor]];
		self.headerHeightConstraint.constant = kIdleHeaderHeight;
		self.fieldBottomConstraint.constant = -kFieldBottomIdle;
		self.commitButton.hidden = YES;
	}

	[self.view layoutSubtreeIfNeeded];
	[self updateCommitButtonEnabledState];
}


- (BOOL) validateSelectLeftPane:(id)sender
{
	return ![self isEditingCommitMessage] && [super validateSelectLeftPane:sender];
}

- (BOOL) isEditingCommitMessage
{
	return ([[self.view window] firstResponder] == self.messageTextView);
}

- (void) updateCommitButtonEnabledState
{
	[self.commitButton setEnabled:[self validateReallyCommit:nil]];
}








#pragma mark NSTableViewDelegate



// The problem: http://www.cocoadev.com/index.pl?CheckboxInTableWithoutSelectingRow
- (BOOL)tableView:(NSTableView*)aTableView 
  shouldTrackCell:(NSCell*)aCell
   forTableColumn:(NSTableColumn*)aTableColumn
              row:(NSInteger)aRow
{
	// This allows clicking the checkbox without selecting the row
	return YES;
}


// This avoids changing selection when checkbox is clicked.
// NOTE: this method is not called because parent class implements tableView:selectionIndexesForProposedSelection:
- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex
{
	NSEvent *currentEvent = [[aTableView window] currentEvent];
	//NSLog(@"stage table view: event type = %d", [currentEvent type]);
	if([currentEvent type] != NSLeftMouseDown) return YES;
	// you may also check for the NSLeftMouseDragged event
	// (changing the selection by holding down the mouse button and moving the mouse over another row)
	int columnIndex = [aTableView columnAtPoint:[aTableView convertPoint:[currentEvent locationInWindow] fromView:nil]];
	if (columnIndex < 0) return NO;
	
	if (columnIndex < [[aTableView tableColumns] count])
	{
		if ([[[[aTableView tableColumns] objectAtIndex:columnIndex] identifier] isEqual:@"staged"])
		{
			return NO;
		}
	}
	return YES;
}









#pragma mark User name and email


- (void) validateUserNameAndEmailIfNeededWithBlock:(void(^)())block
{
	if (self.alreadyValidatedUserNameAndEmail)
	{
		if (block) block();
		return;
	}
	
	NSString* email = [[GBGitConfig userConfig] userEmail];
	
	if (email && [email length] > 3)
	{
		self.alreadyValidatedUserNameAndEmail = YES;
		if (block) block();
		return;
	}
	
	block = [block copy];
	
	GBUserNameEmailController* ctrl = [[GBUserNameEmailController alloc] initWithWindowNibName:@"GBUserNameEmailController"];
	[ctrl fillWithAddressBookData];
	__weak __typeof(ctrl) weakCtrl = ctrl;
	ctrl.completionHandler = ^(BOOL cancelled){
		if (!cancelled)
		{
			self.alreadyValidatedUserNameAndEmail = YES;
			[[GBGitConfig userConfig] setName:weakCtrl.userName email:weakCtrl.userEmail withBlock:block];
		}
		[[GBMainWindowController instance] dismissSheet:weakCtrl];
	};
	[[GBMainWindowController instance] presentSheet:ctrl];
}




#pragma mark Private


- (void) resetMessageHistory
{
	self.messageHistoryController = [GBStageMessageHistoryController new];
	
	self.messageHistoryController.repository = self.repositoryController.repository;
	self.messageHistoryController.textView = self.messageTextView;
	self.messageHistoryController.email = nil;
}


@end
