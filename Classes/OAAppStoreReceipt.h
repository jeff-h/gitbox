// App Store receipt validation disabled for open source version

#import <Foundation/Foundation.h>

#define kReceiptBundleIdentifer @"BundleIdentifier"
#define kReceiptBundleIdentiferData  @"BundleIdentifierData"
#define kReceiptVersion  @"Version"
#define kReceiptOpaqueValue  @"OpaqueValue"
#define kReceiptHash  @"Hash"

NS_INLINE NSData * OAAppleRootCert()
{
	// Stub implementation - no App Store receipt validation in open source version
	return nil;
}

NS_INLINE NSDictionary* OADictionaryWithAppStoreReceipt(NSString* path)
{
	// Stub implementation - no App Store receipt validation in open source version
	return nil;
}

NS_INLINE BOOL OAValidateAppStoreReceiptAtPath(NSString* path)
{
	// Stub implementation - no App Store receipt validation in open source version
	return YES;
}