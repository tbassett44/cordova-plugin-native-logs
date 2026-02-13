#import "CDVNativeLogs.h"
#import <Cordova/CDV.h>

@implementation CDVNativeLogs

@synthesize logCallbackId;
@synthesize logFileSource;
@synthesize lastFileOffset;

- (void)pluginInitialize
{
    NSString* pathForLog = [self getPath];
    [[NSFileManager defaultManager] removeItemAtPath:pathForLog error:nil];
    freopen([pathForLog cStringUsingEncoding:NSASCIIStringEncoding],"a+",stderr);
    self.lastFileOffset = 0;
}

- (NSString*) getPath {
    NSArray *allPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [allPaths objectAtIndex:0];
    NSString *pathForLog = [documentsDirectory stringByAppendingPathComponent:@"cordova-plugin-nativelogs.txt"];
    return pathForLog;
}

- (void)init:(CDVInvokedUrlCommand*)command {
    // Stop any existing monitoring
    [self stopMonitoring];

    self.logCallbackId = command.callbackId;
    NSString* pathForLog = [self getPath];

    // Get current file size as starting offset
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attrs = [fileManager attributesOfItemAtPath:pathForLog error:nil];
    self.lastFileOffset = [attrs fileSize];

    // Open file descriptor for monitoring
    int fileDescriptor = open([pathForLog UTF8String], O_EVTONLY);
    if (fileDescriptor < 0) {
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Failed to open log file for monitoring"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    // Create dispatch source to monitor file changes
    self.logFileSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, fileDescriptor,
                                                 DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND,
                                                 dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));

    __weak CDVNativeLogs *weakSelf = self;

    dispatch_source_set_event_handler(self.logFileSource, ^{
        CDVNativeLogs *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.logCallbackId) return;

        NSString* logPath = [strongSelf getPath];
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:logPath];
        if (!fileHandle) return;

        // Seek to last read position
        [fileHandle seekToFileOffset:strongSelf.lastFileOffset];

        // Read new data
        NSData *newData = [fileHandle readDataToEndOfFile];
        if (newData.length > 0) {
            strongSelf.lastFileOffset = [fileHandle offsetInFile];

            NSString *newContent = [[NSString alloc] initWithData:newData encoding:NSUTF8StringEncoding];
            if (newContent && newContent.length > 0) {
                // Split by lines and send each line
                NSArray *lines = [newContent componentsSeparatedByString:@"\n"];
                for (NSString *line in lines) {
                    if (line.length > 0) {
                        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:line];
                        [pluginResult setKeepCallbackAsBool:YES];
                        [strongSelf.commandDelegate sendPluginResult:pluginResult callbackId:strongSelf.logCallbackId];
                    }
                }
            }
        }

        [fileHandle closeFile];
    });

    dispatch_source_set_cancel_handler(self.logFileSource, ^{
        close(fileDescriptor);
    });

    dispatch_resume(self.logFileSource);

    // Send initial success response
    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Log monitoring started"];
    [pluginResult setKeepCallbackAsBool:YES];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stop:(CDVInvokedUrlCommand*)command {
    [self stopMonitoring];

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Log monitoring stopped"];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)stopMonitoring {
    if (self.logFileSource) {
        dispatch_source_cancel(self.logFileSource);
        self.logFileSource = nil;
    }
    self.logCallbackId = nil;
}

- (void)getLog:(CDVInvokedUrlCommand*)command {


    NSString* callbackId = command.callbackId;
    if (command.arguments.count != 2)
    {
        NSString* error = @"missing arguments in getLog";
        NSLog(@"CDVNativeLogs: %@",error);
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
        return ;
    }

    int nbLines = 1000;  // maxline
    BOOL bClipboard = false;
    id value = [command argumentAtIndex:0];
    if ([value isKindOfClass:[NSNumber class]]) {
        nbLines = [value intValue];
    }

    value = [command argumentAtIndex:1];
    if ([value isKindOfClass:[NSNumber class]]) {
        bClipboard = [value boolValue];
    }


    NSString* pathForLog = [self getPath];
    NSString *stringContent = [NSString stringWithContentsOfFile:pathForLog encoding:NSUTF8StringEncoding error:nil];

    NSString* log = @"";
    NSArray *brokenByLines=[stringContent componentsSeparatedByString:@"\n"];


    NSRange endRange = NSMakeRange(brokenByLines.count >= nbLines ?
                                   brokenByLines.count - nbLines
                                : 0, MIN(brokenByLines.count, nbLines));

    for(id line in [brokenByLines subarrayWithRange:endRange])
    {
        if ([line length]==0)
            continue ;

        log = [log stringByAppendingString:line];
        log = [log stringByAppendingString:@"\n"];
    }

    if (bClipboard)
    {
        UIPasteboard *pb = [UIPasteboard generalPasteboard];
        [pb setString:log];
    }

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:log];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:callbackId];
}


@end
