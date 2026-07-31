@class GBSidebarItem;
@protocol GBSidebarItemObject <NSObject, NSCoding>

- (GBSidebarItem*) sidebarItem;
- (id) sidebarItemContentsPropertyList;
- (void) sidebarItemLoadContentsFromPropertyList:(id)plist;

@optional

- (NSInteger) sidebarItemNumberOfChildren;
// Must implement this method if number of children > 0
- (GBSidebarItem*) sidebarItemChildAtIndex:(NSInteger)anIndex;

- (NSImage*)   sidebarItemImage;
- (NSString*)  sidebarItemTitle;
// Secondary text shown after the title in a muted colour (e.g. a worktree's branch).
- (NSString*)  sidebarItemSubtitle;
- (NSString*)  sidebarItemTooltip;
- (NSUInteger) sidebarItemBadgeInteger;
- (BOOL) sidebarItemIsSelectable;
- (BOOL) sidebarItemIsExpandable;
- (BOOL) sidebarItemIsEditable;
- (BOOL) sidebarItemIsDraggable;
- (BOOL) sidebarItemIsSpinning;
- (double) sidebarItemProgress;
- (void) sidebarItemSetStringValue:(NSString*)value;
- (NSDragOperation) sidebarItemDragOperationForURLs:(NSArray*)URLs outlineView:(NSOutlineView*)anOutlineView;
- (NSDragOperation) sidebarItemDragOperationForItems:(NSArray*)items outlineView:(NSOutlineView*)anOutlineView;
- (NSMenu*) sidebarItemMenu;

- (BOOL) sidebarItemOpenURLs:(NSArray*)URLs atIndex:(NSUInteger)anIndex;
- (BOOL) sidebarItemMoveObjects:(NSArray*)items toIndex:(NSUInteger)anIndex;

// Action button (e.g. "Download" / "Reset" for submodules)
- (NSString*) sidebarItemActionButtonTitle;
- (SEL) sidebarItemActionButtonAction;

@end
