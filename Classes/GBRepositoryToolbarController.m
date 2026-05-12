#import "GBRepositoryController.h"
#import "GBRepository.h"
#import "GBRef.h"
#import "GBCommit.h"
#import "GBStage.h"
#import "GBRemote.h"

#import "GBRepositoryToolbarController.h"
#import "GBPromptController.h"
#import "GBMainWindowController.h"

#import "NSObject+OASelectorNotifications.h"
#import "NSMenu+OAMenuHelpers.h"
#import "NSArray+OAArrayHelpers.h"
#import "NSString+OAStringHelpers.h"

@interface GBRepositoryToolbarController () <NSTextFieldDelegate, NSMenuDelegate>

@property(weak, nonatomic, readonly) NSPopUpButton* currentBranchPopUpButton;
@property(weak, nonatomic, readonly) NSButton* settingsButton;
@property(weak, nonatomic, readonly) NSSegmentedControl* pullPushControl;
@property(weak, nonatomic, readonly) NSButton* pullButton;
@property(weak, nonatomic, readonly) NSPopUpButton* otherBranchPopUpButton;
@property(weak, nonatomic, readonly) NSSearchField* searchField;
@property(nonatomic, strong) NSMutableArray* openedMenus;

// Unified sync bar: [ local branch ▾ | ← pull | push → | remote branch ▾ ]
@property(nonatomic, strong) NSToolbarItem* syncBarItem;
@property(weak, nonatomic, readonly) NSSegmentedControl* syncBarControl;

// Modern search toolbar item (replaces the XIB-based NSSearchField)
@property(nonatomic, strong) NSSearchToolbarItem* searchToolbarItem;
- (void) updateDisabledState;
- (void) updateBranchMenus;
- (void) updateCurrentBranchMenus;
- (void) updateRemoteBranchMenus;
- (void) updateSyncButtons;
- (BOOL) isMenuOpened;
- (BOOL) isMenuOpened:(NSMenu*)menu;

- (BOOL) validateCheckoutTagMenu:(NSMenuItem*)sender;
- (BOOL) validateCheckoutRemoteBranchMenu:(NSMenuItem*)sender;
@end


@implementation GBRepositoryToolbarController {
	BOOL needsUpdateAfterClosingMenu;
}

@synthesize repositoryController;
@synthesize openedMenus=_openedMenus;

@dynamic currentBranchPopUpButton;
@dynamic pullPushControl;
@dynamic pullButton;
@dynamic otherBranchPopUpButton;
@dynamic searchField;
@dynamic syncBarControl;


- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)init
{
	if ((self = [super init]))
	{
	}
	return self;
}

- (void) setRepositoryController:(GBRepositoryController*)repoCtrl
{
	if (repoCtrl == repositoryController) return;
	
	[repositoryController removeObserverForAllSelectors:self];
	
	repositoryController = repoCtrl;
	
	[repositoryController addObserverForAllSelectors:self];
	
	[self update];
	
	[self.searchField setStringValue:repositoryController.searchString ? repositoryController.searchString : @""];
}

- (BOOL) wantsSettingsButton
{
	return YES;
}




#pragma mark - Controls properties



- (NSPopUpButton*) currentBranchPopUpButton
{
	return (id)[[self toolbarItemForIdentifier:@"GBCurrentBranch"] view];
}

- (NSButton*) settingsButton
{
	return (id)[[self toolbarItemForIdentifier:@"GBSettings"] view];
}

- (NSSegmentedControl*) pullPushControl
{
	return (id)[[self toolbarItemForIdentifier:@"GBPullPush"] view];
}

- (NSButton*) pullButton
{
	return (id)[[self toolbarItemForIdentifier:@"GBPull"] view];
}

- (NSPopUpButton*) otherBranchPopUpButton
{
	return (id)[[self toolbarItemForIdentifier:@"GBOtherBranch"] view];
}

- (NSSearchField*) searchField
{
	return self.searchToolbarItem.searchField;
}

- (NSSearchToolbarItem*) ensureSearchToolbarItem
{
	if (self.searchToolbarItem) return self.searchToolbarItem;

	NSSearchToolbarItem* item = [[NSSearchToolbarItem alloc] initWithItemIdentifier:@"GBSearchBar"];
	item.searchField.recentsAutosaveName = @"GBHistorySearchAutosave";
	item.searchField.placeholderString = NSLocalizedString(@"Search", @"Toolbar");
	item.label = NSLocalizedString(@"Search", @"Toolbar");

	self.searchToolbarItem = item;
	return item;
}

- (NSSegmentedControl*) syncBarControl
{
	return (NSSegmentedControl*)self.syncBarItem.view;
}

