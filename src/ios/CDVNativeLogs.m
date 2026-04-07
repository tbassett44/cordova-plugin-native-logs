#import "CDVNativeLogs.h"
#import <Cordova/CDV.h>
#import <os/log.h>

// Set to YES to echo JS console.log/error/warn to os_log (visible in idevicesyslog / Console.app)
static BOOL kJSConsoleOsLogEnabled = NO;

@implementation CDVNativeLogs

@synthesize logCallbackId;
@synthesize logFileSource;
@synthesize lastFileOffset;
@synthesize consoleBridgeActive;

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

    // Inject JS console capture bridge (only when debugging is active)
    [self startConsoleBridge];

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

    // Remove JS console capture bridge
    [self stopConsoleBridge];
}

#pragma mark - JS Console Bridge

- (void)startConsoleBridge {
    if (self.consoleBridgeActive) return;

    UIView *webView = self.webViewEngine.engineWebView;
    if (![webView isKindOfClass:[WKWebView class]]) return;

    WKWebView *wk = (WKWebView *)webView;
    [wk.configuration.userContentController addScriptMessageHandler:self name:@"nativeConsole"];

    NSString *js =
        @"(function(){"
        "if(window.__nativeConsoleActive) return;"
        "window.__nativeConsoleActive=true;"
        "window.__origLog=console.log;window.__origErr=console.error;window.__origWarn=console.warn;"
        "function _s(a){try{return typeof a==='object'?JSON.stringify(a):String(a)}catch(e){return String(a)}}"
        "function _send(l,args){try{window.webkit.messageHandlers.nativeConsole.postMessage({level:l,msg:Array.prototype.slice.call(args).map(_s).join(' ')})}catch(e){}}"
        "console.log=function(){window.__origLog.apply(console,arguments);_send('log',arguments)};"
        "console.error=function(){window.__origErr.apply(console,arguments);_send('error',arguments)};"
        "console.warn=function(){window.__origWarn.apply(console,arguments);_send('warn',arguments)};"
        "})();";

    [wk evaluateJavaScript:js completionHandler:nil];
    self.consoleBridgeActive = YES;
    NSLog(@"[NativeLogs] JS console capture bridge injected");
}

- (void)stopConsoleBridge {
    if (!self.consoleBridgeActive) return;

    UIView *webView = self.webViewEngine.engineWebView;
    if (![webView isKindOfClass:[WKWebView class]]) return;

    WKWebView *wk = (WKWebView *)webView;

    // Restore original console methods
    NSString *js =
        @"(function(){"
        "if(window.__origLog){console.log=window.__origLog;delete window.__origLog;}"
        "if(window.__origErr){console.error=window.__origErr;delete window.__origErr;}"
        "if(window.__origWarn){console.warn=window.__origWarn;delete window.__origWarn;}"
        "delete window.__nativeConsoleActive;"
        "})();";

    [wk evaluateJavaScript:js completionHandler:nil];
    [wk.configuration.userContentController removeScriptMessageHandlerForName:@"nativeConsole"];
    self.consoleBridgeActive = NO;
    NSLog(@"[NativeLogs] JS console capture bridge removed");
}

#pragma mark - WKScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message
{
    if ([message.name isEqualToString:@"nativeConsole"]) {
        NSDictionary *body = message.body;
        NSString *level = body[@"level"] ?: @"log";
        NSString *msg = body[@"msg"] ?: @"";
        if (kJSConsoleOsLogEnabled) {
            os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[JSConsole][%{public}@] %{public}@", level, msg);
        }
    }
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
