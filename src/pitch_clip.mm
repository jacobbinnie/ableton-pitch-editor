// Max for Live development adapter. This is a device UI, not a Clip View hook.
#import <AVFoundation/AVFoundation.h>
#include "ext.h"
#include "ext_obex.h"
#include "jpatcher_api.h"
#include "jgraphics.h"
#include "pitch_core.hpp"
#include <algorithm>
#include <cmath>
#include <memory>
#include <mutex>
#include <string>

struct Pending {
    std::mutex lock;
    unsigned generation = 0;
    bool ready = false;
    std::unique_ptr<pitch::Analysis> analysis;
    std::string status;
};
struct Model {
    std::shared_ptr<Pending> pending = std::make_shared<Pending>();
    std::unique_ptr<pitch::Document> document;
    std::string status = "Select an audio clip, then click Analyze clip";
    long selected = -1;
    double origin = 0, initial = 0, preview = 0;
    int low = 48, high = 72;
    bool dragging = false;
};
struct ClipBox { t_jbox box; Model* model; void* outlet; t_clock* clock; t_qelem* refresh; };
static t_class* clipClass;
static void selectionStatus(ClipBox* x) {
    auto& m=*x->model;
    if(m.document && m.selected>=0) {
        m.status="Note "+std::to_string(m.selected+1)+": "+std::to_string(static_cast<int>(m.document->analysis().notes[m.selected].semitones))+" semitones | Audio rendering pending";
    }
}
static void ink(t_jgraphics* g,double r,double b,double c) { jgraphics_set_source_rgba(g,r,b,c,1); }
static void text(t_jgraphics* g,double x,double y,const char* s) { jgraphics_move_to(g,x,y); jgraphics_show_text(g,s); }
static double row(ClipBox* x,t_rect r) { return (r.height-42)/(x->model->high-x->model->low+1); }
static t_rect noteRect(ClipBox* x,t_rect r,std::size_t index) {
    const auto& n=x->model->document->analysis().notes[index];
    double duration=x->model->document->analysis().duration;
    double shift=x->model->dragging && static_cast<long>(index)==x->model->selected ? x->model->preview : n.semitones;
    return {38+n.start/duration*(r.width-48),25+(x->model->high-n.originalMidi-shift)*row(x,r),std::max(3.0,(n.end-n.start)/duration*(r.width-48)),std::max(2.0,row(x,r)*.8)};
}
static void paint(ClipBox* x,t_object* view) {
    auto g=reinterpret_cast<t_jgraphics*>(patcherview_get_jgraphics(view));
    t_rect r; jbox_get_rect_for_view(reinterpret_cast<t_object*>(x),view,&r);
    ink(g,.15,.16,.17); jgraphics_rectangle(g,0,0,r.width,r.height); jgraphics_fill(g);
    jgraphics_select_font_face(g,"Arial",JGRAPHICS_FONT_SLANT_NORMAL,JGRAPHICS_FONT_WEIGHT_NORMAL);
    jgraphics_set_font_size(g,10);
    ink(g,.8,.8,.82); text(g,10,15,"PITCH EDITOR");
    text(g,r.width-224,15,"Analyze clip"); text(g,r.width-118,15,"Undo"); text(g,r.width-59,15,"Redo");
    for(int midi=x->model->low;midi<=x->model->high;++midi) {
        double y=25+(x->model->high-midi)*row(x,r);
        int pc=(midi%12+12)%12; bool black=pc==1||pc==3||pc==6||pc==8||pc==10;
        double shade=black?.13:.18; ink(g,shade,shade+.01,shade+.02);
        jgraphics_rectangle(g,38,y,r.width-48,row(x,r)-.4); jgraphics_fill(g);
        if(pc==0) { ink(g,.6,.63,.65); std::string name="C"+std::to_string(midi/12-1); text(g,7,y+7,name.c_str()); }
    }
    if(x->model->document) {
        const auto& a=x->model->document->analysis();
        for(std::size_t i=0;i<a.notes.size();++i) {
            t_rect n=noteRect(x,r,i);
            if(static_cast<long>(i)==x->model->selected) ink(g,.94,.72,.35); else ink(g,.72,.49,.73);
            jgraphics_rectangle(g,n.x,n.y,n.width,n.height); jgraphics_fill(g);
        }
    }
    ink(g,.64,.67,.69); jgraphics_set_font_size(g,9);
    text(g,10,r.height-5,x->model->status.c_str());
}
static void update(ClipBox* x) {
    auto& p=*x->model->pending;
    std::lock_guard<std::mutex> lock(p.lock);
    if(!p.ready) return;
    p.ready=false;
    x->model->status=p.status;
    if(p.analysis) {
        x->model->document=std::make_unique<pitch::Document>(std::move(*p.analysis)); p.analysis.reset();
        x->model->selected=-1; x->model->dragging=false;
        double lo=60,hi=72;
        const auto& notes=x->model->document->analysis().notes;
        if(!notes.empty()) { lo=127; hi=0; for(const auto& n:notes) {lo=std::min(lo,n.originalMidi);hi=std::max(hi,n.originalMidi);} }
        x->model->low=std::floor(lo)-4; x->model->high=std::ceil(hi)+4;
    }
    jbox_redraw(&x->box);
}
static void tick(ClipBox* x) { qelem_set(x->refresh); clock_delay(x->clock,100); }
static void readFile(ClipBox* x,t_symbol* path) {
    auto p=x->model->pending;
    unsigned generation;
    { std::lock_guard<std::mutex> lock(p->lock); generation=++p->generation; p->ready=false; p->analysis.reset(); }
    x->model->status="Analyzing selected clip source..."; jbox_redraw(&x->box);
    NSString* filename=[NSString stringWithUTF8String:path->s_name];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            std::unique_ptr<pitch::Analysis> result;
            std::string status;
            NSError* error=nil;
            AVAudioFile* file=[[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:filename] error:&error];
            if(!file) status=error.localizedDescription.UTF8String ?: "Unable to open source audio";
            else if(file.length<=0 || file.length/file.processingFormat.sampleRate>60 || file.processingFormat.sampleRate>48000 || file.processingFormat.channelCount>2)
                status="Prototype limit: mono/stereo, up to 60 seconds, 8-48 kHz";
            else {
                auto buffer=[[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat frameCapacity:static_cast<AVAudioFrameCount>(file.length)];
                if(![file readIntoBuffer:buffer error:&error] || !buffer.floatChannelData) status="Unable to decode source audio";
                else {
                    unsigned channel=0; double best=-1;
                    for(unsigned c=0;c<buffer.format.channelCount;++c) {
                        double sum=0,energy=0;
                        for(unsigned i=0;i<buffer.frameLength;++i) { double v=buffer.floatChannelData[c][i];sum+=v;energy+=v*v; }
                        energy-=sum*sum/std::max(1u,buffer.frameLength);
                        if(energy>best) {best=energy;channel=c;}
                    }
                    try {
                        std::vector<float> audio(buffer.floatChannelData[channel],buffer.floatChannelData[channel]+buffer.frameLength);
                        result=std::make_unique<pitch::Analysis>(pitch::analyze(audio,file.processingFormat.sampleRate));
                        status=std::to_string(result->notes.size())+" notes | Drag vertically | Source seconds, unwarped | Audio rendering pending";
                    } catch(const std::exception& e) {status=e.what();}
                }
            }
            // No Max object pointer crosses into the worker. A destroyed device
            // can leave a job finishing safely with only this shared result.
            std::lock_guard<std::mutex> lock(p->lock);
            if(p->generation==generation) {p->analysis=std::move(result);p->status=std::move(status);p->ready=true;}
        }
    });
}
static void down(ClipBox* x,t_object* view,t_pt point,long modifiers) {
    (void)modifiers; t_rect r; jbox_get_rect_for_view(reinterpret_cast<t_object*>(x),view,&r);
    if(point.y<24) {
        if(point.x>r.width-65) {if(x->model->document)x->model->document->redo();}
        else if(point.x>r.width-125) {if(x->model->document)x->model->document->undo();}
        else if(point.x>r.width-230) {x->model->status="Requesting selected audio clip...";outlet_bang(x->outlet);}
        if(point.x>r.width-125)selectionStatus(x);
    } else if(x->model->document) {
        x->model->selected=-1;
        for(std::size_t i=0;i<x->model->document->analysis().notes.size();++i) {
            auto n=noteRect(x,r,i);
            if(point.x>=n.x && point.x<=n.x+n.width && point.y>=n.y && point.y<=n.y+n.height) {
                x->model->selected=i; x->model->origin=point.y;
                x->model->initial=x->model->preview=x->model->document->analysis().notes[i].semitones;
                x->model->dragging=true;break;
            }
        }
    }
    jbox_redraw(&x->box);
}
static void drag(ClipBox* x,t_object* view,t_pt point,long modifiers) {
    (void)modifiers;if(!x->model->dragging)return;
    t_rect r;jbox_get_rect_for_view(reinterpret_cast<t_object*>(x),view,&r);
    x->model->preview=std::clamp(x->model->initial+std::round((x->model->origin-point.y)/row(x,r)),-24.0,24.0);
    jbox_redraw(&x->box);
}
static void up(ClipBox* x,t_object* view,t_pt point,long modifiers) {
    (void)view;(void)point;(void)modifiers;
    if(!x->model->dragging)return;
    auto& m=*x->model;
    m.document->transpose(m.document->analysis().notes[m.selected].id,m.preview);
    m.status="Note "+std::to_string(m.selected+1)+": "+std::to_string(static_cast<int>(m.preview))+" semitones | Audio rendering pending";
    m.dragging=false;jbox_redraw(&x->box);
}
static void destroy(ClipBox* x) {
    if(x->clock) {clock_unset(x->clock);object_free(x->clock);}
    if(x->refresh)qelem_free(x->refresh);
    delete x->model; jbox_free(&x->box);
}
static void* create(t_symbol* s,long argc,t_atom* argv) {
    (void)s;
    auto dictionary=object_dictionaryarg(argc,argv); if(!dictionary)return nullptr;
    auto x=static_cast<ClipBox*>(object_alloc(clipClass));if(!x)return nullptr;
    jbox_new(&x->box,JBOX_DRAWFIRSTIN|JBOX_NODRAWBOX|JBOX_DRAWINLAST|JBOX_GROWBOTH,argc,argv);
    x->box.b_firstin=reinterpret_cast<t_object*>(x);
    x->model=new Model; x->outlet=outlet_new(x,nullptr);
    x->refresh=static_cast<t_qelem*>(qelem_new(x,reinterpret_cast<method>(update)));
    x->clock=clock_new(x,reinterpret_cast<method>(tick));
    attr_dictionary_process(x,dictionary);jbox_ready(&x->box);clock_delay(x->clock,100);
    return x;
}
extern "C" C74_EXPORT void ext_main(void*) {
    auto c=class_new(PITCHCLIP_CLASS,reinterpret_cast<method>(create),reinterpret_cast<method>(destroy),sizeof(ClipBox),nullptr,A_GIMME,0);
    c->c_flags|=CLASS_FLAG_NEWDICTIONARY;jbox_initclass(c,0);
    class_addmethod(c,reinterpret_cast<method>(paint),"paint",A_CANT,0);
    class_addmethod(c,reinterpret_cast<method>(down),"mousedown",A_CANT,0);
    class_addmethod(c,reinterpret_cast<method>(drag),"mousedrag",A_CANT,0);
    class_addmethod(c,reinterpret_cast<method>(up),"mouseup",A_CANT,0);
    class_addmethod(c,reinterpret_cast<method>(readFile),"read",A_SYM,0);
    CLASS_ATTR_DEFAULT(c,"patching_rect",0,"0 0 700 160");
    class_register(CLASS_BOX,c);clipClass=c;
}
