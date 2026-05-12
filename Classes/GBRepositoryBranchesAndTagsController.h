#import "GBRepositorySettingsViewController.h"

@interface GBRepositoryBranchesAndTagsController : GBRepositorySettingsViewController

@property(nonatomic, strong) NSMutableArray* branchesBinding;
@property(nonatomic, strong) NSMutableArray* tagsBinding;
@property(nonatomic, strong) NSMutableArray* remoteBranchesBinding;

- (IBAction) deleteBranch:(id)sender;
- (IBAction) deleteTag:(id)sender;
- (IBAction) deleteRemoteBranch:(id)sender;

@end
