#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreText/CoreText.h>
#import <objc/runtime.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <algorithm>
#include <memory>
#include "pitch_canvas.hpp"
#include "ext.h"
#include "ext_obex.h"
#include "ext_dictobj.h"
#include "ext_dictionary.h"
#include "pitch_playback.hpp"

extern "C" void pitch_call_factory(void*,void**);
static uintptr_t slide;
static t_class *klass;
struct NativeObject {t_object ob; void *outlet; void *request; void *playOutlet; void *playRequest; bool warped,playing; bool arrangement,songPlaying,looping,muted; double songBeat,clipStart,clipEnd,startMarker,loopStart,loopEnd;};
static NativeObject *instance;
static NSTimer *timer,*playTimer;
static std::vector<pitch::WarpPoint> warpPoints;
static id eventMonitor;
static void *tabHost,*canvasHost,*selectorOwner;
// Desktop Live uses Ableton Sans Small; load it from the user's installed copy.
static NSFont *tabFont(){
    static NSFont *font;
    if(!font){
        NSURL *url=[NSURL fileURLWithPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/App-Resources/Fonts/AbletonSansSmall-Regular.ttf"]];
        CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url,kCTFontManagerScopeProcess,nullptr);
        NSArray *descriptors=CFBridgingRelease(CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url));
        if(descriptors.count){
            NSString *name=CFBridgingRelease(CTFontDescriptorCopyAttribute((__bridge CTFontDescriptorRef)descriptors[0],kCTFontNameAttribute));
            font=[NSFont fontWithName:name size:10];
        }
        if(!font)font=[NSFont systemFontOfSize:10];
    }
    return font;
}
static NSColor *gray(unsigned v){return [NSColor colorWithSRGBRed:v/255.0 green:v/255.0 blue:v/255.0 alpha:1];}
static void drawTab(NSString *title,NSRect rect,BOOL selected){
    [gray(selected?0x46:0x36) setFill];NSRectFill(rect);
    [gray(0x28) setFill];NSRectFill(NSMakeRect(NSMaxX(rect)-1,NSMinY(rect),1,rect.size.height));
    NSDictionary *attrs=@{NSFontAttributeName:tabFont(),NSForegroundColorAttributeName:gray(0x91)};
    NSSize text=[title sizeWithAttributes:attrs];
    [title drawAtPoint:NSMakePoint(round(NSMidX(rect)-text.width/2),round(NSMidY(rect)-text.height/2)) withAttributes:attrs];
}
@interface PitchTabButton20 : NSButton
@end
@implementation PitchTabButton20
- (void)drawRect:(NSRect)rect {drawTab(self.title,self.bounds,self.state==NSControlStateValueOn);}
- (void)setState:(NSControlStateValue)value {[super setState:value];self.needsDisplay=YES;}
@end
static NSButton *tabButton;
static uint32_t savedSelectedBackground,savedSelectedText;
static bool selectorColorsOverridden;
static PitchCanvas *canvas;
static uintptr_t selectedEditor,selectedClip,buttonOwner;
static NSRect tabFrame;
static bool pitchMode;
static bool analyzed;
static NSUInteger generation;
static void log(NSString *s) {
    NSFileHandle *f=[NSFileHandle fileHandleForWritingAtPath:@PITCH_NATIVE_LOG];
    NSData *data=[[s stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    if(!f){[data writeToFile:@PITCH_NATIVE_LOG atomically:YES];return;}
    [f seekToEndOfFile];[f writeData:data];[f closeFile];
}
static uintptr_t word(uintptr_t a){uintptr_t v=0;mach_vm_size_t n=0;if(a)mach_vm_read_overwrite(mach_task_self(),a,8,(mach_vm_address_t)&v,&n);return n==8?v:0;}
static bool tableIs(uintptr_t p,uintptr_t table){return p&&word(p)==slide+table;}
static NSString *type(uintptr_t p){
    uintptr_t v=word(p);Dl_info info;
    if(!v||!dladdr((void*)v,&info)||info.dli_fbase!=(void*)_dyld_get_image_header(0))return nil;
    uintptr_t name=word(word(v-8)+8);
    if(!name||!dladdr((void*)name,&info)||info.dli_fbase!=(void*)_dyld_get_image_header(0))return nil;
    char s[192]={};mach_vm_size_t n=0;
    if(mach_vm_read_overwrite(mach_task_self(),name,191,(mach_vm_address_t)s,&n)!=KERN_SUCCESS)return nil;
    return [NSString stringWithUTF8String:s];
}
static uintptr_t owner(id node){
    Ivar ivar=class_getInstanceVariable([node class],"mpProxy");
    if(!ivar||ivar_getOffset(ivar)!=8)return 0;
    uintptr_t proxy=word((uintptr_t)(__bridge void*)node+32);
    if(![type(proxy) containsString:@"AxProxy"])return 0;
    return word(proxy+0x28);
}
static NSView *nativeView(void *host){
    if(!tableIs((uintptr_t)host,0x10671d9c8))return nil;
    uintptr_t p=word((uintptr_t)host+0x170);if(!p)return nil;
    id v=(__bridge id)(void*)p;return [v isKindOfClass:NSView.class]?v:nil;
}
static void releaseHost(void **host){
    if(!*host)return;
    uintptr_t parent=word((uintptr_t)*host+0x60);
    if(parent&&word(word(parent)+0x270)==slide+0x1017d23a8)
        ((void(*)(void*,void*,bool))(slide+0x1017d23a8))((void*)parent,*host,false);
    if(!word((uintptr_t)*host+0x60)){((void(*)(void**))(slide+0x10179ea38))(host);*host=nullptr;}
}
static void resizeHost(void *host,int width,int height){
    if(host&&width>0&&height>0)((void(*)(void*,uint64_t))(slide+0x1017cefbc))(host,(uint32_t)width|((uint64_t)(uint32_t)height<<32));
}
static void *makeHost(uintptr_t parent,int w,int h){
    if(word(word(parent)+0x268)!=slide+0x1017d1fb8)return nullptr;
    void *hnd=nullptr;pitch_call_factory((void*)(slide+0x10179eb40),&hnd);
    if(!tableIs((uintptr_t)hnd,0x10671d9c8))return nullptr;
    resizeHost(hnd,w,h);
    ((void(*)(void*,void*,void*))(slide+0x1017d1fb8))((void*)parent,hnd,nullptr);
    if(!nativeView(hnd)){releaseHost(&hnd);return nullptr;}
    return hnd;
}
static NSSize sizeOf(uintptr_t view){
    uint64_t a=word(view+0x30),b=word(view+0x38);
    return NSMakeSize(std::max(0,(int32_t)b-(int32_t)a),std::max(0,(int32_t)(b>>32)-(int32_t)(a>>32)));
}
static uintptr_t findSelector(){
    uintptr_t row=word(word(buttonOwner+0x60)+0x60);
    uintptr_t end=row+0x48,node=word(row+0x50);
    for(int i=0;node&&node!=end&&i<32;i++,node=word(node+8)){
        uintptr_t child=word(node+0x10);
        log([NSString stringWithFormat:@"HEADER CHILD %@ size=%@",type(child),NSStringFromSize(sizeOf(child))]);
        if([type(child) containsString:@"ModeSwitchControl"])return child;
    }
    return 0;
}
static void closePitch(){
    pitchMode=false;++generation;
    [canvas removeFromSuperview];releaseHost(&canvasHost);
    // A retained native reference remains valid through header teardown.
    uintptr_t selector=(uintptr_t)selectorOwner;
    if(selectorColorsOverridden&&[type(selector) isEqual:@"18AModeSwitchControl"]){
        ((void(*)(void*,uint32_t))(slide+0x10358ca48))((void*)selector,savedSelectedBackground);
        ((void(*)(void*,uint32_t))(slide+0x10358ca78))((void*)selector,savedSelectedText);
    }
    selectorColorsOverridden=false;
    if(selectorOwner){((void(*)(void**))(slide+0x10358bc80))(&selectorOwner);selectorOwner=nullptr;}
    tabButton.state=NSControlStateValueOff;
    log(@"Pitch mode closed");
}
@interface PitchNativeActions20 : NSObject
- (void)toggle:(id)sender;
@end
static PitchNativeActions20 *actions;
@implementation PitchNativeActions20
- (void)toggle:(id)sender {
    (void)sender;
    if(pitchMode){closePitch();return;}
    if(!tableIs(selectedEditor,0x106b4d2a0))return;
    NSSize size=sizeOf(selectedEditor);
    canvasHost=makeHost(selectedEditor,size.width,size.height);
    NSView *container=nativeView(canvasHost);
    if(!container){log(@"Pitch canvas attachment failed");return;}
    if(!canvas){canvas=[[PitchCanvas alloc] initWithFrame:container.bounds];analyzed=false;}
    canvas.frame=container.bounds;canvas.embeddedTimeline=YES;
    canvas.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    canvas.accessibilityIdentifier=@"PitchEditor.Notes";
    [container addSubview:canvas];pitchMode=true;++generation;
    tabButton.state=NSControlStateValueOn;
    uintptr_t selector=findSelector();
    if(selector){
        uint32_t refs=(uint32_t)word(selector+8);
        if(refs>0&&refs<0x7fffffff){
            // Same TPtr retain used by SNewCompound<AModeSwitchControl> (+44..52).
            *(uint32_t*)(selector+8)=refs+1;selectorOwner=(void*)selector;
            // Verified property loader + setters: color IDs, not RGBA values.
            // Keep Live's own font, layout, antialiasing and theme renderer.
            savedSelectedBackground=(uint32_t)word(selector+0x32c);
            savedSelectedText=(uint32_t)word(selector+0x334);
            ((void(*)(void*,uint32_t))(slide+0x10358ca48))((void*)selector,(uint32_t)word(selector+0x330));
            ((void(*)(void*,uint32_t))(slide+0x10358ca78))((void*)selector,(uint32_t)word(selector+0x338));
            selectorColorsOverridden=true;
            log(@"Native selector colors overridden; original lettering preserved");
        }
    }
    log([NSString stringWithFormat:@"PITCH OPEN nativeParent=%@ nativeClass=%@ size=%@",type(selectedEditor),NSStringFromClass(container.class),NSStringFromSize(size)]);
    if(instance&&!analyzed)qelem_set(instance->request);
}
@end
static void scan(id node,int depth,int *budget,uintptr_t *editor,uintptr_t *button,NSRect *frame){
    if(!node||depth>15||--*budget<0)return;
    NSString *ident=[node respondsToSelector:@selector(accessibilityIdentifier)]?[node accessibilityIdentifier]:nil;
    if([ident isEqual:@"ClipDetailView.WarpedAudioTimelineEditor"])*editor=owner(node);
    if([ident isEqual:@"ClipDetailView.ClipContentHeader.PitchEditorButton"]){
        *button=owner(node);*frame=[node accessibilityFrame];
        static bool described=false;
        if(!described){described=true;log([NSString stringWithFormat:@"TAB NODE class=%@ owner=%@",NSStringFromClass([node class]),type(*button)]);
            for(Class c=[node class];c && c!=NSObject.class;c=class_getSuperclass(c)) {
                unsigned n=0;Ivar *vars=class_copyIvarList(c,&n);
                for(unsigned i=0;i<n;i++)log([NSString stringWithFormat:@"TAB IVAR class=%@ name=%s offset=%td type=%s",NSStringFromClass(c),ivar_getName(vars[i]),ivar_getOffset(vars[i]),ivar_getTypeEncoding(vars[i])]);
                free(vars);
            }
            for(unsigned off=8;off<80;off+=8){uintptr_t p=word((uintptr_t)(__bridge void*)node+off);NSString *kind=type(p);if(kind)log([NSString stringWithFormat:@"TAB FIELD offset=%u kind=%@ ptr=0x%lx",off,kind,(unsigned long)p]);}
        }
    }
    if([node respondsToSelector:@selector(accessibilityChildren)])for(id child in [node accessibilityChildren])scan(child,depth+1,budget,editor,button,frame);
}
static void tick(){
    uintptr_t editor=0,button=0;NSRect frame=NSZeroRect;
    for(NSWindow *w in NSApp.windows){int budget=5000;scan(w,0,&budget,&editor,&button,&frame);}
    if(!tableIs(editor,0x106b4d2a0)){if(pitchMode)closePitch();selectedEditor=0;return;}
    uintptr_t clip=word(editor+0x390);
    if(editor!=selectedEditor||clip!=selectedClip){if(pitchMode)closePitch();canvas=nil;analyzed=false;selectedEditor=editor;selectedClip=clip;}
    tabFrame=frame;
    if(button&&button!=buttonOwner){
        [tabButton removeFromSuperview];tabButton=nil;releaseHost(&tabHost);buttonOwner=button;
        if([type(button) isEqual:@"20AButtonControlSimple"]){
            NSSize size=sizeOf(button);tabHost=makeHost(button,size.width,size.height);
            NSView *container=nativeView(tabHost);
            if(container){
                tabButton=[PitchTabButton20 buttonWithTitle:@"Pitch Editor" target:actions action:@selector(toggle:)];
                tabButton.frame=container.bounds;tabButton.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
                tabButton.bordered=NO;tabButton.buttonType=NSButtonTypePushOnPushOff;
                tabButton.font=tabFont();
                tabButton.accessibilityIdentifier=@"PitchEditor.Toggle";
                [container addSubview:tabButton];log(@"TAB CONNECTED through native child host");
            }
        } else log([NSString stringWithFormat:@"Unexpected tab owner %@",type(button)]);
    }
    if(pitchMode){NSSize size=sizeOf(editor);resizeHost(canvasHost,size.width,size.height);}
}
static void requestClip(NativeObject *x){if(x==instance)outlet_bang(x->outlet);}
static void requestPlayback(NativeObject *x){if(x==instance)outlet_bang(x->playOutlet);}
static void warpMode(NativeObject *x,long value){x->warped=value!=0;warpPoints.clear();}
static void playingState(NativeObject *x,long value){x->playing=value!=0;}
static void warpMap(NativeObject *x,t_symbol*,long argc,t_atom *argv){
    if(x!=instance||argc<1)return;
    t_symbol *name=atom_getsym(argv+argc-1);
    t_dictionary *dict=dictobj_findregistered_retain(name);if(!dict)return;
    long count=0;t_atom *items=nullptr;
    if(!dictionary_getatoms(dict,gensym("warp_markers"),&count,&items)){
        for(long i=0;i<count;i++)if(atom_gettype(items+i)==A_OBJ){
            t_dictionary *marker=(t_dictionary*)atom_getobj(items+i);double beat=0,seconds=0;
            if(!dictionary_getfloat(marker,gensym("beat_time"),&beat)&&!dictionary_getfloat(marker,gensym("sample_time"),&seconds))warpPoints.push_back({beat,seconds});
        }
    }
    std::sort(warpPoints.begin(),warpPoints.end(),[](auto a,auto b){return a.beat<b.beat;});
    static bool reported=false;if(!reported){reported=true;log([NSString stringWithFormat:@"PLAYBACK warp markers=%lu",(unsigned long)warpPoints.size()]);}
    dictobj_release(dict);
}
static void playbackState(NativeObject *x,t_symbol*,long argc,t_atom *argv){
    if(argc<2)return;const char *key=atom_getsym(argv)->s_name;double v=atom_getfloat(argv+1);
    if(!strcmp(key,"follow")){BOOL follow=v!=0;dispatch_async(dispatch_get_main_queue(),^{canvas.followPlayback=follow;});}
    else if(!strcmp(key,"is_arrangement_clip"))x->arrangement=v!=0;
    else if(!strcmp(key,"songplaying"))x->songPlaying=v!=0;
    else if(!strcmp(key,"songtime"))x->songBeat=v;
    else if(!strcmp(key,"start_time"))x->clipStart=v;
    else if(!strcmp(key,"end_time"))x->clipEnd=v;
    else if(!strcmp(key,"start_marker"))x->startMarker=v;
    else if(!strcmp(key,"loop_start"))x->loopStart=v;
    else if(!strcmp(key,"loop_end"))x->loopEnd=v;
    else if(!strcmp(key,"looping"))x->looping=v!=0;
    else if(!strcmp(key,"muted"))x->muted=v!=0;
}
static void playbackPosition(NativeObject *x,double beat){
    if(x!=instance)return;
    bool running=x->playing;
    if(x->arrangement&&x->warped){
        running=x->songPlaying&&!x->muted&&x->songBeat>=x->clipStart&&x->songBeat<x->clipEnd;
        beat=x->startMarker+x->songBeat-x->clipStart;
        if(x->looping&&x->loopEnd>x->loopStart&&beat>=x->loopEnd)beat=x->loopStart+std::fmod(beat-x->loopStart,x->loopEnd-x->loopStart);
    }
    auto seconds=pitch::sourceTime(beat,x->warped,warpPoints);BOOL playing=running;bool valid=seconds.has_value();double time=seconds.value_or(0);
    static int debugCount=0;if(debugCount++<120&&debugCount%30==0)log([NSString stringWithFormat:@"PLAYPOS source=%.3f running=%d arrangement=%d song=%.3f start=%.3f marker=%.3f",time,playing,x->arrangement,x->songBeat,x->clipStart,x->startMarker]);
    dispatch_async(dispatch_get_main_queue(),^{if(pitchMode)[canvas setPlayheadSeconds:time playing:playing valid:valid];});
}
static void readAudio(NativeObject*,t_symbol*,long argc,t_atom *argv){
    if(argc<1||atom_gettype(argv)!=A_SYM)return;
    NSString *path=[NSString stringWithUTF8String:atom_getsym(argv)->s_name];
    dispatch_async(dispatch_get_main_queue(),^{
        if(!pitchMode)return;
        NSUInteger ticket=generation;PitchCanvas *target=canvas;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool {
            NSError *error=nil;AVAudioFile *file=[[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:path] error:&error];
            std::shared_ptr<pitch::Analysis> result;
            double sr=file.processingFormat.sampleRate;
            if(file&&sr>=8000&&sr<=48000&&file.length>0&&file.length/sr<=60&&file.processingFormat.channelCount<=2){
                AVAudioPCMBuffer *buffer=[[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat frameCapacity:(AVAudioFrameCount)file.length];
                if([file readIntoBuffer:buffer error:&error]&&buffer.floatChannelData){
                    unsigned bestChannel=0;double bestEnergy=-1;
                    for(unsigned c=0;c<buffer.format.channelCount;c++){double sum=0,energy=0;for(unsigned i=0;i<buffer.frameLength;i++){double v=buffer.floatChannelData[c][i];sum+=v;energy+=v*v;}energy-=sum*sum/buffer.frameLength;if(energy>bestEnergy){bestEnergy=energy;bestChannel=c;}}
                    std::vector<float> mono(buffer.floatChannelData[bestChannel],buffer.floatChannelData[bestChannel]+buffer.frameLength);
                    try{result=std::make_shared<pitch::Analysis>(pitch::analyze(mono,sr));}catch(...){}
                }
            }
            dispatch_async(dispatch_get_main_queue(),^{
                if(ticket!=generation||!pitchMode||canvas!=target)return;
                if(result){auto count=result->notes.size();[target setAnalysis:std::move(*result)];analyzed=true;[target.window makeFirstResponder:target];log([NSString stringWithFormat:@"ANALYZED %@ notes=%lu",path.lastPathComponent,(unsigned long)count]);}
                else log([NSString stringWithFormat:@"ANALYSIS FAILED %@",error.localizedDescription?:@"unsupported audio"]);
            });
        }});
    });
}
static void dispose(NativeObject *x){
    if(x->request)qelem_free(x->request);
    if(x->playRequest)qelem_free(x->playRequest);
    if(instance!=x)return;instance=nullptr;
    dispatch_async(dispatch_get_main_queue(),^{
        [timer invalidate];timer=nil;[playTimer invalidate];playTimer=nil;closePitch();canvas=nil;[tabButton removeFromSuperview];tabButton=nil;releaseHost(&tabHost);buttonOwner=0;
        if(eventMonitor)[NSEvent removeMonitor:eventMonitor];eventMonitor=nil;
    });
}
static void *create(){
    auto *x=(NativeObject*)object_alloc(klass);x->playOutlet=bangout(x);x->outlet=bangout(x);x->request=qelem_new(x,(method)requestClip);x->playRequest=qelem_new(x,(method)requestPlayback);
    if(instance)return x;instance=x;
    dispatch_async(dispatch_get_main_queue(),^{
        if(instance!=x||![NSBundle.mainBundle.bundlePath isEqual:@PITCH_LIVE_COPY])return;
        slide=_dyld_get_image_vmaddr_slide(0);actions=[PitchNativeActions20 new];
        timer=[NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer*){tick();}];
        playTimer=[NSTimer scheduledTimerWithTimeInterval:1.0/30 repeats:YES block:^(NSTimer*){if(instance&&pitchMode)qelem_set(instance->playRequest);}];
        eventMonitor=[NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseDown|NSEventMaskKeyDown|NSEventMaskScrollWheel|NSEventMaskMagnify) handler:^NSEvent*(NSEvent *e){
            if(e.type==NSEventTypeScrollWheel||e.type==NSEventTypeMagnify){
                if(pitchMode&&canvas.window==e.window&&NSPointInRect([canvas convertPoint:e.locationInWindow fromView:nil],canvas.bounds)){
                    if(e.type==NSEventTypeScrollWheel)[canvas scrollWheel:e];else [canvas magnifyWithEvent:e];return nil;
                }
                return e;
            }
            if(e.type==NSEventTypeKeyDown){
                if(pitchMode&&e.window.firstResponder==canvas&&[canvas handleNavigationKey:e])return nil;
                if(pitchMode&&e.window.firstResponder==canvas&&(e.modifierFlags&NSEventModifierFlagCommand)&&[e.charactersIgnoringModifiers.lowercaseString isEqual:@"z"]){
                    if(e.modifierFlags&NSEventModifierFlagShift)[canvas redoEdit];else [canvas undoEdit];return nil;
                }
                return e;
            }
            NSPoint p=[e.window convertPointToScreen:e.locationInWindow];
            if(pitchMode&&selectorOwner&&buttonOwner){
                NSSize buttonSize=sizeOf(buttonOwner),selectorSize=sizeOf((uintptr_t)selectorOwner);
                uintptr_t border=word(buttonOwner+0x60);
                uint64_t bp=word(buttonOwner+0x30),rp=word(border+0x30),sp=word((uintptr_t)selectorOwner+0x30);
                CGFloat scale=buttonSize.width>0?tabFrame.size.width/buttonSize.width:1;
                CGFloat dx=(int32_t)sp-(int32_t)rp-(int32_t)bp;
                CGFloat dy=(int32_t)(sp>>32)-(int32_t)(rp>>32)-(int32_t)(bp>>32);
                NSRect selectorFrame=NSMakeRect(NSMinX(tabFrame)+dx*scale,NSMaxY(tabFrame)-(dy+selectorSize.height)*scale,selectorSize.width*scale,selectorSize.height*scale);
                if(NSPointInRect(p,selectorFrame))closePitch();
            }
            return e;
        }];
        log(@"LOADED native Pitch Editor tab bridge");tick();
    });return x;
}
extern "C" C74_EXPORT void ext_main(void*){
    klass=class_new("pitchnative20",(method)create,(method)dispose,sizeof(NativeObject),nullptr,0);
    class_addmethod(klass,(method)playbackState,"state",A_GIMME,0);
    class_addmethod(klass,(method)warpMode,"warping",A_LONG,0);
    class_addmethod(klass,(method)playingState,"playing",A_LONG,0);
    class_addmethod(klass,(method)warpMap,"warpmap",A_GIMME,0);
    class_addmethod(klass,(method)playbackPosition,"position",A_FLOAT,0);
    class_addmethod(klass,(method)readAudio,"read",A_GIMME,0);class_register(CLASS_BOX,klass);
}
