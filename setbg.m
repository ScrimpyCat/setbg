/*
 *  Copyright (c) 2013, Stefan Johnson
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without modification,
 *  are permitted provided that the following conditions are met:
 *
 *  1. Redistributions of source code must retain the above copyright notice, this list
 *     of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright notice, this
 *     list of conditions and the following disclaimer in the documentation and/or other
 *     materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 * OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*
 Compile:
 clang setbg.m -o setbg -framework Cocoa
 
 Commands:
 -i path = image input
    -is* = size options
        -isfixed = the image retains its original size
        -isprop = the image is proportionally scaled to fit as much of the screen as it can
        -isset number number = the image uses the specified width and height for its size
    -off* = offset options
        -offbl = offsets from the bottom left
        -offbr = offsets from the bottom right
        -offtl = offsets from the top left
        -offtr = offsets from the top right
    -tiled = the image is tiled to fill the screen
 -p path = plugin input
    -pr number = the interval the plugin should be recalled
 -t number = time the operation should last for (note: it does not guarantee any high degree of accuracy, if you do need that you're better off handling that in a plugin)
 -r = repeat the operations once it reaches the end
 -rr = reverse repeat, does the same as repeat except will reverse the order of operations each time it reaches the end
 -kill = conveniently kills the daemon and exits
 -focus process name = specify an app that the focus should be sent to when selecting the background (assumes not being blocked by services placed above setbg such as Finder)
 -nofocus = to disable focus
 
 
 The order of commands can be thought of as as sequence of operations. Where the last set operation can then have additional options to define its usage.
 Examples:
 setbg -i img1.png (Sets the background to img1.png)
 setbg -i img1.png -isfixed (Sets the background to img1.png, without performing any resizing)
 setbg -i img1.png -isset 16 16 -offbl -tiled (Sets the background to img1.png sized at 16*16, which tiles across the screen starting at the bottom left corner)
 setbg -i img1.png -isset 16 16 -offbl (Sets the background to img1.png sized at 16*16, which originates at the bottom left corner)
 setbg -i img1.png -t 2 -i img2.png -t 2 -i img3.png -t 2 -r (Sets the background to img1.png for 2 seconds, then to img2.png for 2 seconds, then to img3.png for 2 seconds, then back to img1.png for 2 seconds, etc.)
 */
#import <Cocoa/Cocoa.h>

#define SBGConnectionName @"setbgd" //Should we use reverse-DNS style naming?
#define SBGAllScreens nil 

typedef enum {
    SBGDrawOnce, //1,2,3,4 end
    SBGDrawRepeat, //1,2,3,4 -> 1,2,3,4
    SBGDrawReverseRepeat //1,2,3,4 -> 3,2,1 -> 2,3,4
} SBGDrawingOrder;

typedef enum {
    SBGDrawOperationSizeStretchToFit,
    SBGDrawOperationSizeFixed,
    SBGDrawOperationSizeScaleProportionally,
    SBGDrawOperationSizeCustom,
    SBGDrawOperationSizeMask = 3,
    
    SBGDrawOperationOffsetCenter = 0,
    SBGDrawOperationOffsetBottomLeft = (1 << 2),
    SBGDrawOperationOffsetBottomRight = (2 << 2),
    SBGDrawOperationOffsetTopLeft = (3 << 2),
    SBGDrawOperationOffsetTopRight = (4 << 2),
    SBGDrawOperationOffsetMask = (7 << 2),
    
    SBGDrawOperationTypeSingle = 0,
    SBGDrawOperationTypeTile = (1 << 5),
    SBGDrawOperationTypeMask = (1 << 5)
} SBGDrawingImageOperationOption;



@protocol SBGDrawingOperation

@property (copy) NSNumber *time;

@end

@protocol SBGData

-(NSView<SBGDrawingOperation>*) view;

@end

@interface SBGDaemon : NSView <NSApplicationDelegate>

@property (retain) NSString *focusOnApp;

-(void) setOperation: (NSArray*)op WithOption: (SBGDrawingOrder)option ApplyToScreens: (NSIndexSet*)indexSet;
-(oneway void) kill;

@end

@interface SBGBackground : NSWindow

@property SBGDrawingOrder drawingOrder;
@property (retain) NSArray *operations;
@property NSUInteger currentOperationIndex;

-(void) setOperation: (NSArray*)op WithOption: (SBGDrawingOrder)option;

@end

@interface SBGImage : NSView <SBGData, SBGDrawingOperation, NSCoding>

@property SBGDrawingImageOperationOption drawingOption;
@property CGSize overridenSize;

-(instancetype) initWithImageAtPath: (NSString*)img;

@end

@interface SBGImageView : NSView <SBGDrawingOperation>

@property SBGDrawingImageOperationOption drawingOption;
@property CGSize overridenSize;