- (NSToolbarItem*) ensureSyncBarItem
{
	if (self.syncBarItem) return self.syncBarItem;

	NSSegmentedControl* seg = [NSSegmentedControl new];
	seg.segmentCount = 4;
	seg.segmentStyle = NSSegmentStyleRounded;
	seg.trackingMode = NSSegmentSwitchTrackingMomentary;

	// Segment 0: local branch (menu)
	[seg setLabel:@"main" forSegment:0];
	[seg setWidth:0 forSegment:0]; // auto-size
	[seg setShowsMenuIndicator:YES forSegment:0];
	[seg setMenu:[[NSMenu alloc] init] forSegment:0];

	// Segment 1: pull/rebase
	[seg setLabel:@"← pull" forSegment:1];
	[seg setWidth:0 forSegment:1];

	// Segment 2: push/force (arrow trails the label, so use text not image)
	[seg setLabel:@"push →" forSegment:2];
	[seg setWidth:0 forSegment:2];

	// Segment 3: remote branch (menu)
	[seg setLabel:@"origin/main" forSegment:3];
	[seg setWidth:0 forSegment:3];
	[seg setShowsMenuIndicator:YES forSegment:3];
	[seg setMenu:[[NSMenu alloc] init] forSegment:3];

	seg.target = self;
	seg.action = @selector(syncBarClicked:);

	[seg sizeToFit];

	NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:@"GBSyncBar"];
	item.view = seg;
	item.label = @"";
	item.paletteLabel = @"Sync";
	item.minSize = NSMakeSize(300, 25);
	item.maxSize = NSMakeSize(600, 32);

	self.syncBarItem = item;
	return item;
}

- (IBAction) syncBarClicked:(NSSegmentedControl*)sender
{
	NSInteger segment = sender.selectedSegment;

	if (segment == 0) {
		// Local branch — show menu immediately
		NSMenu* menu = [sender menuForSegment:0];
		if (menu && menu.numberOfItems > 0) {
			NSRect segRect = [self frameOfSegment:0 inControl:sender];
			[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(segRect.origin.x, NSMinY(segRect)) inView:sender];
		}
	} else if (segment == 1) {
		// Pull/rebase/fetch
		NSUInteger modifierFlags = [[NSApp currentEvent] modifierFlags];
		if (modifierFlags & NSAlternateKeyMask) {
			[self.repositoryController fetch:sender];
		} else if ((modifierFlags & NSShiftKeyMask) && (modifierFlags & NSCommandKeyMask)) {
			[self.repositoryController rebase:sender];
		} else {
			[self.repositoryController pull:sender];
		}
	} else if (segment == 2) {
		// Push/force
		NSUInteger modifierFlags = [[NSApp currentEvent] modifierFlags];
		if ((modifierFlags & NSShiftKeyMask) && (modifierFlags & NSCommandKeyMask)) {
			[self.repositoryController forcePush:sender];
		} else {
			[self.repositoryController push:sender];
		}
	} else if (segment == 3) {
		// Remote branch — show menu immediately
		NSMenu* menu = [sender menuForSegment:3];
		if (menu && menu.numberOfItems > 0) {
			NSRect segRect = [self frameOfSegment:3 inControl:sender];
			[menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(segRect.origin.x, NSMinY(segRect)) inView:sender];
		}
	}
}

- (NSRect) frameOfSegment:(NSInteger)segment inControl:(NSSegmentedControl*)control
{
	CGFloat x = 0;
	for (NSInteger i = 0; i < segment; i++) {
		x += [control widthForSegment:i];
		if ([control widthForSegment:i] == 0) {
			// Auto-sized segment — estimate from the label
			NSSize labelSize = [[control labelForSegment:i] sizeWithAttributes:@{NSFontAttributeName: control.font}];
			x += labelSize.width + 24; // padding for menu indicator + margins
		}
	}
	CGFloat w = [control widthForSegment:segment];
	if (w == 0) {
		NSSize labelSize = [[control labelForSegment:segment] sizeWithAttributes:@{NSFontAttributeName: control.font}];
		w = labelSize.width + 24;
	}
	return NSMakeRect(x, 0, w, control.frame.size.height);
}



- (NSToolbarItem*) programmaticToolbarItemForIdentifier:(NSString*)itemIdentifier
{
	if ([itemIdentifier isEqualToString:@"GBSyncBar"]) {
		return [self ensureSyncBarItem];
	}
	if ([itemIdentifier isEqualToString:@"GBSearchBar"]) {
		return [self ensureSearchToolbarItem];
	}
	return [super programmaticToolbarItemForIdentifier:itemIdentifier];
}


#pragma mark - GBRepositoryController notifications



- (void) repositoryControllerDidChangeDisabledStatus:(GBRepositoryController*)repoCtrl
{
	[self update];
}

- (void) repositoryControllerDidChangeSpinningStatus:(GBRepositoryController*)repoCtrl
{
	[self update];
}

- (void) repositoryControllerDidCheckoutBranch:(GBRepositoryController*)repoCtrl
{
	[self update];
}

- (void) repositoryControllerDidChangeRemoteBranch:(GBRepositoryController*)repoCtrl
{
	[self update];
}

- (void) repositoryControllerDidCommit:(GBRepositoryController*)repoCtrl
{
	[self update];
}

- (void) repositoryControllerDidUpdateRefs:(GBRepositoryController*)repoCtrl
{
	[self update];
}

