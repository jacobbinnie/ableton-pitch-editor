#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include "ext.h"
#include "ext_obex.h"

static t_class *probe_class;
static NSString *logPath;
static void logLine(NSString *line) {
    @autoreleasepool {
        NSString *s = [line stringByAppendingString:@"\n"];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (!h) { [s writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil]; return; }
        [h seekToEndOfFile]; [h writeData:[s dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile];
    }
}

static id attr(id obj, NSString *key) {
    @try {
        if ([key isEqualToString:NSAccessibilityIdentifierAttribute] && [obj respondsToSelector:@selector(accessibilityIdentifier)]) return [obj accessibilityIdentifier];
        if ([key isEqualToString:NSAccessibilityRoleAttribute] && [obj respondsToSelector:@selector(accessibilityRole)]) return [obj accessibilityRole];
        if ([key isEqualToString:NSAccessibilityChildrenAttribute] && [obj respondsToSelector:@selector(accessibilityChildren)]) return [obj accessibilityChildren];
        if ([key isEqualToString:NSAccessibilityPositionAttribute] && [obj respondsToSelector:@selector(accessibilityFrame)]) return NSStringFromRect([obj accessibilityFrame]);
        if ([obj respondsToSelector:@selector(accessibilityAttributeValue:)])
            return [obj accessibilityAttributeValue:key];
    } @catch (NSException *e) { }
    return nil;
}
static void dump(id obj, int depth, int *budget) {
    if (!obj || depth > 15 || --*budget < 0) return;
    NSString *ident = attr(obj, NSAccessibilityIdentifierAttribute);
    NSString *role = attr(obj, NSAccessibilityRoleAttribute);
    if (depth < 3 || [ident hasPrefix:@"ClipDetail"])
        logLine([NSString stringWithFormat:@"%d %@ id=%@ role=%@ pos=%@ size=%@", depth, NSStringFromClass([obj class]), ident, role, attr(obj, NSAccessibilityPositionAttribute), attr(obj, NSAccessibilitySizeAttribute)]);
    id children = attr(obj, NSAccessibilityChildrenAttribute);
    if ([children isKindOfClass:[NSArray class]]) for (id child in children) dump(child, depth+1, budget);
}
static void inspect(void) {
    logLine([NSString stringWithFormat:@"PROCESS %@ pid=%d bundle=%@ mainThread=%d", NSProcessInfo.processInfo.processName, NSProcessInfo.processInfo.processIdentifier, NSBundle.mainBundle.bundleIdentifier, NSThread.isMainThread]);
    for (NSWindow *w in NSApp.windows) {
        logLine([NSString stringWithFormat:@"WINDOW %@ class=%@ frame=%@ content=%@", w.title, NSStringFromClass(w.class), NSStringFromRect(w.frame), NSStringFromClass(w.contentView.class)]);
        int budget=5000; dump(w, 0, &budget);
    }
}
static void describeClass(NSString *name) {
    Class c=NSClassFromString(name);
    if (!c) return;
    logLine([NSString stringWithFormat:@"CLASS %@ superclass=%@",name,NSStringFromClass(class_getSuperclass(c))]);
    unsigned int count=0;
    Ivar *ivars=class_copyIvarList(c,&count);
    for(unsigned int i=0;i<count;i++) logLine([NSString stringWithFormat:@"IVAR %s type=%s offset=%td",ivar_getName(ivars[i]),ivar_getTypeEncoding(ivars[i]),ivar_getOffset(ivars[i])]);
    free(ivars);
    Method *methods=class_copyMethodList(c,&count);
    for(unsigned int i=0;i<count;i++) logLine([NSString stringWithFormat:@"METHOD %@ %s",NSStringFromSelector(method_getName(methods[i])),method_getTypeEncoding(methods[i])]);
    free(methods);
}
typedef struct { t_object ob; } t_probe;
static void probe_bang(t_probe *x) { dispatch_async(dispatch_get_main_queue(), ^{ inspect(); }); }
static void *probe_new(void) {
    t_probe *x=(t_probe *)object_alloc(probe_class);
    dispatch_async(dispatch_get_main_queue(), ^{ inspect(); });
    dispatch_async(dispatch_get_main_queue(), ^{
        describeClass(@"TAxPlatformNode");
        describeClass(@"TCocoaMainView");
        for(int i=1;i<=12;i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,i*5*NSEC_PER_SEC),dispatch_get_main_queue(),^{inspect();});
    });
    return x;
}
C74_EXPORT void ext_main(void *r) {
    logPath=@PITCH_PROBE_LOG_PATH;
    t_class *c=class_new("pitchprobe3", (method)probe_new, NULL, sizeof(t_probe), NULL, 0);
    class_addmethod(c,(method)probe_bang,"bang",0);
    class_register(CLASS_BOX,c); probe_class=c;
}
