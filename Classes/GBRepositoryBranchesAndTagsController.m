#import "GBRepository.h"
#import "GBRemote.h"
#import "GBRef.h"
#import "GBRepositoryBranchesAndTagsController.h"

@interface GBRepositoryBranchesAndTagsController () <NSTableViewDelegate>

@property(nonatomic, strong) NSArrayController* branchesController;
@property(nonatomic, strong) NSArrayController* tagsController;
@property(nonatomic, strong) NSArrayController* remoteBranchesController;

@property(nonatomic, weak)   NSTableView* branchesTable;
@property(nonatomic, weak)   NSTableView* tagsTable;
@property(nonatomic, weak)   NSTableView* remoteBranchesTable;

@property(nonatomic, weak)   NSTextField* branchesFooterLabel;
@property(nonatomic, weak)   NSTextField* tagsFooterLabel;
@property(nonatomic, weak)   NSTextField* remoteBranchesFooterLabel;

@property(nonatomic, strong) NSMutableArray* branchesToDelete;
@property(nonatomic, strong) NSMutableArray* tagsToDelete;
@property(nonatomic, strong) NSMutableArray* remoteBranchesToDelete;

@end

@implementation GBRepositoryBranchesAndTagsController

- (id) initWithRepository:(GBRepository*)repo
{
	if ((self = [super initWithRepository:repo]))
	{
		self.branchesBinding       = [NSMutableArray array];
		self.tagsBinding           = [NSMutableArray array];
		self.remoteBranchesBinding = [NSMutableArray array];

		self.branchesToDelete       = [NSMutableArray array];
		self.tagsToDelete           = [NSMutableArray array];
		self.remoteBranchesToDelete = [NSMutableArray array];
	}
	return self;
}

- (NSString*) title
{
	return NSLocalizedString(@"Branches and Tags", @"");
}

- (void) loadView
{
	NSView* container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 680, 400)];
	container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	// Three array controllers, one per list
	self.branchesController       = [self makeArrayControllerBoundTo:@"branchesBinding"];
	self.tagsController           = [self makeArrayControllerBoundTo:@"tagsBinding"];
	self.remoteBranchesController = [self makeArrayControllerBoundTo:@"remoteBranchesBinding"];

	NSView* branchesColumn = [self makeColumnWithTitle:NSLocalizedString(@"Local Branches", @"")
												 keyPath:@"arrangedObjects.name"
									   arrayController:self.branchesController
									   deleteSelector:@selector(deleteBranch:)
											tableOut:&_branchesTable
									   footerLabelOut:&_branchesFooterLabel];

	NSView* tagsColumn = [self makeColumnWithTitle:NSLocalizedString(@"Tags", @"")
											  keyPath:@"arrangedObjects.name"
									arrayController:self.tagsController
									 deleteSelector:@selector(deleteTag:)
										 tableOut:&_tagsTable
									footerLabelOut:&_tagsFooterLabel];

	NSView* remoteBranchesColumn = [self makeColumnWithTitle:NSLocalizedString(@"Remote Branches", @"")
														keyPath:@"arrangedObjects.nameWithRemoteAlias"
											  arrayController:self.remoteBranchesController
											   deleteSelector:@selector(deleteRemoteBranch:)
													tableOut:&_remoteBranchesTable
											   footerLabelOut:&_remoteBranchesFooterLabel];

	NSStackView* row = [NSStackView stackViewWithViews:@[ branchesColumn, tagsColumn, remoteBranchesColumn ]];
	row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	row.distribution = NSStackViewDistributionFillEqually;
	row.spacing = 16;
	row.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:row];

	[NSLayoutConstraint activateConstraints:@[
		[row.topAnchor      constraintEqualToAnchor:container.topAnchor      constant:20],
		[row.leadingAnchor  constraintEqualToAnchor:container.leadingAnchor  constant:20],
		[row.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-20],
		[row.bottomAnchor   constraintEqualToAnchor:container.bottomAnchor   constant:-20],
	]];

	self.view = container;
}