- (void) repositoryControllerSearchDidStart:(GBRepositoryController*)repoCtrl
{
	[self.searchField setStringValue:repoCtrl.searchString ? repoCtrl.searchString : @""];
	[self.searchField setRefusesFirstResponder:NO]; // some cargo cult line appeared when I was trying to make Cmd+F select all text while the field is first responder.
	[self.window makeFirstResponder:self.searchField];
	[self.searchField selectText:nil];
}

- (void) repositoryControllerSearchDidStartRunning:(GBRepositoryController*)repoCtrl
{
	if (self.searchField.stringValue != repoCtrl.searchString && 
		(repoCtrl.searchString &&
		![self.searchField.stringValue isEqualToString:repoCtrl.searchString]))
	{
		[self.searchField setStringValue:repoCtrl.searchString ? repoCtrl.searchString : @""];
		[self.searchField setRefusesFirstResponder:NO]; // some cargo cult line appeared when I was trying to make Cmd+F select all text while the field is first responder.
		[self.window makeFirstResponder:self.searchField];
		[self.searchField selectText:nil];
	}
}

- (void) repositoryControllerSearchDidEnd:(GBRepositoryController*)repoCtrl
{
	[self.searchField setStringValue:@""];
}




#pragma mark - Search delegate and action


- (IBAction)searchFieldDidChange:(id)sender
{
	self.repositoryController.searchString = [self.searchField stringValue];
}


// handling of ESC key
- (BOOL) control:(NSControl*)control textView:(NSTextView*)textView doCommandBySelector:(SEL)commandSelector
{
	NSSearchField* searchField = self.searchField;
	if (control == searchField)
	{
		if (commandSelector == @selector(cancelOperation:))
		{
			[self.repositoryController cancelSearch:self];
			return YES;
		}
		// when Cmd+F is pressed, should select all text.
		// In fact, this code is not executed because of a funny way editor textview surpresses all find panel actions
		if (commandSelector == @selector(performFindPanelAction:))
		{
			[self.searchField selectText:nil];
			return YES;
		}
		
		if (commandSelector == @selector(insertTab:))
		{
			[self.repositoryController notifyWithSelector:@selector(repositoryControllerSearchDidTab:)];
			return YES;
		}    
	}
	return NO;
}



- (void)flagsChanged:(NSEvent *)theEvent
{
	[self updateSyncButtons];
}




#pragma mark - Updates



- (CGFloat) sidebarPadding
{
	return [super sidebarPadding] - ([self wantsSettingsButton] ? 38.0 : 0.0); // compensation for GBSettings button
}

- (void) update
{
	BOOL isSearchFieldFirstResponder = ([self.window firstResponder] && [self.window firstResponder] == [self.searchField currentEditor]);
	
	[super update];
	
	[self appendItemWithIdentifier:@"GBAdd"];
	if ([self wantsSettingsButton])
	{
		[self appendItemWithIdentifier:@"GBSettings"];
	}
	[self appendItemWithIdentifier:NSToolbarFlexibleSpaceItemIdentifier];
	[self appendItemWithIdentifier:@"GBSyncBar"];
	[self appendItemWithIdentifier:NSToolbarFlexibleSpaceItemIdentifier];
	[self appendItemWithIdentifier:@"GBSearchBar"];
	
	NSSearchField* searchField = self.searchField;
	
	[searchField setEnabled:YES];
	
	if (repositoryController)
	{
		[searchField setDelegate:self];
		[searchField setAction:@selector(searchFieldDidChange:)];
		[searchField setTarget:self];
	}
	else if ([searchField delegate] == nil || [searchField delegate] == self)
	{
		[searchField setDelegate:nil];
		[searchField setAction:NULL];
		[searchField setTarget:nil];
	}
	
	[self updateBranchMenus];
	[self updateDisabledState];
	
	if (isSearchFieldFirstResponder)
	{
		[self.window makeFirstResponder:self.searchField];
	}
}

- (void) updateDisabledState
{
	// enabling these buttons because they somehow appear disabled after sheet appearance
	[self.settingsButton setEnabled:YES];
	[self.pullPushControl setEnabled:YES];
	[self.pullButton setEnabled:YES];
	
	//NSLog(@"updateDisabledState: ctrl: %d  isDisabled: %d", (int)(!!self.baseRepositoryController), (int)(!!self.baseRepositoryController.isDisabled));
	BOOL isDisabled = self.repositoryController.isDisabled || !self.repositoryController;
	BOOL isCurrentBranchDisabled = NO; // TODO: get from repo controller
	BOOL isRemoteBranchDisabled  = self.repositoryController && self.repositoryController.isRemoteBranchesDisabled;
	
	isDisabled = isDisabled || (self.repositoryController && [self.repositoryController.repository.localBranches count] < 1);
	
	[self.currentBranchPopUpButton setEnabled:!isDisabled && !isCurrentBranchDisabled];
	[self.otherBranchPopUpButton setEnabled:!isDisabled && !isRemoteBranchDisabled];

	// Sync bar: segment 0 = local branch, segment 3 = remote branch
	NSSegmentedControl* syncBar = self.syncBarControl;
	if (syncBar) {
		[syncBar setEnabled:!isDisabled && !isCurrentBranchDisabled forSegment:0];
		[syncBar setEnabled:!isDisabled && !isRemoteBranchDisabled forSegment:3];
	}

	[self.searchField setEnabled:YES];

	[self updateSyncButtons];
}


