//
//  Gitbox-Bridging-Header.h
//  gitbox
//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

// Import main application classes
#import "GBMainWindowController.h"
#import "GBRootController.h"
#import "GBSidebarController.h"
#import "GBSidebarItem.h"
#import "GBRepository.h"
#import "GBRef.h"
#import "GBRemote.h"
#import "GBStage.h"
#import "GBCommit.h"
#import "GBChange.h"

// Import utility classes
#import "NSObject+OASelectorNotifications.h"
#import "NSArray+OAArrayHelpers.h"
#import "NSString+OAStringHelpers.h"
#import "NSFileManager+OAFileManagerHelpers.h"

// Import protocols and interfaces
#import "GBSidebarItemObject.h"
#import "GBRepositoriesGroup.h"
