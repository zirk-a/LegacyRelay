#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "JITEnabler.h"
#import "IOSBootstrap.h"
#import <sys/utsname.h>
#import <stdio.h>
#import <string.h>

static int32_t LRCurrentTabPID = 0;

static dispatch_queue_t LRJITQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create(
            "com.legacyrelay.officialreynardjit",
            DISPATCH_QUEUE_SERIAL
        );
    });

    return queue;
}

static BOOL LRJITEnabled(void) {
    return [[NSUserDefaults standardUserDefaults]
        boolForKey:@"LegacyRelay.JIT.enabled"];
}

static BOOL LRHasTXMSupport(void) {
    NSOperatingSystemVersion v =
        NSProcessInfo.processInfo.operatingSystemVersion;
    if (v.majorVersion < 26) {
        return NO;
    }

    struct utsname systemInfo;
    if (uname(&systemInfo) != 0) {
        return NO;
    }
    const char *hardware = systemInfo.machine;

    if (v.majorVersion >= 27) {
        return strcmp(hardware, "iPad8,11") != 0 &&
               strcmp(hardware, "iPad8,12") != 0;
    }

    int major = -1, minor = -1;
    double threshold = 0.0;
    if (sscanf(hardware, "iPhone%d,%d", &major, &minor) == 2) {
        threshold = 14.2;
    } else if (sscanf(hardware, "iPad%d,%d", &major, &minor) == 2) {
        threshold = 14.5;
    } else {
        return NO;
    }
    if (major < 0 || minor < 0) {
        return NO;
    }

    
    double divisor = 10.0;
    int t = minor;
    while (t >= 10) {
        divisor *= 10.0;
        t /= 10;
    }
    const double modelVersion = (double)major + (double)minor/divisor;
    return modelVersion >= threshold;
}

static JITRuntimeInfo LRRuntimeInfo(void) {
    NSOperatingSystemVersion v =
        NSProcessInfo.processInfo.operatingSystemVersion;

    DeviceOSVersion os = {
        .majorVersion = (int32_t)v.majorVersion,
        .minorVersion = (int32_t)v.minorVersion,
        .patchVersion = (int32_t)v.patchVersion
    };

    JITRuntimeInfo info = {
        .hasTXMSupport = LRHasTXMSupport() ? 1 : 0,
        .deviceOSVersion = os
    };

    return info;
}

static void LRPublish(
    NSString *state,
    NSString *detail
) {
    NSUserDefaults *defaults =
        NSUserDefaults.standardUserDefaults;

    [defaults
        setObject:(state ?: @"off")
        forKey:@"LegacyRelay.JIT.state"];

    [defaults
        setObject:(detail ?: @"")
        forKey:@"LegacyRelay.JIT.detail"];

    dispatch_async(
        dispatch_get_main_queue(),
        ^{
            [NSNotificationCenter.defaultCenter
                postNotificationName:
                    @"LegacyRelay.JITStatusDidChange"
                object:nil];
        }
    );
}

static void LRReport(
    int32_t pid,
    BOOL enabled
) {
    if (pid <= 0) {
        return;
    }

    ReportJITStatusForChild(
        pid,
        enabled,
        LRRuntimeInfo()
    );
}

static void LRTryOfficialReynardJIT(void) {
    int32_t pid = LRCurrentTabPID;

    if (!LRJITEnabled()) {
        LRReport(pid, NO);
        LRPublish(
            @"off",
            @"JIT disabled."
        );
        return;
    }

    if (pid <= 0) {
        LRPublish(
            @"waiting",
            @"Waiting for a Gecko tab process."
        );
        return;
    }

    LRPublish(
        @"enabling",
        @"Reynard JITEnabler is attaching…"
    );

    dispatch_async(
        LRJITQueue(),
        ^{
            NSError *error = nil;

            BOOL ok =
                [[JITEnabler shared]
                    enableJITForPID:pid
                    hasTXMSupport:LRHasTXMSupport()
                    error:&error];

            if (pid != LRCurrentTabPID) {
                return;
            }

            LRReport(pid, ok);

            if (ok) {
                LRPublish(
                    @"active",
                    @"Official Reynard JITEnabler completed successfully."
                );
            } else {
                NSString *detail =
                    error.localizedDescription
                    ?: @"Official Reynard JITEnabler returned failure without an error message.";

                LRPublish(
                    @"failed",
                    detail
                );

                NSLog(
                    @"LegacyRelay official Reynard JIT FAILED pid=%d error=%@",
                    pid,
                    detail
                );
            }
        }
    );
}

void LegacyRelaySetBuiltInJITEnabled(
    int32_t enabledValue
) {
    BOOL enabled =
        enabledValue != 0;

    [NSUserDefaults.standardUserDefaults
        setBool:enabled
        forKey:@"LegacyRelay.JIT.enabled"];

    if (!enabled) {
        [[JITEnabler shared]
            detachAllJITSessions];

        LRReport(
            LRCurrentTabPID,
            NO
        );

        LRPublish(
            @"off",
            @"JIT disabled."
        );

        return;
    }

    LRTryOfficialReynardJIT();
}

@interface LegacyRelayOfficialJITController : NSObject
@property(nonatomic, strong) id childToken;
@end

@implementation LegacyRelayOfficialJITController

- (instancetype)init {
    self = [super init];

    if (!self) {
        return nil;
    }

    if (LRJITEnabled()) {
        LRPublish(
            @"waiting",
            @"Waiting for a Gecko tab process."
        );
    } else {
        LRPublish(
            @"off",
            @"JIT disabled."
        );
    }

    self.childToken =
        [NSNotificationCenter.defaultCenter
            addObserverForName:
                @"GeckoRuntime.ChildProcessDidStart"
            object:nil
            queue:NSOperationQueue.mainQueue
            usingBlock:^(
                NSNotification *notification
            ) {
                NSNumber *pidValue =
                    notification.userInfo[@"pid"];

                NSString *processType =
                    notification.userInfo[@"processType"];

                if (![pidValue
                        isKindOfClass:NSNumber.class] ||
                    ![processType
                        isKindOfClass:NSString.class]) {
                    return;
                }

                NSString *normalized =
                    [[processType
                        stringByTrimmingCharactersInSet:
                            NSCharacterSet
                                .whitespaceAndNewlineCharacterSet]
                        lowercaseString];

                if (![normalized
                        isEqualToString:@"tab"]) {
                    LRReport(
                        pidValue.intValue,
                        NO
                    );
                    return;
                }

                LRCurrentTabPID =
                    pidValue.intValue;

                LRTryOfficialReynardJIT();
            }];

    return self;
}

@end

static LegacyRelayOfficialJITController *
    LROfficialJITController = nil;

__attribute__((constructor))
static void LegacyRelayStartOfficialJIT(void) {
    @autoreleasepool {
        LROfficialJITController =
            [LegacyRelayOfficialJITController new];
    }
}