-(instancetype) initWithImageAtPath: (NSString*)img;

@end


int main(int argc, char *argv[])
{
    _Bool RunApp = NO;
    
    @autoreleasepool {
        SBGDaemon *Daemon = nil;
        _Bool Kill = NO, SetFocus = NO;
        NSString *FocusOnApp = nil;
        SBGDrawingOrder DrawOrder = SBGDrawOnce;
        NSMutableArray *DrawOperations = [NSMutableArray array];
        for (int Loop = 1; Loop < argc; Loop++)
        {
            const char *Command = argv[Loop];
            if (!strcmp(Command, "-kill")) //Kill the setbg daemon
            {
                Kill = YES;
                break;
            }
            //Input sources
            else if (!strcmp(Command, "-i")) //Image input
            {
                if (++Loop < argc)
                {
                    NSString *Option = @(argv[Loop]);
                    
                    if ((![[NSFileManager defaultManager] fileExistsAtPath: Option]) || ([[NSImage imageFileTypes] indexOfObject: [Option pathExtension]] == NSNotFound))
                    {
                        fprintf(stderr, "Failed to open the image at: %s.\n", argv[Loop]);
                        return EXIT_FAILURE;
                    }
                    
                    [DrawOperations addObject: [[[SBGImage alloc] initWithImageAtPath: Option] autorelease]];
                }
                
                else
                {
                    fprintf(stderr, "Missing image path.\n");
                    return EXIT_FAILURE;
                }
            }
            
            else if (!strcmp(Command, "-p")) //Plugin input
            {
                if (++Loop < argc)
                {
                    const char *Option = argv[Loop];
                }
                
                else
                {
                    fprintf(stderr, "Missing plugin path.\n");
                    return EXIT_FAILURE;
                }
            }
            //Options
            else if (!strcmp(Command, "-t")) //Time option
            {
                if (++Loop < argc)
                {
                    const char *Option = argv[Loop];
                    
                    id<SBGDrawingOperation> CurrentOperation = [DrawOperations lastObject];
                    if (CurrentOperation) CurrentOperation.time = @([@(Option) doubleValue]);
                }
                
                else
                {
                    fprintf(stderr, "Missing time value.\n");
                    return EXIT_FAILURE;
                }
            }
            //Focus option
            else if (!strcmp(Command, "-focus")) //Focus option
            {
                if (++Loop < argc)
                {
                    SetFocus = YES;
                    FocusOnApp = @(argv[Loop]);
                }
                
                else
                {
                    fprintf(stderr, "Missing process name.\n");
                    return EXIT_FAILURE;
                }
            }
            
            else if (!strcmp(Command, "-nofocus")) //Disable focus option
            {
                SetFocus = YES;
                FocusOnApp = nil;
            }
            //Order options
            else if (!strcmp(Command, "-r")) //Repeats option
            {
                DrawOrder = SBGDrawRepeat;
            }
            
            else if (!strcmp(Command, "-rr")) //Reverse repeat option
            {
                DrawOrder = SBGDrawReverseRepeat;
            }
            
            //Specific type options
            else if (!strncmp(Command, "-is", 3)) //Image size option
            {
                SBGDrawingImageOperationOption Size;
                Command += 3;
                
                id<NSObject, SBGDrawingOperation> CurrentOperation = [DrawOperations lastObject];
                if (![CurrentOperation isKindOfClass: [SBGImage class]])
                {
                    fprintf(stderr, "Invalid option for type: %s.\n", [[[CurrentOperation class] description] UTF8String]);
                    return EXIT_FAILURE;
                }
                
                if (!strcmp(Command, "fixed")) Size = SBGDrawOperationSizeFixed;
                else if (!strcmp(Command, "prop")) Size = SBGDrawOperationSizeScaleProportionally;
                else if (!strcmp(Command, "set"))
                {
                    Size = SBGDrawOperationSizeCustom;
                    const char *Width, *Height;
                    
                    if (++Loop < argc) Width = argv[Loop];
                    else
                    {
                        fprintf(stderr, "Missing width and height.\n");
                        return EXIT_FAILURE;
                    }
                    
                    if (++Loop < argc) Height = argv[Loop];
                    else
                    {
                        fprintf(stderr, "Missing height.\n");
                        return EXIT_FAILURE;
                    }
                    
                    ((SBGImage*)CurrentOperation).overridenSize = CGSizeMake([@(Width) floatValue], [@(Height) floatValue]);
                }
                
                else
                {
                    fprintf(stderr, "%s is not a valid command.\n", Command - 3);
                    return EXIT_FAILURE;
                }
                
                ((SBGImage*)CurrentOperation).drawingOption = (((SBGImage*)CurrentOperation).drawingOption & ~SBGDrawOperationSizeMask) | Size;
            }
            
            else if (!strncmp(Command, "-off", 4)) //Image offset option
            {
                SBGDrawingImageOperationOption Offset;
                Command += 4;
                if (!strcmp(Command, "bl")) Offset = SBGDrawOperationOffsetBottomLeft;
                else if (!strcmp(Command, "br")) Offset = SBGDrawOperationOffsetBottomRight;
                else if (!strcmp(Command, "tl")) Offset = SBGDrawOperationOffsetTopLeft;
                else if (!strcmp(Command, "tr")) Offset = SBGDrawOperationOffsetTopRight;
                else
                {
                    fprintf(stderr, "%s is not a valid command.\n", Command - 4);
                    return EXIT_FAILURE;
                }
                
                id<NSObject, SBGDrawingOperation> CurrentOperation = [DrawOperations lastObject];
                if (![CurrentOperation isKindOfClass: [SBGImage class]])
                {
                    fprintf(stderr, "Invalid option for type: %s.\n", [[[CurrentOperation class] description] UTF8String]);
                    return EXIT_FAILURE;
                }
                
                ((SBGImage*)CurrentOperation).drawingOption = (((SBGImage*)CurrentOperation).drawingOption & ~SBGDrawOperationOffsetMask) | Offset;
            }
            
            else if (!strcmp(Command, "-tiled")) //Image tiled option
            {
                id<NSObject, SBGDrawingOperation> CurrentOperation = [DrawOperations lastObject];
                if (![CurrentOperation isKindOfClass: [SBGImage class]])
                {
                    fprintf(stderr, "Invalid option for type: %s.\n", [[[CurrentOperation class] description] UTF8String]);
                    return EXIT_FAILURE;
                }
                
                ((SBGImage*)CurrentOperation).drawingOption = (((SBGImage*)CurrentOperation).drawingOption & ~SBGDrawOperationTypeMask) | SBGDrawOperationTypeTile;
            }
            
            else if (!strcmp(Command, "-pr")) //Plugin refresh rate option
            {
                if (++Loop < argc)
                {
                    const char *Option = argv[Loop];
                }
                
                else
                {
                    fprintf(stderr, "Missing refresh value.\n");
                    return EXIT_FAILURE;
                }
            }
            
            //help
            else if ((!strcmp(Command, "--help")) || (!strcmp(Command, "-h")))
            {
                printf("Commands:\n"
                       "\t-i path = image input\n"
                       "\t\t-is* = size options\n"
                       "\t\t\t-isfixed = the image retains its original size\n"
                       "\t\t\t-isprop = the image is proportionally scaled to fit as much of the screen as it can\n"
                       "\t\t\t-isset number number = the image uses the specified width and height for its size\n"
                       "\t\t-off* = offset options\n"
                       "\t\t\t-offbl = offsets from the bottom left\n"
                       "\t\t\t-offbr = offsets from the bottom right\n"
                       "\t\t\t-offtl = offsets from the top left\n"
                       "\t\t\t-offtr = offsets from the top right\n"
                       "\t\t-tiled = the image is tiled to fill the screen\n"
                       "\t-p path = plugin input\n"
                       "\t\t-pr number = the interval the plugin should be recalled\n"
                       "\t-t number = time the operation should last for (note: it does not guarantee any high degree of accuracy, if you do need that you're better off handling that in a plugin)\n"
                       "\t-r = repeat the operations once it reaches the end\n"
                       "\t-rr = reverse repeat, does the same as repeat except will reverse the order of operations each time it reaches the end\n"
                       "\t-kill = conveniently kills the daemon and exits\n"
                       "\t-focus process name = specify an app that the focus should be sent to when selecting the background (assumes not being blocked by services placed above setbg such as Finder)\n"
                       "\t-nofocus = to disable focus\n"
                       "Examples:\n"
                       "\tsetbg -i img1.png (Sets the background to img1.png)\n"
                       "\tsetbg -i img1.png -isfixed (Sets the background to img1.png, without performing any resizing)\n"
                       "\tsetbg -i img1.png -isset 16 16 -offbl -tiled (Sets the background to img1.png sized at 16*16, which tiles across the screen starting at the position bottom left)\n"
                       "\tsetbg -i img1.png -isset 16 16 -offbl (Sets the background to img1.png sized at 16*16, which originates at the bottom left corner)\n"
                       "\tsetbg -i img1.png -t 2 -i img2.png -t 2 -i img3.png -t 2 -r (Sets the background to img1.png for 2 seconds, then to img2.png for 2 seconds, then to img3.png for 2 seconds, then back to img1.png for 2 seconds, etc.)\n");
                
                return EXIT_SUCCESS;
            }
            
            else
            {
                fprintf(stderr, "\"%s\" is not a valid command. For a list of commands use the option: --help.\n", Command);
                return EXIT_FAILURE;
            }
        }
        
        NSConnection *DaemonConnection = [NSConnection connectionWithRegisteredName: SBGConnectionName host: nil];
        if (!DaemonConnection)
        {
            if (Kill) return EXIT_SUCCESS;
            
            NSApplication *App = [NSApplication sharedApplication];
            RunApp = YES;
            
            Daemon = [SBGDaemon new];
            [App setDelegate: Daemon];
            
            [Daemon setOperation: DrawOperations WithOption: DrawOrder ApplyToScreens: SBGAllScreens];
            
            if (SetFocus) Daemon.focusOnApp = FocusOnApp;
        }
        
        else if (Kill)
        {
            [(SBGDaemon*)[DaemonConnection rootProxy] kill];
        }
        
        else
        {
            SBGDaemon *Daemon = (SBGDaemon*)[DaemonConnection rootProxy];
            [Daemon setOperation: DrawOperations WithOption: DrawOrder ApplyToScreens: SBGAllScreens];
            if (SetFocus) Daemon.focusOnApp = FocusOnApp;
        }
    }
    
    if (RunApp)
    {
        [NSApp run];
    }
    
    return EXIT_SUCCESS;
}