- (NSArrayController*) makeArrayControllerBoundTo:(NSString*)keyPath
{
	NSArrayController* ac = [[NSArrayController alloc] init];
	ac.objectClass = [GBRef class];
	ac.editable = NO;
	ac.selectsInsertedObjects = NO;
	ac.avoidsEmptySelection = NO;
	[ac bind:NSContentArrayBinding toObject:self withKeyPath:keyPath options:nil];
	return ac;
}

- (NSView*) makeColumnWithTitle:(NSString*)title
						 keyPath:(NSString*)columnKeyPath
				 arrayController:(NSArrayController*)ac
				  deleteSelector:(SEL)deleteSelector
						tableOut:(NSTableView* __weak *)tableOut
				  footerLabelOut:(NSTextField* __weak *)footerLabelOut
{
	NSView* column = [[NSView alloc] init];
	column.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextField* header = [NSTextField labelWithString:title];
	header.translatesAutoresizingMaskIntoConstraints = NO;

	// Table inside scroll view
	NSScrollView* scroll = [[NSScrollView alloc] init];
	scroll.hasVerticalScroller = YES;
	scroll.autohidesScrollers = YES;
	scroll.borderType = NSNoBorder;
	scroll.wantsLayer = YES;
	scroll.layer.borderColor = [NSColor quaternaryLabelColor].CGColor;
	scroll.layer.borderWidth = 1;
	scroll.translatesAutoresizingMaskIntoConstraints = NO;

	NSTableView* table = [[NSTableView alloc] init];
	table.headerView = nil;
	table.gridStyleMask = NSTableViewGridNone;
	table.intercellSpacing = NSMakeSize(0, 0);
	table.style = NSTableViewStylePlain;
	table.usesAlternatingRowBackgroundColors = NO;
	table.allowsMultipleSelection = YES;
	table.delegate = self;
	table.translatesAutoresizingMaskIntoConstraints = NO;

	NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	col.editable = NO;
	col.resizingMask = NSTableColumnAutoresizingMask;
	NSCell* cell = [[NSTextFieldCell alloc] initTextCell:@""];
	[(NSTextFieldCell*)cell setLineBreakMode:NSLineBreakByTruncatingTail];
	col.dataCell = cell;
	[table addTableColumn:col];
	[col bind:NSValueBinding toObject:ac withKeyPath:columnKeyPath options:nil];

	scroll.documentView = table;

	// Footer: small bordered minus button + "Delete X" label
	NSButton* minusButton = [[NSButton alloc] init];
	minusButton.bezelStyle = NSBezelStyleSmallSquare;
	minusButton.bordered = YES;
	minusButton.image = [NSImage imageWithSystemSymbolName:@"minus" accessibilityDescription:nil];
	minusButton.imagePosition = NSImageOnly;
	minusButton.target = self;
	minusButton.action = deleteSelector;
	minusButton.translatesAutoresizingMaskIntoConstraints = NO;
	[minusButton bind:NSEnabledBinding toObject:ac withKeyPath:@"canRemove" options:nil];

	NSTextField* footerLabel = [NSTextField labelWithString:@""];
	footerLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
	footerLabel.textColor = [NSColor secondaryLabelColor];
	footerLabel.translatesAutoresizingMaskIntoConstraints = NO;

	NSStackView* footer = [NSStackView stackViewWithViews:@[ minusButton, footerLabel ]];
	footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
	footer.spacing = 6;
	footer.alignment = NSLayoutAttributeCenterY;
	footer.translatesAutoresizingMaskIntoConstraints = NO;

	[column addSubview:header];
	[column addSubview:scroll];
	[column addSubview:footer];

	[NSLayoutConstraint activateConstraints:@[
		[header.topAnchor      constraintEqualToAnchor:column.topAnchor],
		[header.leadingAnchor  constraintEqualToAnchor:column.leadingAnchor],
		[header.trailingAnchor constraintLessThanOrEqualToAnchor:column.trailingAnchor],

		[scroll.topAnchor      constraintEqualToAnchor:header.bottomAnchor constant:6],
		[scroll.leadingAnchor  constraintEqualToAnchor:column.leadingAnchor],
		[scroll.trailingAnchor constraintEqualToAnchor:column.trailingAnchor],
		[scroll.bottomAnchor   constraintEqualToAnchor:footer.topAnchor constant:-8],

		[footer.leadingAnchor  constraintEqualToAnchor:column.leadingAnchor],
		[footer.bottomAnchor   constraintEqualToAnchor:column.bottomAnchor],

		[minusButton.widthAnchor  constraintEqualToConstant:22],
		[minusButton.heightAnchor constraintEqualToConstant:22],
	]];

	if (tableOut)       *tableOut       = table;
	if (footerLabelOut) *footerLabelOut = footerLabel;
	return column;
}