- (void) updateSyncButtons
{
	// Update the unified sync bar (segments 1=pull, 2=push)
	NSSegmentedControl* syncBar = self.syncBarControl;
	if (!syncBar) return;

	GBRepository* repo = self.repositoryController.repository;
	NSUInteger modifierFlags = [[NSApp currentEvent] modifierFlags];

	if (repo.currentRemoteBranch && [repo.currentRemoteBranch isLocalBranch])
	{
		[syncBar setLabel:@"← merge" forSegment:1];
		[syncBar setLabel:@"" forSegment:2];
		[syncBar setEnabled:NO forSegment:2];

		if ((modifierFlags & NSShiftKeyMask) && (modifierFlags & NSCommandKeyMask))
		{
			[syncBar setLabel:@"← rebase" forSegment:1];
		}
	}
	else
	{
		[syncBar setLabel:@"← pull" forSegment:1];
		[syncBar setLabel:@"push →" forSegment:2];
		[syncBar setEnabled:YES forSegment:2];

		if (modifierFlags & NSAlternateKeyMask)
		{
			[syncBar setLabel:@"← fetch" forSegment:1];
		}
		else if ((modifierFlags & NSShiftKeyMask) && (modifierFlags & NSCommandKeyMask))
		{
			[syncBar setLabel:@"← rebase" forSegment:1];
			[syncBar setLabel:@"force →" forSegment:2];
		}
	}

	[syncBar setEnabled:[self.repositoryController validatePull:nil] forSegment:1];
	BOOL canPush = [self.repositoryController validatePush:nil];
	if (!(repo.currentRemoteBranch && [repo.currentRemoteBranch isLocalBranch])) {
		[syncBar setEnabled:canPush forSegment:2];
	}

	[syncBar sizeToFit];
	self.syncBarItem.minSize = syncBar.fittingSize;
	self.syncBarItem.maxSize = NSMakeSize(syncBar.fittingSize.width + 50, 32);
}






- (void) updateBranchMenus
{
	[self updateCurrentBranchMenus];
	[self updateRemoteBranchMenus];
	[self updateSyncButtons];
}


- (void) updateCurrentBranchMenus
{
	GBRepository* repo = self.repositoryController.repository;
	
	NSPopUpButton* button = self.currentBranchPopUpButton;
	
	if ([self isMenuOpened:button.menu])
	{
		needsUpdateAfterClosingMenu = YES;
		return;
	}
	
	// Local branches
	//NSMenu* newMenu = [NSMenu menu];
	NSMenu* currentBranchesMenu = button.menu;
	if (!currentBranchesMenu) currentBranchesMenu = [NSMenu menu];
	currentBranchesMenu.delegate = self;
	[currentBranchesMenu removeAllItems];
	
	if ([button pullsDown])
	{
		// Note: this is needed according to documentation for pull-down menus. The item will be ignored.
		[currentBranchesMenu addItem:[NSMenuItem menuItemWithTitle:@"" submenu:nil]];
	}
	
	if (!repo)
	{
		[button setMenu:currentBranchesMenu];
		[button setEnabled:NO];
		//NSLog(@"Toolbar: disabling branch menu because repo is nil.");
		return;
	}
	
	if ([repo.localBranches count] < 1)
	{
		[button setMenu:currentBranchesMenu];
		[button setEnabled:NO];
		[button setTitle:NSLocalizedString(@"", @"Toolbar")];
		//NSLog(@"Toolbar: disabling branch menu because branches count is 0");
		return;    
	}
	
	for (GBRef* localBranch in repo.localBranches)
	{
		NSMenuItem* item = [NSMenuItem new];
		[item setTitle:localBranch.name];
		[item setAction:@selector(checkoutBranch:)];
		[item setTarget:nil];
		[item setRepresentedObject:localBranch];
		if ([localBranch.name isEqual:repo.currentLocalRef.name])
		{
			[item setState:NSOnState];
		}
		[currentBranchesMenu addItem:item];
	}
	
	[currentBranchesMenu addItem:[NSMenuItem separatorItem]];
	
	
	// Checkout Tag
	
	if ([repo.tags count] > 0)
	{
		NSMenuItem* item = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"Checkout Tag", @"Command") action:nil];
		[currentBranchesMenu addItem:item];
		[self validateCheckoutTagMenu:item];
	}
	
	
	// Checkout Remote Branch
	
	BOOL hasOneRemoteBranch = NO;
	for (GBRemote* remote in repo.remotes)
	{
		if ([remote.branches count] > 0)
		{
			hasOneRemoteBranch = YES;
		}
	}
	if (hasOneRemoteBranch)
	{
		NSMenuItem* item = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"Checkout Remote Branch", @"Command") action:nil];
		[currentBranchesMenu addItem:item];
		[self validateCheckoutRemoteBranchMenu:item];
	}
	
	
	
	// Checkout Commit
	
	{
		NSMenuItem* item = [NSMenuItem new];
		[item setTitle:NSLocalizedString(@"Checkout Commit...", @"Command")];
		[item setAction:@selector(checkoutCommit:)];
		[item setTarget:self];
		
		[currentBranchesMenu addItem:item];
	}
	
	
	[currentBranchesMenu addItem:[NSMenuItem separatorItem]];
	
	
	// Create and edit branches and tags
	
	[currentBranchesMenu addItem:[NSMenuItem menuItemWithTitle:NSLocalizedString(@"New Tag...", @"Command") action:@selector(newTag:)]];
	[currentBranchesMenu addItem:[NSMenuItem menuItemWithTitle:NSLocalizedString(@"New Branch...", @"Command") action:@selector(newBranch:)]];  
	[currentBranchesMenu addItem:[NSMenuItem separatorItem]];
	[currentBranchesMenu addItem:[NSMenuItem menuItemWithTitle:NSLocalizedString(@"Edit Branches and Tags...", @"Command") action:@selector(editBranchesAndTags:)]];  
	
	
	// Select current branch
	
	//[button setMenu:newMenu];
	for (NSMenuItem* item in [currentBranchesMenu itemArray])
	{
		if (item.representedObject == repo.currentLocalRef)
		{
			[button selectItem:item];
		}
	}
	
	// If no branch is found the name could be empty.
	// I make sure that the name is set nevertheless.
	NSString* title = [repo.currentLocalRef displayName];
	if (title) [button setTitle:title];

	// Update sync bar segment 0 (local branch label + menu)
	NSSegmentedControl* syncBar = self.syncBarControl;
	if (syncBar) {
		if (title) [syncBar setLabel:title forSegment:0];
		[syncBar setMenu:currentBranchesMenu forSegment:0];
		[syncBar sizeToFit];
		self.syncBarItem.minSize = syncBar.fittingSize;
		self.syncBarItem.maxSize = NSMakeSize(syncBar.fittingSize.width + 50, 32);
	}
}