#pragma mark - Daemon
@interface SBGDaemon ()
{
    CFMachPortRef tap;
    CFRunLoopSourceRef source;
}

@property (readonly) NSArray *backgrounds;

@end

@implementation SBGDaemon
{
    NSConnection *connection;
}
@synthesize backgrounds, focusOnApp;

-(id) init
{
    if ((self = [super init]))
    {
        NSArray *Screens = [NSScreen screens];
        NSMutableArray *Backgrounds = [[NSMutableArray alloc] initWithCapacity: [Screens count]];
        backgrounds = Backgrounds;
        for (NSScreen *Screen in Screens)
        {
            CGRect Frame = [Screen frame]; Frame.origin = CGPointMake(0.0f, 0.0f);
            SBGBackground *Window = [[[SBGBackground alloc] initWithContentRect: Frame styleMask: NSBorderlessWindowMask backing: NSBackingStoreBuffered defer: NO screen: Screen] autorelease];
            
            [Window setCollectionBehavior: NSWindowCollectionBehaviorCanJoinAllSpaces];
            [Window setOpaque: YES];
            [Window setBackgroundColor: [NSColor blackColor]];
            [Window setContentView: self];
            [Window setLevel: kCGDesktopWindowLevel];
            [Window makeKeyAndOrderFront: nil];
            
            [Backgrounds addObject: Window];
        }
    }
    
    return self;
}

