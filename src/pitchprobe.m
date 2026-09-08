#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include "ext.h"
#include "ext_obex.h"

static t_class *probe_class;
static NSString *logPath;
// Bounded read-only inspection of the selected UI nodes. Failed reads return
// false; never dereference private C++ pointers or invoke their vtables.
static BOOL readWord(uintptr_t address, uintptr_t *value) {
    mach_vm_size_t read=0;
    return address && mach_vm_read_overwrite(mach_task_self(),address,sizeof(*value),(mach_vm_address_t)value,&read)==KERN_SUCCESS && read==sizeof(*value);
}
static NSString *cppType(uintptr_t object, uintptr_t *vtable) {
    uintptr_t info=0,name=0;
    Dl_info image;
    if(!readWord(object,vtable) || !dladdr((void *)*vtable,&image) || image.dli_fbase!=(void *)_dyld_get_image_header(0))return nil;
    if(!readWord(*vtable-sizeof(uintptr_t),&info) || !readWord(info+sizeof(uintptr_t),&name))return nil;
    if(!dladdr((void *)name,&image) || image.dli_fbase!=(void *)_dyld_get_image_header(0))return nil;
    char buffer[192]={0};mach_vm_size_t read=0;
    if(mach_vm_read_overwrite(mach_task_self(),name,sizeof(buffer)-1,(mach_vm_address_t)buffer,&read)!=KERN_SUCCESS)return nil;
    return [NSString stringWithUTF8String:buffer];
}
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
static void pointerField(uintptr_t owner, size_t offset, NSString *path) {
    uintptr_t target=0,table=0;
    if(!readWord(owner+offset,&target))return;
    NSString *type=cppType(target,&table);
    if(type)logLine([NSString stringWithFormat:@"FIELD path=%@+0x%zx target=0x%lx type=%@ vtableFile=0x%lx",path,offset,(unsigned long)target,type,(unsigned long)(table-_dyld_get_image_vmaddr_slide(0))]);
}
static void identity(id obj, NSString *ident) {
    if(![NSStringFromClass([obj class]) isEqualToString:@"TAxPlatformNode"])return;
    if(![@[@"ClipDetailView",@"ClipDetailView.WarpedAudioTimelineEditor",@"ClipDetailView.ClipViewLoopBar",@"ClipDetailView.ClipContentHeader.PitchEditorButton"] containsObject:ident])return;
    Ivar ivar=class_getInstanceVariable([obj class],"mpProxy");
    if(!ivar || ivar_getOffset(ivar)!=8)return;
    uintptr_t proxy=0,owner=0,proxyTable=0,ownerTable=0;
    // TWeakReference's three pointer fields precede its object pointer.
    if(!readWord((uintptr_t)(__bridge void *)obj+ivar_getOffset(ivar)+3*sizeof(uintptr_t),&proxy))return;
    NSString *proxyType=cppType(proxy,&proxyTable);
    if(!proxyType || ![proxyType containsString:@"TAxProxy"])return;
    // Static TAxProxy constructor stores its owner argument at +0x28.
    if(!readWord(proxy+0x28,&owner))return;
    NSString *ownerType=cppType(owner,&ownerTable);
    intptr_t slide=_dyld_get_image_vmaddr_slide(0);
    logLine([NSString stringWithFormat:@"IDENTITY id=%@ ax=%p proxy=0x%lx proxyType=%@ owner=0x%lx ownerType=%@ ownerVTableFile=0x%lx",ident,obj,(unsigned long)proxy,proxyType,(unsigned long)owner,ownerType,(unsigned long)(ownerTable?ownerTable-slide:0)]);
    // Exact observed types/vtables guard the bounded, read-only field survey.
    // Pointer-shaped values with RTTI are candidates, not declared ownership.
    if([ownerType isEqualToString:@"15LClipDetailView"] && ownerTable-slide==0x106b07b68) {
        size_t offsets[]={0x310,0x320,0x398,0x3a0,0x3a8,0x3c8,0x3e0,0x3f8,0x410,0x428,0x438,0x480,0x4c0};
        for(size_t i=0;i<sizeof(offsets)/sizeof(*offsets);i++)pointerField(owner,offsets[i],ident);
        uintptr_t content=0;
        if(readWord(owner+0x310,&content)) {
            pointerField(content,0x2d8,@"ClipDetailView.content");
            uintptr_t area=0,table=0;
            if(readWord(content+0x2d8,&area) && [cppType(area,&table) isEqualToString:@"19LDetailTimelineArea"] && table-slide==0x106b12e80) {
                for(size_t offset=0x180;offset<0x220;offset+=8)pointerField(area,offset,@"ClipDetailView.timelineArea");
            }
        }
    }
    if([ownerType isEqualToString:@"26LWarpedAudioTimelineEditor"] && ownerTable-slide==0x106b4d2a0) {
        for(size_t offset=8;offset<0x508;offset+=8)pointerField(owner,offset,ident);
    }
}
static void dump(id obj, int depth, int *budget) {
    if (!obj || depth > 15 || --*budget < 0) return;
    NSString *ident = attr(obj, NSAccessibilityIdentifierAttribute);
    NSString *role = attr(obj, NSAccessibilityRoleAttribute);
    identity(obj,ident);
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
        for(int i=1;i<=24;i++) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,i*5*NSEC_PER_SEC),dispatch_get_main_queue(),^{inspect();});
    });
    return x;
}
C74_EXPORT void ext_main(void *r) {
    logPath=@PITCH_PROBE_LOG_PATH;
    t_class *c=class_new("pitchprobe6", (method)probe_new, NULL, sizeof(t_probe), NULL, 0);
    class_addmethod(c,(method)probe_bang,"bang",0);
    class_register(CLASS_BOX,c); probe_class=c;
}
