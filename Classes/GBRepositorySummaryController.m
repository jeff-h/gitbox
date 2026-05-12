#import "GBRepositorySummaryController.h"
#import "GBRepository.h"

@interface GBRepositorySummaryController ()
@property(nonatomic, strong) NSTextView* gitignoreTextView;
@end

@implementation GBRepositorySummaryController

- (void) dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString*) title
{
	return NSLocalizedString(@"Ignored Files", @"");
}

- (void) loadView
{
	NSView* container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
	container.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	NSTextField* label = [NSTextField labelWithString:NSLocalizedString(@"Ignored files (.gitignore)", @"")];
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

	self.gitignoreTextView = textView;

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
	NSString* gitignoreContents = [NSString stringWithContentsOfFile:[self.repository.path stringByAppendingPathComponent:@".gitignore"] encoding:NSUTF8StringEncoding error:&error];

	if (!gitignoreContents) gitignoreContents = @"";

	NSArray* paths = [self.userInfo objectForKey:@"pathsForGitIgnore"];
	if (paths.count > 0)
	{
		gitignoreContents = [gitignoreContents stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		NSUInteger length = gitignoreContents.length;
		NSString* additionalSpace = (length > 0 ? @"\n" : @"");
		NSString* appendix = [paths componentsJoinedByString:@"\n"];
		gitignoreContents = [gitignoreContents stringByAppendingFormat:@"%@%@\n", additionalSpace, appendix];
		[self.gitignoreTextView setString:gitignoreContents];
		NSRange selectionRange = NSMakeRange(length + additionalSpace.length, appendix.length);
		[self.gitignoreTextView setSelectedRange:selectionRange];
		[self.gitignoreTextView scrollRangeToVisible:selectionRange];
	}
	else
	{
		[self.gitignoreTextView setString:gitignoreContents];
	}

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(didUpdateText:)
												 name:NSTextDidChangeNotification
											   object:self.gitignoreTextView];
}

- (void) didUpdateText:(NSNotification*)notif
{
	self.dirty = YES;
}

- (void) save
{
	NSError* error = nil;
	NSString* gitignore = [self.gitignoreTextView.string copy];
	NSString* gitignoreTrimmed = [gitignore stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString* gitignorePath = [self.repository.path stringByAppendingPathComponent:@".gitignore"];

	if (![[[NSFileManager alloc] init] fileExistsAtPath:gitignorePath] && gitignoreTrimmed.length == 0)
	{
		// avoid creating an empty file
		return;
	}

	if (![gitignore writeToFile:gitignorePath
					 atomically:YES
					   encoding:NSUTF8StringEncoding
						  error:&error])
	{
		NSLog(@"Error: .gitignore update failed: %@", error);
	}
}

@end
