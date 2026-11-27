/*	 SDLMain.m - main entry point for our Cocoa-ized SDL app
	   Initial Version: Darrell Walisser <dwaliss1@purdue.edu>
	   Non-NIB-Code & other changes: Max Horn <max@quendi.de>

	Feel free to customize this file to suit your needs
	Adapted for aranym
*/

#import "SDL_compat.h"
#import "SDLMain.h"
#import <sys/param.h> /* for MAXPATHLEN */
#import <unistd.h>
#import "parameters.h"
#import <string.h>
#ifdef ENABLE_MCP
#import "aranym_mcp.h"
#endif

static int gArgc;
static char **gArgv;
static BOOL gFinderLaunch;
static BOOL gCalledAppMainline = FALSE;
char gAranymFilesDirectory[MAXPATHLEN];	 // Path to the "AranymFiles" folder


/* these were renamed in SDK 10.12 and above */
#if !defined(MAC_OS_X_VERSION_10_12) || MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_12
#define NSAlertStyleWarning NSWarningAlertStyle
#define NSAlertStyleInformational NSInformationalAlertStyle
#define NSAlertStyleCritical NSCriticalAlertStyle
#endif


@interface NSApplication (SDLApplication)
@end

@implementation NSApplication (SDLApplication)
/* Invoked from the Quit menu item */
- (void)terminate:(id)sender
{
    /* Post a SDL_QUIT event */
    SDL_Event event;
    event.type = SDL_QUIT;
    SDL_PushEvent(&event);
}
@end

/* The main class of the application, the application's delegate */
@implementation SDLMain

/* The user selected the "Preferencs..." menu entry */
- (IBAction)doSetup:(id)sender
{
	SDL_Event event;
	event.type = SDL_KEYDOWN;
	event.key.keysym.sym = bx_options.hotkeys.setup.sym;
	event.key.keysym.mod = bx_options.hotkeys.setup.mod;
	SDL_PushEvent(&event);
}


/* The user selected the "Fullscreen" menu entry */
- (IBAction)doFullscreen:(id)sender
{
	SDL_Event event;
	event.type = SDL_KEYDOWN;
	event.key.keysym.sym = bx_options.hotkeys.fullscreen.sym;
	event.key.keysym.mod = bx_options.hotkeys.fullscreen.mod;
	SDL_PushEvent(&event);
}

/* The user selected the "Screenshot" menu entry */
- (IBAction)doScreenshot:(id)sender
{
	SDL_Event event;
	event.type = SDL_KEYDOWN;
	event.key.keysym.sym = bx_options.hotkeys.screenshot.sym;
	event.key.keysym.mod = bx_options.hotkeys.screenshot.mod;
	SDL_PushEvent(&event);
}

/* The user selected the "Reboot" menu entry */
- (IBAction)doReboot:(id)sender
{
	SDL_Event event;
	event.type = SDL_KEYDOWN;
	event.key.keysym.sym = bx_options.hotkeys.warmreboot.sym;
	event.key.keysym.mod = bx_options.hotkeys.warmreboot.mod;
	SDL_PushEvent(&event);
}

/* The user selected the "Reboot" menu entry */
- (IBAction)doDebug:(id)sender
{
	SDL_Event event;
	event.type = SDL_KEYDOWN;
	event.key.keysym.sym = bx_options.hotkeys.debug.sym;
	event.key.keysym.mod = bx_options.hotkeys.debug.mod;
	SDL_PushEvent(&event);
}

/* A nice joke :-) */
- (IBAction)help:(id)sender
{
	NSRunAlertPanel (@"Oh help, where have ye gone?", 
		@"Sorry, there is no help available.\n\nThis message brought to you by We Don't Document, Inc.\n\n", @"Rats", @"Good, I never read it anyway", nil);
}


/* Set the working directory to the .app's parent directory */
- (void) setupWorkingDirectory:(BOOL)shouldChdir
{
	if (shouldChdir)
	{
		char parentdir[MAXPATHLEN];
		CFURLRef url = CFBundleCopyBundleURL(CFBundleGetMainBundle());
		CFURLRef url2 = CFURLCreateCopyDeletingLastPathComponent(0, url);
		if (CFURLGetFileSystemRepresentation(url2, true, (UInt8 *)parentdir, MAXPATHLEN)) {
			assert ( chdir (parentdir) == 0 );	/* chdir to the binary app's parent */
		}
		CFRelease(url);
		CFRelease(url2);
	}
}

- (void) findAranymFilesDirectory
{
	//	 get the application's bundle, thus it's name (ARAnyM)
	NSBundle* bundle=[NSBundle mainBundle];
	NSDictionary *infoDict = [bundle infoDictionary];
	
	NSArray* searchPaths = [infoDict objectForKey: @"AranymHomeDirectories"];
	if (![searchPaths isKindOfClass: [NSArray class]] || [searchPaths count] == 0)
		//	 a bundle without the key, such as the one make builds: the defaults
		searchPaths = [NSArray arrayWithObjects: @"Aranym_files", @"~/Documents/Aranym_files", nil];
	
	//	 helper to check existence
	NSFileManager* fileManager = [NSFileManager defaultManager];

	//	 iterate through all folders and check if they exist
	NSEnumerator* searchPathEnum = [searchPaths objectEnumerator];
	NSString* currentPath;
	while ((currentPath = [searchPathEnum nextObject]) != nil)
	{
		currentPath = [[currentPath stringByExpandingTildeInPath] stringByStandardizingPath];
		BOOL isDirectory = NO;
		BOOL exists = [fileManager fileExistsAtPath: currentPath isDirectory: &isDirectory];
		
		if (exists && isDirectory)
			//  it's a valid and existing directory
			break;
	}
	
	//	 if Preferences folder couldn't be found, take last choice
	if (currentPath == nil) {
		currentPath = [[[searchPaths lastObject] stringByExpandingTildeInPath] stringByStandardizingPath];
		NSError *error = nil;
		if (currentPath == nil || ![fileManager createDirectoryAtPath:currentPath
			withIntermediateDirectories:YES attributes:nil error:&error]) {
			NSLog(@"Cannot create ARAnyM configuration directory: %@", error);
			exit(EXIT_FAILURE);
		}
	}

	//	 store this path, convert it to a C string and copy into buffer
	if (![currentPath getFileSystemRepresentation: gAranymFilesDirectory maxLength: MAXPATHLEN]) {
		NSLog(@"ARAnyM configuration directory path is too long");
		exit(EXIT_FAILURE);
	}
	char realPath[MAXPATHLEN];	 // Temporary storage for the resolved path
	if (realpath(gAranymFilesDirectory, realPath) == NULL) {
		NSLog(@"Cannot resolve ARAnyM configuration directory");
		exit(EXIT_FAILURE);
	}
	strncpy(gAranymFilesDirectory, realPath, MAXPATHLEN);
}