- (void) updateRemoteBranchMenus
{
	GBRepository* repo = self.repositoryController.repository;
	NSArray* remotes = repo.remotes;
	
	NSPopUpButton* button = self.otherBranchPopUpButton;
	
	if ([self isMenuOpened:button.menu])
	{
		needsUpdateAfterClosingMenu = YES;
		return;
	}
	
	NSMenu* remoteBranchesMenu = button.menu ? button.menu : [NSMenu menu];
	[button.menu removeAllItems];
	remoteBranchesMenu.delegate = self;
	
	if ([button pullsDown])
	{
		// Note: this is needed according to documentation for pull-down menus. The item will be ignored.
		[remoteBranchesMenu addItem:[NSMenuItem menuItemWithTitle:@"" submenu:nil]];
	}
	
	if ([remotes count] > 1) // display submenus for each remote
	{
		NSMenuItem* item = [NSMenuItem new];
		[item setTitle:NSLocalizedString(@"Remote Branches", @"Toolbar")];
		[item setAction:@selector(thisItemIsActuallyDisabled)];
		[item setEnabled:NO];
		[remoteBranchesMenu addItem:item];
		
		for (GBRemote* remote in remotes)
		{
			NSMenu* remoteMenu = [NSMenu new];
			BOOL haveBranches = NO;
			for (GBRef* branch in [remote pushedAndNewBranches])
			{
				NSMenuItem* item = [NSMenuItem new];
				[item setTitle:branch.name];
				[item setAction:@selector(selectRemoteBranch:)];
				[item setTarget:self];
				[item setRepresentedObject:branch];
				if (branch == repo.currentRemoteBranch)
				{
					[item setState:NSOnState];
				}
				[remoteMenu addItem:item];
				haveBranches = YES;
			}
			if (haveBranches) [remoteMenu addItem:[NSMenuItem separatorItem]];
			
			NSMenuItem* newBranchItem = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"New Remote Branch...", @"Command") submenu:nil];
			[newBranchItem setAction:@selector(createNewRemoteBranch:)];
			[newBranchItem setTarget:self];
			[newBranchItem setRepresentedObject:remote];
			[remoteMenu addItem:newBranchItem];
			
			NSMenuItem* item = [NSMenuItem menuItemWithTitle:remote.alias submenu:remoteMenu];
			[item setIndentationLevel:1];
			[remoteBranchesMenu addItem:item];
		}
	}
	else if ([remotes count] == 1) // display a flat list of "origin/master"-like titles
	{
		NSMenuItem* item = [NSMenuItem new];
		[item setTitle:NSLocalizedString(@"Remote Branches", @"Toolbar")];
		[item setAction:@selector(thisItemIsActuallyDisabled)];
		[item setEnabled:NO];
		[remoteBranchesMenu addItem:item];
		
		GBRemote* remote = [remotes firstObject];
		for (GBRef* branch in [remote pushedAndNewBranches])
		{
			NSMenuItem* item = [NSMenuItem new];
			[item setIndentationLevel:1];
			[item setTitle:[branch nameWithRemoteAlias]];
			[item setAction:@selector(selectRemoteBranch:)];
			[item setTarget:self];
			[item setRepresentedObject:branch];
			if (branch == repo.currentRemoteBranch)
			{
				[item setState:NSOnState];
			}
			[remoteBranchesMenu addItem:item];
		}
		
		
		
		NSMenuItem* newBranchItem = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"New Remote Branch...", @"Command") submenu:nil];
		[newBranchItem setIndentationLevel:1];
		[newBranchItem setAction:@selector(createNewRemoteBranch:)];
		[newBranchItem setTarget:self];
		[newBranchItem setRepresentedObject:remote];
		
		[remoteBranchesMenu addItem:[NSMenuItem separatorItem]];
		[remoteBranchesMenu addItem:newBranchItem];
	}
	
	// Add new remote
	
	BOOL isEmptyMenu = NO;
	
	if (remoteBranchesMenu.itemArray.count <= 1) // ignore dummy item
	{
		isEmptyMenu = YES;
		NSMenuItem* newRemoteItem = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"Add Server...", @"Command") submenu:nil];
		[newRemoteItem setAction:@selector(editRemotes:)];
		[newRemoteItem setTarget:nil];
		[newRemoteItem setRepresentedObject:nil];
		[remoteBranchesMenu addItem:newRemoteItem];
	}
	
	
	// Local branch for merging
	
	// We display local branches in two cases:
	// 1. We have more than one local branch.
	// 2. Or we are not on any branch right now.
	
	if (repo.localBranches.count > 1 || !repo.currentLocalRef.name)
	{
		if (remoteBranchesMenu.itemArray.count > 1) // ignore dummy item
		{
			[remoteBranchesMenu addItem:[NSMenuItem separatorItem]];
		}
		
		NSMenuItem* item = [NSMenuItem new];
		[item setTitle:NSLocalizedString(@"Local Branches", @"Toolbar")];
		[item setAction:@selector(thisItemIsActuallyDisabled)];
		[item setEnabled:NO];
		[remoteBranchesMenu addItem:item];
		
		for (GBRef* localBranch in repo.localBranches)
		{
			NSMenuItem* item = [NSMenuItem new];
			[item setIndentationLevel:1];
			[item setTitle:localBranch.name];
			[item setAction:@selector(selectRemoteBranch:)];
			[item setTarget:self];
			[item setRepresentedObject:localBranch];
			if (localBranch == repo.currentRemoteBranch)
			{
				[item setState:NSOnState];
			}
			if (localBranch == repo.currentLocalRef)
			{
				[item setEnabled:NO];
				[item setAction:@selector(thisItemIsActuallyDisabled)];
				[item setTarget:nil];
				[item setRepresentedObject:nil];
			}      
			[remoteBranchesMenu addItem:item];
		}
	} // if > 1 local branches
	
	if (!isEmptyMenu)
	{
		[remoteBranchesMenu addItem:[NSMenuItem separatorItem]];
		
		NSMenuItem* item = nil;
		
		item = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"Edit Branches...", @"Command") action:@selector(editBranchesAndTags:)];
		item.indentationLevel = 1;
		[remoteBranchesMenu addItem:item];
		item = [NSMenuItem menuItemWithTitle:NSLocalizedString(@"Edit Servers...", @"Command") action:@selector(editRemotes:)];
		item.indentationLevel = 1;
		[remoteBranchesMenu addItem:item];
	}
	
	
	// Finish with a button for the menu
	
	//NSLog(@"Updated remote branches menu!");
	//[button setMenu:remoteBranchesMenu];
	
	GBRef* remoteBranch = repo.currentRemoteBranch;
	if (remoteBranch)
	{
		[button setTitle:[remoteBranch nameWithRemoteAlias]];
	}
	else
	{
		[button setTitle:NSLocalizedString(@"", @"Toolbar")];
	}

	// Update sync bar segment 3 (remote branch label + menu)
	NSSegmentedControl* syncBar = self.syncBarControl;
	if (syncBar) {
		NSString* remoteTitle = remoteBranch ? [remoteBranch nameWithRemoteAlias] : @"";
		[syncBar setLabel:remoteTitle forSegment:3];
		[syncBar setMenu:remoteBranchesMenu forSegment:3];
		[syncBar sizeToFit];
		self.syncBarItem.minSize = syncBar.fittingSize;
		self.syncBarItem.maxSize = NSMakeSize(syncBar.fittingSize.width + 50, 32);
	}
}