- (void) viewDidLoad
{
	[super viewDidLoad];

	self.branchesBinding = [self.repository.localBranches mutableCopy];
	self.tagsBinding     = [self.repository.tags mutableCopy];

	NSMutableArray* rs = [NSMutableArray array];
	for (GBRemote* remote in self.repository.remotes)
	{
		[rs addObjectsFromArray:remote.branches];
	}
	self.remoteBranchesBinding = rs;

	[self updateFooterLabels];
}

- (void) updateFooterLabels
{
	NSUInteger b = self.branchesController.selectedObjects.count;
	self.branchesFooterLabel.stringValue = (b > 1)
		? NSLocalizedString(@"Delete Branches", @"")
		: NSLocalizedString(@"Delete Branch", @"");

	NSUInteger t = self.tagsController.selectedObjects.count;
	self.tagsFooterLabel.stringValue = (t > 1)
		? NSLocalizedString(@"Delete Tags", @"")
		: NSLocalizedString(@"Delete Tag", @"");

	NSUInteger r = self.remoteBranchesController.selectedObjects.count;
	self.remoteBranchesFooterLabel.stringValue = (r > 1)
		? NSLocalizedString(@"Delete Branches", @"")
		: NSLocalizedString(@"Delete Branch", @"");
}

- (void) cancel
{
	self.branchesToDelete       = [NSMutableArray array];
	self.tagsToDelete           = [NSMutableArray array];
	self.remoteBranchesToDelete = [NSMutableArray array];
}

- (void) save
{
	[self.repository removeRemoteRefs:[self.remoteBranchesToDelete arrayByAddingObjectsFromArray:self.tagsToDelete] withBlock:^{
		[self.repository removeRefs:[self.branchesToDelete arrayByAddingObjectsFromArray:self.tagsToDelete] withBlock:^{
			self.branchesToDelete       = [NSMutableArray array];
			self.tagsToDelete           = [NSMutableArray array];
			self.remoteBranchesToDelete = [NSMutableArray array];
		}];
	}];
}

- (IBAction) deleteBranch:(id)sender
{
	self.dirty = YES;
	[self.branchesToDelete addObjectsFromArray:[self.branchesController selectedObjects]];
	[self.branchesController remove:sender];
}

- (IBAction) deleteTag:(id)sender
{
	self.dirty = YES;
	[self.tagsToDelete addObjectsFromArray:[self.tagsController selectedObjects]];
	[self.tagsController remove:sender];
}

- (IBAction) deleteRemoteBranch:(id)sender
{
	self.dirty = YES;
	[self.remoteBranchesToDelete addObjectsFromArray:[self.remoteBranchesController selectedObjects]];
	[self.remoteBranchesController remove:sender];
}


#pragma mark NSTableViewDelegate


- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	[self updateFooterLabels];
}


@end