static CGEventRef FocusEventTap(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo)
{
    switch (type)
    {
        case kCGEventTapDisabledByTimeout:
            ((SBGDaemon*)userInfo).focusOnApp = ((SBGDaemon*)userInfo).focusOnApp; //As it will re-enable the event tap
            break;
            
        default:;
            NSString *TargetApp = ((SBGDaemon*)userInfo).focusOnApp;
            if (TargetApp)
            {
                ProcessSerialNumber PSN = { 0, kNoProcess };
                while (GetNextProcess(&PSN) != procNotFound)
                {
                    NSString *Name;
                    CopyProcessName(&PSN, (CFStringRef*)&Name);
                    if ([Name isEqualToString: TargetApp])
                    {
                        SetFrontProcessWithOptions(&PSN, kSetFrontProcessFrontWindowOnly);
                        [Name release];
                        break;
                    }
                    [Name release];
                }
            }
            break;
    }
    
    
    return event;
}

-(void) applicationDidFinishLaunching: (NSNotification*)aNotification
{
    connection = [[NSConnection serviceConnectionWithName: SBGConnectionName rootObject: self] retain];
    
    [[NSDistributedNotificationCenter defaultCenter] addObserver: self selector: @selector(connectionDied:) name: NSConnectionDidDieNotification object: nil];
    
    
    CGEventMask Mask = CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp) | CGEventMaskBit(kCGEventRightMouseDown) | CGEventMaskBit(kCGEventRightMouseUp) | CGEventMaskBit(kCGEventLeftMouseDragged) | CGEventMaskBit(kCGEventOtherMouseDown) | CGEventMaskBit(kCGEventOtherMouseUp);
    
    ProcessSerialNumber PSN;
    GetCurrentProcess(&PSN);
    
    tap = CGEventTapCreateForPSN(&PSN, kCGHeadInsertEventTap, kCGEventTapOptionDefault, Mask, FocusEventTap, self);
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    
    if (!self.focusOnApp) CGEventTapEnable(tap, FALSE);
}

static OSSpinLock FocusOnAppLock = OS_SPINLOCK_INIT;
-(NSString*) focusOnApp
{
    NSString *Name = nil;
    OSSpinLockLock(&FocusOnAppLock);
    Name = [focusOnApp retain];
    OSSpinLockUnlock(&FocusOnAppLock);
    
    return [Name autorelease];
}