-(void) applicationWillFinishLaunching:(NSNotification *)notification
{
#if defined(MAC_OS_X_VERSION_10_12) && (MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_12)
	if (NSAppKitVersionNumber > 1500)
	{
		[NSWindow setAllowsAutomaticWindowTabbing: NO];
	}
#endif
}


/* Called when the internal event loop has just started running */
- (void) applicationDidFinishLaunching: (NSNotification *) note
{
	int status;

	/* Set the working directory to the .app's parent directory */
	[self setupWorkingDirectory:gFinderLaunch];
	[self findAranymFilesDirectory];

#ifdef ENABLE_LILO
	/* Enable linux booting if available! */
	boot_lilo = 1;
#endif

	/* Hand off to main application code */
	gCalledAppMainline = TRUE;
	status = SDL_main (gArgc, gArgv);

	/* We're done, thank you for playing */
	exit(status);
}
@end


void guialert(const char *fmt, ...)
{
	va_list args;
	char *buf = NULL;
	int ret;
	
	va_start(args, fmt);
	vfprintf(stderr, fmt, args);
	fputs("\n", stderr);
	va_end(args);
	va_start(args, fmt);
	ret = vasprintf(&buf, fmt, args);
	va_end(args);
	if (ret >= 0)
	{
		NSRunAlertPanel (@"Error:", @"%s", @"Ok", nil, nil, buf);
		free(buf);
	}
}


#if !SDL_VERSION_ATLEAST(2, 0, 0)
SDL_GLContext SDL_GL_GetCurrentContext(void)
{
	return [NSOpenGLContext currentContext];
}
#endif


/*
 * Only called with ctx != 0,
 * to restore the current SDL context
 */
void SDL_GL_SetCurrentContext(SDL_GLContext ctx)
{
    NSAutoreleasePool *pool;
    pool = [[NSAutoreleasePool alloc] init];
	NSOpenGLContext *nscontext = (NSOpenGLContext *)ctx;
	[nscontext makeCurrentContext];
    [pool release];
}


#ifdef main
#  undef main
#endif


static int IsRootCwd(void)
{
    char buf[MAXPATHLEN];
    char *cwd = getcwd(buf, sizeof (buf));
    return cwd != NULL && strcmp(cwd, "/") == 0;
}

static int IsFinderLaunch(int argc, char **argv)
{
    /* -psn_XXX is passed if we are launched from Finder, SOMETIMES */
    if ( (argc >= 2) && (strncmp(argv[1], "-psn", 4) == 0) ) {
        return 1;
    } else if ((argc == 1) && IsRootCwd()) {
        /* we might still be launched from the Finder; on 10.9+, you might not
        get the -psn command line anymore. If there's no
        command line, and if our current working directory is "/", it
        might as well be a Finder launch. */
        return 1;
    }
    return 0;  /* not a Finder launch. */
}


/* Main entry point to executable - should *not* be SDL_main! */
int main (int argc, char **argv)
{
#ifdef ENABLE_MCP
	/* "aranym -mcp-bridge": the MCP server an agent starts, not a VM */
	if (argc >= 2 && (strcmp(argv[1], "-mcp-bridge") == 0 || strcmp(argv[1], "--mcp-bridge") == 0))
		return aranym_mcp_bridge_main(argc, argv);
#endif
	/* Copy the arguments into a global variable */
	/* This is passed if we are launched by double-clicking */
	if (IsFinderLaunch(argc, argv))
	{
		gArgv = (char **) SDL_malloc(sizeof (char *) * 2);
		gArgv[0] = argv[0];
		gArgv[1] = NULL;
		gArgc = 1;
		gFinderLaunch = YES;
	} 
	else 
	{
		int i;
		gArgc = argc;
		gArgv = (char **) SDL_malloc(sizeof (char *) * (argc+1));
		for (i = 0; i <= argc; i++)
			gArgv[i] = argv[i];
		gFinderLaunch = NO;
	}

	if ([[NSBundle mainBundle] objectForInfoDictionaryKey: @"NSMainNibFile"] == nil)
	{
		/* No bundle (the bare binary): no nib makes the delegate, so make it
		 * here, and be a normal app with a Dock icon and keyboard focus. */
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSApplication *app = [NSApplication sharedApplication];
		if ([app respondsToSelector: @selector(setActivationPolicy:)])
			[app setActivationPolicy: NSApplicationActivationPolicyRegular];
		[app setDelegate: (id)[[SDLMain alloc] init]];
		[pool release];
		[app run];
		return 0;
	}

	NSApplicationMain (argc, (const char **)argv);

	return 0;
}
