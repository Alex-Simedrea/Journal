#import "PrivateAppLauncher.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

static BOOL JournalOpenWithSharedApplication(NSURL *url) {
    Class applicationClass = objc_getClass("UIApplication");
    SEL sharedSelector = NSSelectorFromString(@"sharedApplication");

    if (applicationClass == Nil ||
        ![applicationClass respondsToSelector:sharedSelector]) {
        NSLog(@"Journal launcher: UIApplication is unavailable");
        return NO;
    }

    id application = ((id (*)(id, SEL))objc_msgSend)(
        applicationClass,
        sharedSelector
    );
    SEL openSelector = NSSelectorFromString(
        @"openURL:options:completionHandler:"
    );

    if (application == nil ||
        ![application respondsToSelector:openSelector]) {
        NSLog(@"Journal launcher: UIApplication cannot open URLs");
        return NO;
    }

    ((void (*)(id, SEL, NSURL *, NSDictionary *, id))objc_msgSend)(
        application,
        openSelector,
        url,
        @{},
        nil
    );
    NSLog(@"Journal launcher: requested UIApplication URL open");
    return YES;
}

static id _Nullable JournalDefaultApplicationWorkspace(void) {
    dlopen(
        "/System/Library/Frameworks/CoreServices.framework/CoreServices",
        RTLD_LAZY
    );
    dlopen(
        "/System/Library/Frameworks/MobileCoreServices.framework/"
        "MobileCoreServices",
        RTLD_LAZY
    );

    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    SEL defaultSelector = NSSelectorFromString(@"defaultWorkspace");

    if (workspaceClass == Nil ||
        ![workspaceClass respondsToSelector:defaultSelector]) {
        NSLog(@"Journal launcher: LSApplicationWorkspace is unavailable");
        return nil;
    }

    return ((id (*)(id, SEL))objc_msgSend)(
        workspaceClass,
        defaultSelector
    );
}

static BOOL JournalOpenWithApplicationWorkspace(
    NSURL *url,
    NSString *bundleIdentifier
) {
    id workspace = JournalDefaultApplicationWorkspace();
    if (workspace == nil) {
        return NO;
    }

    BOOL madeRequest = NO;
    SEL sensitiveURLSelector = NSSelectorFromString(
        @"openSensitiveURL:withOptions:"
    );
    if ([workspace respondsToSelector:sensitiveURLSelector]) {
        BOOL didOpen = ((BOOL (*)(id, SEL, NSURL *, NSDictionary *))
                        objc_msgSend)(
            workspace,
            sensitiveURLSelector,
            url,
            @{}
        );
        NSLog(
            @"Journal launcher: LS sensitive URL result = %@",
            didOpen ? @"YES" : @"NO"
        );
        madeRequest = YES;
    }

    SEL bundleSelector = NSSelectorFromString(
        @"openApplicationWithBundleID:"
    );
    if ([workspace respondsToSelector:bundleSelector]) {
        BOOL didOpen = ((BOOL (*)(id, SEL, NSString *))objc_msgSend)(
            workspace,
            bundleSelector,
            bundleIdentifier
        );
        NSLog(
            @"Journal launcher: LS bundle result = %@",
            didOpen ? @"YES" : @"NO"
        );
        madeRequest = YES;
    }

    return madeRequest;
}

static BOOL JournalOpenWithFrontBoard(
    NSURL *url,
    NSString *bundleIdentifier
) {
    void *framework = dlopen(
        "/System/Library/PrivateFrameworks/FrontBoardServices.framework/"
        "FrontBoardServices",
        RTLD_LAZY
    );
    if (framework == NULL) {
        framework = dlopen(
            "/System/Library/PrivateFrameworks/BackBoardServices.framework/"
            "BackBoardServices",
            RTLD_LAZY
        );
    }

    Class serviceClass = objc_getClass("FBSSystemService");
    if (serviceClass == Nil) {
        serviceClass = objc_getClass("BKSSystemService");
    }
    SEL sharedSelector = NSSelectorFromString(@"sharedService");
    id service = nil;
    if (serviceClass != Nil &&
        [serviceClass respondsToSelector:sharedSelector]) {
        service = ((id (*)(id, SEL))objc_msgSend)(
            serviceClass,
            sharedSelector
        );
    } else if (serviceClass != Nil) {
        service = ((id (*)(id, SEL))objc_msgSend)(
            serviceClass,
            NSSelectorFromString(@"new")
        );
    }

    if (service == nil) {
        NSLog(@"Journal launcher: FBSSystemService is unavailable");
        return NO;
    }

    NSDictionary *options = @{
        @"__ActivateSuspended": @NO,
        @"__UnlockDevice": @YES,
    };
    void (^resultHandler)(NSError *) = ^(NSError *error) {
        NSLog(
            @"Journal launcher: FrontBoard result = %@",
            error.localizedDescription ?: @"success"
        );
    };
    unsigned clientPort = 0;
    SEL createPortSelector = NSSelectorFromString(@"createClientPort");
    if ([service respondsToSelector:createPortSelector]) {
        clientPort = ((unsigned (*)(id, SEL))objc_msgSend)(
            service,
            createPortSelector
        );
    }

    BOOL madeRequest = NO;
    SEL openURLSelector = NSSelectorFromString(
        @"openURL:application:options:clientPort:withResult:"
    );
    if ([service respondsToSelector:openURLSelector]) {
        ((void (*)(id, SEL, NSURL *, NSString *, NSDictionary *, unsigned, id))
         objc_msgSend)(
            service,
            openURLSelector,
            url,
            bundleIdentifier,
            options,
            clientPort,
            resultHandler
        );
        NSLog(@"Journal launcher: requested FrontBoard URL open");
        madeRequest = YES;
    }

    SEL clientPortOpenSelector = NSSelectorFromString(
        @"openApplication:options:clientPort:withResult:"
    );
    if ([service respondsToSelector:clientPortOpenSelector]) {
        ((void (*)(id, SEL, NSString *, NSDictionary *, unsigned, id))
         objc_msgSend)(
            service,
            clientPortOpenSelector,
            bundleIdentifier,
            options,
            clientPort,
            resultHandler
        );
        NSLog(@"Journal launcher: requested FrontBoard client-port open");
        madeRequest = YES;
    }

    SEL simpleOpenSelector = NSSelectorFromString(
        @"openApplication:options:withResult:"
    );
    if ([service respondsToSelector:simpleOpenSelector]) {
        ((void (*)(id, SEL, NSString *, NSDictionary *, id))objc_msgSend)(
            service,
            simpleOpenSelector,
            bundleIdentifier,
            options,
            resultHandler
        );
        NSLog(@"Journal launcher: requested FrontBoard simple open");
        madeRequest = YES;
    }

    if (!madeRequest) {
        NSLog(@"Journal launcher: FBS open selectors are unavailable");
    }
    return madeRequest;
}

BOOL JournalOpenContainingApplication(
    NSURL *url,
    NSString *bundleIdentifier
) {
    BOOL applicationRequest = JournalOpenWithSharedApplication(url);
    BOOL workspaceRequest = JournalOpenWithApplicationWorkspace(
        url,
        bundleIdentifier
    );
    BOOL frontBoardRequest = JournalOpenWithFrontBoard(
        url,
        bundleIdentifier
    );

    return applicationRequest || workspaceRequest || frontBoardRequest;
}
