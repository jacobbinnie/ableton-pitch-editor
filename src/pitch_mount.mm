#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include "ext.h"
#include "ext_obex.h"

// One-shot, reversible native-host attachment experiment. No executable patch.
extern "C" void pitch_call_factory(void *, void **);
static t_class *klass;
static void *host;
static bool attempted;
static uintptr_t slide;
static NSView *testView;
static void record(NSString *message) {
    NSString *line=[message stringByAppendingString:@"\n"];
    NSFileHandle *f=[NSFileHandle fileHandleForWritingAtPath:@PITCH_MOUNT_LOG];
    if(!f){[line writeToFile:@PITCH_MOUNT_LOG atomically:YES encoding:NSUTF8StringEncoding error:nil];return;}
    [f seekToEndOfFile];[f writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];[f closeFile];
}
static bool readMemory(uintptr_t address, void *out, size_t bytes) {
    mach_vm_size_t n=0;
    return address && mach_vm_read_overwrite(mach_task_self(),address,bytes,(mach_vm_address_t)out,&n)==KERN_SUCCESS && n==bytes;
}
static uintptr_t word(uintptr_t p) {uintptr_t value=0;readMemory(p,&value,sizeof(value));return value;}
static bool tableIs(uintptr_t p,uintptr_t table){return p && word(p)==table+slide;}
static void detach() {
    if(!host)return;
    [testView removeFromSuperview];testView=nil;
    uintptr_t parent=word((uintptr_t)host+0x60);
    // Only detach the host that this experiment created, via its actual parent.
    if(parent && tableIs(parent,0x106b4d2a0) && word(word(parent)+0x270)==slide+0x1017d23a8)
        ((void(*)(void*,void*,bool))(slide+0x1017d23a8))((void*)parent,host,false);
    if(word((uintptr_t)host+0x60)==0) {
        ((void(*)(void**))(slide+0x10179ea38))(&host);
        host=nullptr;
        record(@"DETACHED native test host; factory reference released");
    } else record(@"DETACH deferred: parent differs; retained host left to process teardown");
}
static void mount(uintptr_t editor) {
    if(attempted)return;
    attempted=true;
    if(!tableIs(editor,0x106b4d2a0) || word(word(editor)+0x268)!=slide+0x1017d1fb8)return;
    record(@"BEGIN native host factory");
    pitch_call_factory((void*)(slide+0x10179eb40),&host);
    if(!tableIs((uintptr_t)host,0x10671d9c8)){record(@"ABORT unexpected host vtable");return;}
    // The size setter takes two 32-bit coordinates packed in x1.
    ((void(*)(void*,uint64_t))(slide+0x1017cefbc))(host,260ULL|(90ULL<<32));
    ((void(*)(void*,void*,void*))(slide+0x1017d1fb8))((void*)editor,host,nullptr);
    record([NSString stringWithFormat:@"ATTACHED host=%p parent=0x%lx",host,(unsigned long)word((uintptr_t)host+0x60)]);
    uintptr_t handle=word((uintptr_t)host+0x170);
    if(!handle) {record(@"NO NATIVE HANDLE after attachment");detach();return;}
    // StrongRef's sole field holds an Objective-C object, confirmed by its
    // retain/release helpers. The host is still retained by this experiment.
    id native=(__bridge id)(void*)handle;
    if(![native isKindOfClass:[NSView class]]) {record(@"ABORT handle is not NSView");detach();return;}
    NSView *container=native;
    testView=[[NSView alloc] initWithFrame:container.bounds];
    testView.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    testView.wantsLayer=YES;testView.layer.backgroundColor=NSColor.systemPurpleColor.CGColor;
    testView.accessibilityIdentifier=@"PitchEditor.NativeMountTest";
    NSTextField *label=[NSTextField labelWithString:@"Native pitch canvas attachment test"];
    label.frame=NSMakeRect(8,20,245,40);label.textColor=NSColor.whiteColor;
    [testView addSubview:label];[container addSubview:testView];
    record([NSString stringWithFormat:@"MOUNTED nativeClass=%@ bounds=%@ window=%@",NSStringFromClass(container.class),NSStringFromRect(container.bounds),container.window.title]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{detach();});
}
static void visit(id node,int depth,int *budget) {
    if(!node || depth>15 || --*budget<0 || attempted)return;
    if([node respondsToSelector:@selector(accessibilityIdentifier)] &&
       [[node accessibilityIdentifier] isEqual:@"ClipDetailView.WarpedAudioTimelineEditor"] &&
       [NSStringFromClass([node class]) isEqual:@"TAxPlatformNode"]) {
        Ivar ivar=class_getInstanceVariable([node class],"mpProxy");
        if(ivar && ivar_getOffset(ivar)==8) {
            uintptr_t proxy=word((uintptr_t)(__bridge void*)node+32);
            if(tableIs(proxy,0x106716cd0))mount(word(proxy+0x28));
        }
    }
    if([node respondsToSelector:@selector(accessibilityChildren)])
        for(id child in [node accessibilityChildren])visit(child,depth+1,budget);
}
static void *create() {
    t_object *obj=(t_object*)object_alloc(klass);
    if(![NSBundle.mainBundle.bundlePath isEqual:@PITCH_LIVE_COPY])return obj;
    slide=_dyld_get_image_vmaddr_slide(0);
    record(@"LOADED native mount experiment; waiting for audio Clip View");
    for(int i=1;i<=60;i++)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,i*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        if(!attempted)for(NSWindow *w in NSApp.windows){int budget=5000;visit(w,0,&budget);}
    });
    return obj;
}
extern "C" C74_EXPORT void ext_main(void*) {
    klass=class_new("pitchmount1",(method)create,nullptr,sizeof(t_object),nullptr,0);
    class_register(CLASS_BOX,klass);
}
