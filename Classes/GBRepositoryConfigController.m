#import "GBRepository.h"
#import "GBRepositoryConfigController.h"

@interface GBRepositoryConfigController ()
@property(nonatomic, strong) NSTextView* configTextView;
@property(nonatomic, copy)   NSString*   contents;
@end

@implementation GBRepositoryConfigController

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString*) title
{
	return NSLocalizedString(@"Advanced", @"");
}

- (void) loadView
{
	NSView* container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	NSTextField* label = [NSTextField labelWithString:NSLocalizedString(@"Git configuration (.git/config)", @"")];
	label.translatesAutoresizingMaskIntoConstraints = NO;
	[container addSubview:label];

	NSScrollView* scroll = [[NSScrollView alloc] init];
	scroll.hasVerticalScroller = YES;
	scroll.borderType = NSNoBorder;
	scroll.wantsLayer = YES;
	scroll.layer.borderColor = [NSColor quaternaryLabelColor].CGColor;
	scroll.layer.borderWidth = 1;
	scroll.translatesAutoresizingMaskIntoConstraints = NO;

	NSTextView* textView = [[NSTextView alloc] init];
	textView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
	textView.richText = NO;
	textView.automaticQuoteSubstitutionEnabled = NO;
	textView.automaticDashSubstitutionEnabled = NO;
	textView.automaticSpellingCorrectionEnabled = NO;
	textView.automaticTextReplacementEnabled = NO;
	textView.textContainerInset = NSMakeSize(8, 8);
	textView.autoresizingMask = NSViewWidthSizable;
	textView.minSize = NSMakeSize(0, 0);
	textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
	textView.verticallyResizable = YES;
	textView.horizontallyResizable = NO;
	textView.textContainer.containerSize = NSMakeSize(0, CGFLOAT_MAX);
	textView.textContainer.widthTracksTextView = YES;

	scroll.documentView = textView;
	[container addSubview:scroll];

	self.configTextView = textView;

	CGFloat inset = 20;
	[NSLayoutConstraint activateConstraints:@[
		[label.topAnchor constraintEqualToAnchor:container.topAnchor constant:inset],
		[label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:inset],
		[label.trailingAnchor constraintLessThanOrEqualToAnchor:container.trailingAnchor constant:-inset],

		[scroll.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:8],
		[scroll.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:inset],
		[scroll.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-inset],
		[scroll.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-inset],
	]];

	self.view = container;
}

- (void) viewDidLoad
{
	[super viewDidLoad];

	NSError* error = nil;
	self.contents = [NSString stringWithContentsOfFile:[self.repository.path stringByAppendingPathComponent:@".git/config"] encoding:NSUTF8StringEncoding error:&error];

	if (!self.contents)
	{
		NSLog(@"GBRepositoryConfigController: Error while reading .git/config: %@", error);
	}
	else
	{
		[self.configTextView setString:[self.contents copy]];
	}

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(didUpdateText:)
												 name:NSTextDidChangeNotification
											   object:self.configTextView];
}

- (void) didUpdateText:(NSNotification*)notif
{
	self.dirty = YES;
}

- (void) save
{
	NSError* error = nil;
	NSString* config = [self.configTextView.string copy];

	// Don't overwrite if unchanged — could clobber updates from the Remote Repositories tab.
	if (config && self.contents && [self.contents isEqual:config]) return;

	if (![config writeToFile:[self.repository.path stringByAppendingPathComponent:@".git/config"]
				  atomically:YES
					encoding:NSUTF8StringEncoding
					   error:&error])
	{
		NSLog(@"Error: .git/config update failed: %@", error);
	}
}

@end