#pragma mark - NSMenuDelegate


- (void)menuWillOpen:(NSMenu *)menu
{
	if (!self.openedMenus) self.openedMenus = [NSMutableArray array];
	[self.openedMenus addObject:menu];
	//NSLog(@"   > Opened menu.");
}

- (void)menuDidClose:(NSMenu *)menu
{
	//NSLog(@"   < Closed menu.");
	[self.openedMenus removeObject:menu];
	if (needsUpdateAfterClosingMenu)
	{
		needsUpdateAfterClosingMenu = NO;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updateBranchMenus];
		});
	}
}



- (BOOL) isMenuOpened
{
	return self.openedMenus.count > 0;
}

- (BOOL) isMenuOpened:(NSMenu*)menu
{
	if (!menu) return NO;
	return [self.openedMenus containsObject:menu];
}





#pragma mark - IBActions



- (IBAction) pullOrPush:(id)sender
{
	NSInteger segment = 0;
	
	if ([sender isKindOfClass:[NSSegmentedControl class]])
	{
		segment = [(NSSegmentedControl*)sender selectedSegment];
	}
	
	if (segment == 0)
	{
		NSUInteger modifierFlags = [[NSApp currentEvent] modifierFlags];
		if (modifierFlags & NSAlternateKeyMask)
		{
			[self.repositoryController fetch:sender];
		}
		else if ((modifierFlags & NSShiftKeyMask) && (modifierFlags & NSCommandKeyMask))
		{
			[self.repositoryController rebase:sender];
		}
		else
		{
			[self.repositoryController pull:sender];
		}
	}
	else if (segment == 1)
	{
		NSUInteger modifierFlags = [[NSApp currentEvent] modifierFlags];
		if ((modifierFlags & NSShiftKeyMask) && (modifierFlags & NSCommandKeyMask))
		{
			[self.repositoryController forcePush:sender];
		}
		else
		{
			[self.repositoryController push:sender];
		}
	}
	else
	{
		NSLog(@"ERROR: Unrecognized push/pull segment %d", (int)segment);
	}
}



