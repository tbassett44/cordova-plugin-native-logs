#import <Cordova/CDV.h>

@interface CDVNativeLogs : CDVPlugin

@property (nonatomic, strong) NSString *logCallbackId;
@property (nonatomic, strong) dispatch_source_t logFileSource;
@property (nonatomic, assign) unsigned long long lastFileOffset;

- (void)pluginInitialize;
- (NSString*) getPath;
- (void) init:(CDVInvokedUrlCommand*)command;
- (void) stop:(CDVInvokedUrlCommand*)command;
- (void) getLog:(CDVInvokedUrlCommand*)command;

@end