-(void) setFocusOnApp: (NSString*)name
{
    OSSpinLockLock(&FocusOnAppLock);
    [focusOnApp release];
    focusOnApp = [name retain];
    
    if (tap) CGEventTapEnable(tap, name != nil);
    OSSpinLockUnlock(&FocusOnAppLock);
}

-(void) setOperation: (NSArray*)op WithOption: (SBGDrawingOrder)option ApplyToScreens: (NSIndexSet*)indexSet;
{
    if (indexSet == SBGAllScreens)
    {
        for (SBGBackground *Background in self.backgrounds)
        {
            [Background setOperation: op WithOption: option];
        }
    }
}

-(oneway void) kill
{
    [connection invalidate];
    [NSApp terminate: self];
}

-(void) connectionDied: (NSNotification*)notification
{
    [NSApp terminate: self];
}

-(void) dealloc
{
    [connection invalidate];
    [connection release]; connection = nil;
    
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
    CFRelease(source); source = NULL;
    CFRelease(tap); tap = NULL;
    
    [focusOnApp release]; focusOnApp = nil;
    [backgrounds release]; backgrounds = nil;
    
    [super dealloc];
}

@end


#pragma mark - Screens
@interface SBGBackground ()

-(void) nextOperation: (NSTimer*)timer;

@end

@implementation SBGBackground
{
    NSTimer *timer;
    NSInteger direction;
}
@synthesize operations,  currentOperationIndex, drawingOrder;

-(id) initWithContentRect: (NSRect)contentRect styleMask: (NSUInteger)windowStyle backing: (NSBackingStoreType)bufferingType defer: (BOOL)deferCreation screen: (NSScreen*)screen
{
    if ((self = [super initWithContentRect: contentRect styleMask: windowStyle backing: bufferingType defer: deferCreation screen: screen]))
    {
        direction = 1;
    }
    
    return self;
}

-(void) nextOperation: (NSTimer*)oldTimer
{
    @synchronized(self) {
        NSArray *Operations = self.operations;
        NSInteger Index = self.currentOperationIndex + direction, Count = [Operations count];
        
        if (Index >= Count)
        {
            switch (self.drawingOrder)
            {
                case SBGDrawRepeat:
                    Index = 0;
                    break;
                    
                case SBGDrawReverseRepeat:
                    direction *= -1;
                    Index = (Index - 2 > 0? Index - 2 : 0);
                    break;
                    
                default: return; //SBGDrawOnce or some invalid value
            }
        }
        
        else if (Index < 0)
        {
            direction *= -1;
            Index = (Count > 1? 1 : 0);
        }
        
        
        self.currentOperationIndex = Index;
        
        id<SBGDrawingOperation> Op = [Operations objectAtIndex: Index];
        NSNumber *Time = Op.time;
        
        if (Time)
        {
            [timer release];
            timer = [[NSTimer timerWithTimeInterval: [Time doubleValue] target: self selector: @selector(nextOperation:) userInfo: nil repeats: NO] retain];
            [[NSRunLoop mainRunLoop] addTimer: timer forMode: NSDefaultRunLoopMode];
        }
    }
    
    [[self contentView] setNeedsDisplay: YES];
}

-(NSUInteger) currentOperationIndex
{
    return currentOperationIndex;
}

-(void) setCurrentOperationIndex: (NSUInteger)Index
{
    currentOperationIndex = Index;
    
    NSArray *Operations = self.operations;
    if ([Operations count])
    {
        NSView *View = [self.operations objectAtIndex: Index];
        
        CGSize Size = [[self screen] frame].size;
        View.frame = CGRectMake(0.0f, 0.0f, Size.width, Size.height);
        [self setContentView: View];
    }
    
    else [self setContentView: nil];
}

-(void) setOperation: (NSArray*)op WithOption: (SBGDrawingOrder)option;
{
    @synchronized(self) {
        if (timer)
        {
            [timer invalidate];
            [timer release]; timer = nil;
        }
        
        NSMutableArray *Views = [NSMutableArray arrayWithCapacity: [op count]];
        for (id<SBGData> Data in op) [Views addObject: [Data view]];
        
        self.operations = Views;
        self.drawingOrder = option;
        self.currentOperationIndex = 0;
        
        if ([Views count])
        {
            id<SBGDrawingOperation> Op = [Views objectAtIndex: 0];
            NSNumber *Time = Op.time;
            
            if (Time)
            {
                timer = [[NSTimer timerWithTimeInterval: [Time doubleValue] target: self selector: @selector(nextOperation:) userInfo: nil repeats: NO] retain];
                [[NSRunLoop mainRunLoop] addTimer: timer forMode: NSDefaultRunLoopMode];
            }
        }
    }
    
    [[self contentView] setNeedsDisplay: YES];
}