- (IBAction) checkoutBranch:(NSMenuItem*)sender
{
	[self.repositoryController checkoutRef:[sender representedObject]];
}

- (IBAction) checkoutRemoteBranch:(id)sender
{
	GBRef* remoteBranch = [sender representedObject];
	NSString* defaultName = [remoteBranch.name uniqueStringForStrings:[self.repositoryController.repository.localBranches valueForKey:@"name"]];
	
	GBPromptController* ctrl = [GBPromptController controller];
	
	ctrl.title = NSLocalizedString(@"Remote Branch Checkout", @"");
	ctrl.promptText = NSLocalizedString(@"Branch Name:", @"");
	ctrl.buttonText = NSLocalizedString(@"Checkout", @"");
	ctrl.value = defaultName;
	ctrl.requireSingleLine = YES;
	ctrl.requireStripWhitespace = YES;
	ctrl.completionHandler = ^(BOOL cancelled){
		if (!cancelled) [self.repositoryController checkoutRef:remoteBranch withNewName:ctrl.value];
	};
	[ctrl presentSheetInMainWindow];
}

- (IBAction) newBranch:(id)sender
{
	GBPromptController* ctrl = [GBPromptController controller];
	GBCommit* aCommit = [self.repositoryController contextCommit];
	
	ctrl.title = NSLocalizedString(@"New Branch", @"");
	ctrl.promptText = NSLocalizedString(@"Branch Name:", @"");
	ctrl.buttonText = NSLocalizedString(@"OK", @"");
	ctrl.requireSingleLine = YES;
	ctrl.requireStripWhitespace = YES;
	ctrl.completionHandler = ^(BOOL cancelled){
		if (!cancelled) [self.repositoryController checkoutNewBranchWithName:ctrl.value commit:aCommit];
	};
	[ctrl presentSheetInMainWindow];
}

- (BOOL) validateNewBranch:(id)sender
{
	return !![self.repositoryController contextCommit];
}


- (IBAction) checkoutCommit:(id)sender
{
	GBPromptController* ctrl = [GBPromptController controller];
	
	ctrl.title = NSLocalizedString(@"Checkout Commit", @"");
	
	GBCommit* aCommit = self.repositoryController.selectedCommit;
	if (aCommit.commitId)
	{
		ctrl.value = aCommit.commitId;
	}
	
	ctrl.promptText = NSLocalizedString(@"Commit ID:", @"");
	ctrl.buttonText = NSLocalizedString(@"Checkout", @"");
	ctrl.requireSingleLine = YES;
	ctrl.requireStripWhitespace = YES;
	ctrl.completionHandler = ^(BOOL cancelled){
		if (!cancelled) [self.repositoryController checkoutRef:[GBRef refWithCommitId:ctrl.value]];
	};
	[ctrl presentSheetInMainWindow];
}


- (IBAction) selectRemoteBranch:(id)sender
{
	GBRef* remoteBranch = [sender representedObject];
	
	if (remoteBranch && self.repositoryController.repository.currentRemoteBranch == remoteBranch)
	{
		remoteBranch = nil; // reset branch if selected current branch
	}
	
	[self.repositoryController selectRemoteBranch:remoteBranch];
}

