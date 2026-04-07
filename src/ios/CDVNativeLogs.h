#import <Cordova/CDV.h>
#import <WebKit/WebKit.h>

@interface CDVNativeLogs : CDVPlugin <WKScriptMessageHandler>

@property (nonatomic, strong) NSString *logCallbackId;
@property (nonatomic, strong) dispatch_source_t logFileSource;
@property (nonatomic, assign) unsigned long long lastFileOffset;
@property (nonatomic, assign) BOOL consoleBridgeActive;

- (void)pluginInitialize;
- (NSString*) getPath;
- (void) init:(CDVInvokedUrlCommand*)command;
- (void) stop:(CDVInvokedUrlCommand*)command;
- (void) getLog:(CDVInvokedUrlCommand*)command;

@end