-(void) dealloc
{
    if (timer)
    {
        [timer invalidate];
        [timer release]; timer = nil;
    }
    
    [operations release]; operations = nil;
    
    [super dealloc];
}

@end


#pragma mark - Data
@implementation SBGImage
{
    NSString *imagePath;
}
@synthesize time, drawingOption, overridenSize;

-(instancetype) initWithImageAtPath: (NSString*)img
{
    if ((self = [super init]))
    {
        imagePath = [img retain];
    }
    
    return self;
}

-(id) replacementObjectForPortCoder: (NSPortCoder*)encoder
{
    return self;
}

-(id) initWithCoder: (NSCoder*)decoder
{
    if ((self = [super init]))
    {
        time = [[decoder decodeObject] retain];
        imagePath = [[decoder decodeObject] retain];
        [decoder decodeValueOfObjCType: @encode(SBGDrawingImageOperationOption) at: &drawingOption];
        [decoder decodeValueOfObjCType: @encode(CGSize) at: &overridenSize];
    }
    
    return self;
}

-(void) encodeWithCoder: (NSCoder*)encoder
{
    [encoder encodeBycopyObject: self.time];
    [encoder encodeBycopyObject: imagePath];
    [encoder encodeValueOfObjCType: @encode(SBGDrawingImageOperationOption) at: &drawingOption];
    [encoder encodeValueOfObjCType: @encode(CGSize) at: &overridenSize];
}

-(NSView<SBGDrawingOperation>*) view
{
    SBGImageView *ImageView = [[[SBGImageView alloc] initWithImageAtPath: imagePath] autorelease];
    ImageView.time = self.time;
    ImageView.drawingOption = self.drawingOption;
    ImageView.overridenSize = self.overridenSize;
    
    return ImageView;
}

-(void) dealloc
{
    [imagePath release]; imagePath = nil;
    [time release]; time = nil;
    
    [super dealloc];
}

@end


#pragma mark - Views
@interface SBGImageView ()

-(CGPoint) offsetInRect: (CGRect)rect ForSize: (CGSize)size;

@end

@implementation SBGImageView
{
    NSString *imagePath;
    CGImageRef cachedImage;
    CGRect cachedRect;
}
@synthesize time, drawingOption, overridenSize;

-(instancetype) initWithImageAtPath: (NSString*)img
{
    if ((self = [super init]))
    {
        imagePath = [img copy];
    }
    
    return self;
}

