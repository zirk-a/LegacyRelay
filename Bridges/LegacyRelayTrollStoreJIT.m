#include <xpc/xpc.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>
#import <sys/types.h>
#import <errno.h>

#include "IOSBootstrap.h"

extern char **environ;

extern int posix_spawnattr_set_persona_np(
    posix_spawnattr_t * __restrict,
    uid_t,
    uint32_t
);

extern int posix_spawnattr_set_persona_uid_np(
    posix_spawnattr_t * __restrict,
    uid_t
);

extern int posix_spawnattr_set_persona_gid_np(
    posix_spawnattr_t * __restrict,
    gid_t
);

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif

static int LRSpawnRoot(
    NSString *path,
    NSArray<NSString *> *arguments
) {
    if (path.length == 0) {
        return ENOENT;
    }

    NSMutableArray<NSString *> *args =
        [arguments mutableCopy];

    [args insertObject:path atIndex:0];

    NSUInteger count = args.count;
    char **argv =
        calloc(count + 1, sizeof(char *));

    if (!argv) {
        return ENOMEM;
    }

    for (NSUInteger index = 0; index < count; index++) {
        argv[index] =
            strdup(args[index].UTF8String);
    }

    argv[count] = NULL;

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

    posix_spawnattr_set_persona_np(
        &attr,
        99,
        POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
    );

    posix_spawnattr_set_persona_uid_np(
        &attr,
        0
    );

    posix_spawnattr_set_persona_gid_np(
        &attr,
        0
    );

    pid_t child = 0;

    int spawnResult = posix_spawn(
        &child,
        path.UTF8String,
        NULL,
        &attr,
        argv,
        environ
    );

    posix_spawnattr_destroy(&attr);

    for (NSUInteger index = 0; index < count; index++) {
        free(argv[index]);
    }

    free(argv);

    if (spawnResult != 0) {
        return spawnResult;
    }

    int status = 0;

    if (waitpid(child, &status, 0) < 0) {
        return errno != 0 ? errno : ECHILD;
    }

    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    }

    if (WIFSIGNALED(status)) {
        return 128 + WTERMSIG(status);
    }

    return ECHILD;
}

static NSString *LRPtraceJITPath(void) {
    NSBundle *bundle = NSBundle.mainBundle;
    NSArray<NSString *> *helperNames =
        @[@"ts_ptrace_jit", @"jb_ptrace_jit"];

    for (NSString *name in helperNames) {
        NSString *root = [
            bundle.bundlePath
            stringByAppendingPathComponent:name
        ];

        if ([
            NSFileManager.defaultManager
            isExecutableFileAtPath:root
        ]) {
            return root;
        }

        NSURL *auxiliary =
            [bundle URLForAuxiliaryExecutable:name];

        if (auxiliary.path.length > 0 &&
            [
                NSFileManager.defaultManager
                isExecutableFileAtPath:auxiliary.path
            ]) {
            return auxiliary.path;
        }
    }

    return nil;
}

static JITRuntimeInfo LRRuntimeInfo(void) {
    NSOperatingSystemVersion version =
        NSProcessInfo.processInfo.operatingSystemVersion;

    DeviceOSVersion osVersion = {
        .majorVersion =
            (int32_t)version.majorVersion,
        .minorVersion =
            (int32_t)version.minorVersion,
        .patchVersion =
            (int32_t)version.patchVersion
    };

    JITRuntimeInfo info = {
        .hasTXMSupport = 0,
        .deviceOSVersion = osVersion
    };

    return info;
}

static void LRReportDisabled(int32_t pid) {
    ReportJITStatusForChild(
        pid,
        false,
        LRRuntimeInfo()
    );
}

static void LREnableJITForTabPID(int32_t pid) {
    if (pid <= 0) {
        return;
    }

    NSString *helper =
        LRPtraceJITPath();

    if (helper.length == 0) {
        NSLog(
            @"LegacyRelay JIT: ptrace_jit missing for pid=%d",
            pid
        );

        LRReportDisabled(pid);
        return;
    }

    int result = LRSpawnRoot(
        helper,
        @[
            [NSString stringWithFormat:@"%d", pid]
        ]
    );

    BOOL enabled =
        (result == 0);

    ReportJITStatusForChild(
        pid,
        enabled,
        LRRuntimeInfo()
    );

    NSLog(
        @"LegacyRelay JIT: pid=%d result=%d enabled=%@",
        pid,
        result,
        enabled ? @"YES" : @"NO"
    );

    NSUserDefaults *stateDefaults = NSUserDefaults.standardUserDefaults;
    [stateDefaults setObject:(enabled ? @"active" : @"failed")
                    forKey:@"LegacyRelay.JIT.state"];
    [stateDefaults setObject:[NSString stringWithFormat:@"ptrace_jit exit=%d", result]
                    forKey:@"LegacyRelay.JIT.detail"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:
            @"LegacyRelay.JITStatusDidChange" object:nil];
    });
}

@interface LegacyRelayTrollStoreJIT : NSObject
@property(nonatomic, strong) id token;
@end

@implementation LegacyRelayTrollStoreJIT

- (instancetype)init {
    self = [super init];

    if (!self) {
        return nil;
    }

    self.token = [
        NSNotificationCenter.defaultCenter
        addObserverForName:@"GeckoRuntime.ChildProcessDidStart"
        object:nil
        queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *notification) {
            NSNumber *pidValue =
                notification.userInfo[@"pid"];

            NSString *processType =
                notification.userInfo[@"processType"];

            if (![
                pidValue
                isKindOfClass:NSNumber.class
            ] ||
                ![
                    processType
                    isKindOfClass:NSString.class
                ]) {
                return;
            }

            int32_t pid =
                pidValue.intValue;

            NSString *normalized = [
                processType
                stringByTrimmingCharactersInSet:
                    NSCharacterSet
                        .whitespaceAndNewlineCharacterSet
            ].lowercaseString;

            if (![
                normalized
                isEqualToString:@"tab"
            ]) {
                LRReportDisabled(pid);
                return;
            }

            dispatch_async(
                dispatch_get_global_queue(
                    QOS_CLASS_USER_INITIATED,
                    0
                ),
                ^{
                    LREnableJITForTabPID(pid);
                }
            );
        }
    ];

    NSLog(
        @"LegacyRelay JIT: child-process observer installed"
    );

    return self;
}

@end

static LegacyRelayTrollStoreJIT *LRJITController = nil;

__attribute__((constructor))
static void LegacyRelayStartTrollStoreJITParity(void) {
    @autoreleasepool {
        LRJITController =
            [LegacyRelayTrollStoreJIT new];
    }
}

// Expose the ABI already used by the newer Swift status model.
// TrollStore does NOT need a pairing file, VPN, or RPPairing to attach JIT.
void LegacyRelaySetBuiltInJITEnabled(int32_t value) {
    BOOL enabled = value != 0;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:enabled forKey:@"LegacyRelay.JIT.enabled"];
    [defaults setObject:(enabled ? @"waiting" : @"off")
                    forKey:@"LegacyRelay.JIT.state"];
    [defaults setObject:(enabled ? @"Waiting for a Gecko tab process." : @"JIT disabled.")
                    forKey:@"LegacyRelay.JIT.detail"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:
            @"LegacyRelay.JITStatusDidChange" object:nil];
    });
}