- (IBAction) createNewRemoteBranch:(id)sender
{
	GBPromptController* ctrl = [GBPromptController controller];
	
	GBRemote* remote = [sender representedObject];
	NSString* defaultName = [self.repositoryController.repository.currentLocalRef.name 
							 uniqueStringForStrings:[[remote pushedAndNewBranches] valueForKey:@"name"]];
	
	ctrl.title = NSLocalizedString(@"New Remote Branch", @"");
	ctrl.promptText = NSLocalizedString(@"Branch Name:", @"");
	ctrl.buttonText = NSLocalizedString(@"OK", @"");
	ctrl.requireSingleLine = YES;
	ctrl.requireStripWhitespace = YES;
	ctrl.value = defaultName;
	ctrl.completionHandler = ^(BOOL cancelled){
		if (!cancelled) [self.repositoryController createAndSelectRemoteBranchWithName:ctrl.value remote:remote];
	};
	[ctrl presentSheetInMainWindow];
}

- (IBAction) quickCheckout:(id)sender
{
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.currentBranchPopUpButton.superview)
		{
			NSPopUpButtonCell* cell = self.currentBranchPopUpButton.cell;
			[cell performClickWithFrame:self.currentBranchPopUpButton.frame inView:self.currentBranchPopUpButton.superview];
		}
	});
}


- (IBAction) checkoutBranchMenu:(NSMenuItem*)sender
{
	// noop method to trigger validation callbacks
}

- (IBAction) checkoutRemoteBranchMenu:(NSMenuItem*)sender
{
	// noop method to trigger validation callbacks
}

- (IBAction) checkoutTagMenu:(NSMenuItem*)sender
{
	// noop method to trigger validation callbacks
}

// Used by main menu
- (BOOL) validateCheckoutBranchMenu:(NSMenuItem*)sender
{
	[sender setSubmenu:[NSMenu menuWithTitle:[sender title]]];
	
	NSMenu* aMenu = [sender submenu];
	GBRepository* repo = self.repositoryController.repository;
	BOOL hasOneItem = NO;
	for (GBRef* localBranch in repo.localBranches)
	{
		NSMenuItem* item = [NSMenuItem new];
		[item setTitle:localBranch.name];
		[item setAction:@selector(checkoutBranch:)];
		[item setRepresentedObject:localBranch];
		if ([localBranch.name isEqual:repo.currentLocalRef.name])
		{
			[item setState:NSOnState];
		}
		[aMenu addItem:item];
		hasOneItem = YES;
	}
	
	return hasOneItem;
}

// Used by main menu
- (BOOL) validateCheckoutRemoteBranchMenu:(NSMenuItem*)sender
{
	[sender setSubmenu:[NSMenu menuWithTitle:[sender title]]];
	NSMenu* aMenu = [sender submenu];
	GBRepository* repo = self.repositoryController.repository;
	BOOL hasOneItem = NO;
	
	if ([repo.remotes count] > 1) // display submenus for each remote
	{
		for (GBRemote* remote in repo.remotes)
		{
			if (remote.branches.count > 0)
			{
				NSMenu* remoteMenu = [NSMenu new];
				for (GBRef* branch in remote.branches)
				{
					if ([repo doesRefExist:branch])
					{
						NSMenuItem* item = [NSMenuItem new];
						[item setTitle:branch.name];
						[item setAction:@selector(checkoutRemoteBranch:)];
						[item setTarget:self];
						[item setRepresentedObject:branch];
						[remoteMenu addItem:item];
						hasOneItem = YES;
					}
				}
				[aMenu addItem:[NSMenuItem menuItemWithTitle:remote.alias submenu:remoteMenu]];
			}
		}
	}
	else if ([repo.remotes count] == 1) // display a flat list of "origin/master"-like titles
	{
		for (GBRef* branch in [[repo.remotes firstObject] branches])
		{
			if ([repo doesRefExist:branch])
			{
				NSMenuItem* item = [NSMenuItem new];
				[item setTitle:[branch nameWithRemoteAlias]];
				[item setAction:@selector(checkoutRemoteBranch:)];
				[item setTarget:self];
				[item setRepresentedObject:branch];    
				[aMenu addItem:item];
				hasOneItem = YES;
			}
		}
	}
	return hasOneItem;
}

// Used by main menu
- (BOOL) validateCheckoutTagMenu:(NSMenuItem*)sender
{
	[sender setSubmenu:[NSMenu menuWithTitle:[sender title]]];
	NSMenu* aMenu = [sender submenu];
	[aMenu removeAllItems];
	GBRepository* repo = self.repositoryController.repository;
	BOOL hasOneItem = NO;
	for (GBRef* tag in repo.tags)
	{
		NSMenuItem* item = [NSMenuItem new];
		[item setTitle:tag.name];
		[item setAction:@selector(checkoutBranch:)];
		[item setTarget:self];
		[item setRepresentedObject:tag];
		if ([tag.name isEqual:repo.currentLocalRef.name] && repo.currentLocalRef.isTag)
		{
			[item setState:NSOnState];
		}
		[aMenu addItem:item];
		hasOneItem = YES;
	}
	
	return hasOneItem;
}


@end