-(void) drawRect: (CGRect)rect
{
    const SBGDrawingImageOperationOption DrawOp = self.drawingOption;
    CGContextRef ctx = [[NSGraphicsContext currentContext] graphicsPort];
    CGContextClearRect(ctx, rect);
    
    if (!cachedImage)
    {
        NSImage *Image = [[NSImage alloc] initByReferencingFile: imagePath];
        
        const NSSize Size = Image.size;
        
        
        CGRect Rect;
        if ((DrawOp & SBGDrawOperationSizeMask) == SBGDrawOperationSizeStretchToFit) Rect = rect;
        else if ((DrawOp & SBGDrawOperationSizeMask) == SBGDrawOperationSizeFixed)
        {
            Rect.size = Size;
            Rect.origin = [self offsetInRect: rect ForSize: Size];
        }
        
        else if ((DrawOp & SBGDrawOperationSizeMask) == SBGDrawOperationSizeScaleProportionally)
        {
            CGSize ViewSize = rect.size;
            if (Size.width > Size.height)
            {
                const float Scale = Size.height / Size.width;
                Rect.size = CGSizeMake(ViewSize.width, ViewSize.width * Scale);
            }
            
            else
            {
                const float Scale = Size.width / Size.height;
                Rect.size = CGSizeMake(ViewSize.height * Scale, ViewSize.height);
            }
            
            Rect.origin = [self offsetInRect: rect ForSize: Rect.size];
        }
        
        else if ((DrawOp & SBGDrawOperationSizeMask) == SBGDrawOperationSizeCustom)
        {
            Rect.size = self.overridenSize;
            Rect.origin = [self offsetInRect: rect ForSize: Rect.size];
        }
        
        cachedRect = Rect;
        cachedImage = CGImageRetain([Image CGImageForProposedRect: NULL context: [NSGraphicsContext currentContext] hints: nil]);
        [Image release];
        
        const size_t ImageSize = CGImageGetWidth(cachedImage) * CGImageGetHeight(cachedImage), DrawingSize = cachedRect.size.width * cachedRect.size.height, DestinationSize = rect.size.width * rect.size.height;
        if ((ImageSize > DrawingSize) || (ImageSize > DestinationSize))
        {
            const size_t BitsPerComponent = CGImageGetBitsPerComponent(cachedImage), BPP = CGImageGetBitsPerPixel(cachedImage);
            CGColorSpaceRef ColourSpace = CGImageGetColorSpace(cachedImage);
            const CGBitmapInfo Info = CGImageGetBitmapInfo(cachedImage);

            
            
            if (DrawingSize < DestinationSize)
            {
                //custom, proportional
                const CGRect OptimalRect = CGRectMake(0.0f, 0.0f, cachedRect.size.width, cachedRect.size.height);
                
                CGContextRef ImageCtx = CGBitmapContextCreate(NULL, OptimalRect.size.width, OptimalRect.size.height, BitsPerComponent, (BPP / 8) * (size_t)OptimalRect.size.width, ColourSpace, Info);
                CGContextDrawImage(ImageCtx, OptimalRect, cachedImage);
                
                CGImageRef OptimalImage = CGBitmapContextCreateImage(ImageCtx);
                CGImageRelease(cachedImage); cachedImage = OptimalImage;
                CGContextRelease(ImageCtx);
                
                cachedRect.size = OptimalRect.size;
            }
            
            else
            {
                //fixed, shrunk
                const CGRect OptimalRect = CGRectMake(0.0f, 0.0f, rect.size.width, rect.size.height);
                
                CGContextRef ImageCtx = CGBitmapContextCreate(NULL, OptimalRect.size.width, OptimalRect.size.height, BitsPerComponent, (BPP / 8) * (size_t)OptimalRect.size.width, ColourSpace, Info);
                
                /*
                 Noticed an issue here:
                 Depending on the size of the image and positioning and size of the rect it can affect the memory usage internally after the call to CGContextDrawImage.
                 
                 image size = 6000*6000
                 
                 rects                     pid    proc  CPU Threads  Real      Kind      Sandbox Shared Private
                 0,0,100,100 =           32276	 setbg	0.0	  2   27.0 MB	Intel (64 bit)	No	21.9 MB	14.4 MB
                 0,0,1000,1000 =         32280	 setbg	0.0	  2   29.9 MB	Intel (64 bit)	No	21.6 MB	16.1 MB
                 0,0,10000,10000 =       32284	 setbg	0.0	  2   27.1 MB	Intel (64 bit)	No	21.6 MB	14.8 MB
                 0,0,6000,6000 =         32288	 setbg	0.0	  2   57.6 MB	Intel (64 bit)	No	21.9 MB	14.9 MB <-- internal caching maybe?
                 -2160,-2475,6000,6000 = 32309	 setbg	0.0	  2   72.9 MB	Intel (64 bit)	No	21.6 MB	14.8 MB <-- >_<
                 
                 
                 A deeper look:
                 
                 
                 Loop at copyImageBlockSetJPEG+3398 allocates a little bit more memory every iteration when calling _cg_jpeg_read_scanlines
                 
                 1: x/i $pc  0x7fff90090d67 <copyImageBlockSetJPEG+3451>:	callq  0x7fff90132e5e <dyld_stub__cg_jpeg_read_scanlines>
                 
                 #0  0x00007fff9008ffec in copyImageBlockSetJPEG ()
                 #1  0x00007fff90080555 in ImageProviderCopyImageBlockSetCallback ()
                 #2  0x00007fff9345b299 in img_blocks_create ()
                 #3  0x00007fff9345b0f0 in img_blocks_extent ()
                 #4  0x00007fff93421c43 in img_data_lock ()
                 #5  0x00007fff9341f2b2 in CGSImageDataLock ()
                 #6  0x00007fff90d43ba9 in ripc_AcquireImage ()
                 #7  0x00007fff90d42709 in ripc_DrawImage ()
                 #8  0x00007fff9341ede7 in CGContextDrawImage ()
                 #9  0x000000010000458d in -[SBGImage drawInContext:InRect:] ()
                 #10 0x0000000100002fdc in -[SBGDaemon drawRect:] ()
                 #11 0x00007fff91f8f064 in -[NSView _drawRect:clip:] ()
                 #12 0x00007fff91f8d6c1 in -[NSView _recursiveDisplayAllDirtyWithLockFocus:visRect:] ()
                 #13 0x00007fff91f8dad9 in -[NSView _recursiveDisplayAllDirtyWithLockFocus:visRect:] ()
                 #14 0x00007fff91f8b6f2 in -[NSView _recursiveDisplayRectIfNeededIgnoringOpacity:isVisibleRect:rectIsVisibleRectForView:topView:] ()
                 #15 0x00007fff920dafab in -[NSNextStepFrame _recursiveDisplayRectIfNeededIgnoringOpacity:isVisibleRect:rectIsVisibleRectForView:topView:] ()
                 #16 0x00007fff91f86d6d in -[NSView _displayRectIgnoringOpacity:isVisibleRect:rectIsVisibleRectForView:] ()
                 #17 0x00007fff91f50c93 in -[NSView displayIfNeeded] ()
                 #18 0x00007fff920dae64 in -[NSNextStepFrame displayIfNeeded] ()
                 #19 0x00007fff9200da18 in -[NSWindow _reallyDoOrderWindow:relativeTo:findKey:forCounter:force:isModal:] ()
                 #20 0x00007fff9200d038 in -[NSWindow _doOrderWindow:relativeTo:findKey:forCounter:force:isModal:] ()
                 #21 0x00007fff9200cc1f in -[NSWindow orderWindow:relativeTo:] ()
                 #22 0x00007fff920056dc in -[NSWindow makeKeyAndOrderFront:] ()
                 #23 0x00000001000029c0 in -[SBGDaemon applicationDidFinishLaunching:] ()
                 #24 0x00007fff90aededa in _CFXNotificationPost ()
                 #25 0x00007fff92a737b6 in -[NSNotificationCenter postNotificationName:object:userInfo:] ()
                 #26 0x00007fff91f5452d in -[NSApplication _postDidFinishNotification] ()
                 #27 0x00007fff91f54266 in -[NSApplication _sendFinishLaunchingNotification] ()
                 #28 0x00007fff91f51452 in -[NSApplication(NSAppleEventHandling) _handleAEOpenEvent:] ()
                 #29 0x00007fff91f5104c in -[NSApplication(NSAppleEventHandling) _handleCoreEvent:withReplyEvent:] ()
                 #30 0x00007fff92a8d07b in -[NSAppleEventManager dispatchRawAppleEvent:withRawReply:handlerRefCon:] ()
                 #31 0x00007fff92a8cedd in _NSAppleEventManagerGenericHandler ()
                 #32 0x00007fff97244078 in aeDispatchAppleEvent ()
                 #33 0x00007fff97243ed9 in dispatchEventAndSendReply ()
                 #34 0x00007fff97243d99 in aeProcessAppleEvent ()
                 #35 0x00007fff9910e709 in AEProcessAppleEvent ()
                 #36 0x00007fff91f4d836 in _DPSNextEvent ()
                 #37 0x00007fff91f4cdf2 in -[NSApplication nextEventMatchingMask:untilDate:inMode:dequeue:] ()
                 #38 0x00007fff91f441a3 in -[NSApplication run] ()
                 #39 0x00000001000025cd in main ()
                 
                 
                 Memory will be freed up later (as it's for a cache) but doesn't serve a purpose for this type of use case. Possible solution, Apple offer a separate non-cache function? Or can we set the allocator?
                 */
                
                CGContextDrawImage(ImageCtx, cachedRect, cachedImage);
                
                CGImageRef OptimalImage = CGBitmapContextCreateImage(ImageCtx);
                CGImageRelease(cachedImage); cachedImage = OptimalImage;
                CGContextRelease(ImageCtx);
                
                cachedRect = OptimalRect;
            }
        }
    }
    
    ((DrawOp & SBGDrawOperationTypeMask) == SBGDrawOperationTypeSingle ? CGContextDrawImage : CGContextDrawTiledImage)(ctx, cachedRect, cachedImage);
    CGContextFlush(ctx);
}

