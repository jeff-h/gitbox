#import <Cocoa/Cocoa.h>

#import "GBAskPass.h"
#import "GBAskPassServer.h"

int main(int argc, const char *argv[])
{
	@autoreleasepool {
	if ([[[NSProcessInfo processInfo] environment] objectForKey:GBAskPassServerNameKey])
	{
		return GBAskPass(argc, argv);
	}

	if (getenv("NSZombieEnabled"))
	{
		NSLog(@"WARNING! NSZombieEnabled is ON!");
	}

	if (getenv("NSAutoreleaseFreedObjectCheckEnabled"))
	{
		NSLog(@"WARNING! NSAutoreleaseFreedObjectCheckEnabled is ON!");
	}

	return NSApplicationMain(argc, (const char **) argv);
	}
}