-(CGPoint) offsetInRect: (CGRect)rect ForSize: (CGSize)size
{
    const SBGDrawingImageOperationOption DrawOp = self.drawingOption;
    
    CGPoint Offset;
    if ((DrawOp & SBGDrawOperationOffsetMask) == SBGDrawOperationOffsetCenter) Offset = CGPointMake(rect.origin.x + ((rect.size.width / 2.0f) - (size.width / 2.0f)), rect.origin.y + ((rect.size.height / 2.0f) - (size.height / 2.0f)));
    else if ((DrawOp & SBGDrawOperationOffsetMask) == SBGDrawOperationOffsetBottomLeft) Offset = rect.origin;
    else if ((DrawOp & SBGDrawOperationOffsetMask) == SBGDrawOperationOffsetBottomRight) Offset = CGPointMake(rect.origin.x + (rect.size.width - size.width), rect.origin.y);
    else if ((DrawOp & SBGDrawOperationOffsetMask) == SBGDrawOperationOffsetTopLeft) Offset = CGPointMake(rect.origin.x, rect.origin.y + (rect.size.height - size.height));
    else if ((DrawOp & SBGDrawOperationOffsetMask) == SBGDrawOperationOffsetTopRight) Offset = CGPointMake(rect.origin.x + (rect.size.width - size.width), rect.origin.y + (rect.size.height - size.height));
    
    return Offset;
}

-(void) dealloc
{
    [imagePath release]; imagePath = nil;
    [time release]; time = nil;
    CGImageRelease(cachedImage); cachedImage = NULL;
    
    [super dealloc];
}

@end
