#import "pitch_canvas.hpp"
#include <stdexcept>
#include <iostream>

@interface PitchCanvas (TestGeometry)
- (NSRect)gainHandleRect;
- (NSRect)formantHandleRect;
- (NSRect)driftHandleRect:(NSInteger)side;
- (NSRect)vibratoHandleRect;
- (NSRect)rectForNote:(const pitch::Note&)note index:(NSInteger)index;
@end
static void require(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
static NSMenu *noteMenu(PitchCanvas *canvas,std::size_t index){
    auto notes=[canvas noteSnapshot];NSRect rect=[canvas rectForNote:notes[index] index:index];
    NSPoint point=[canvas convertPoint:NSMakePoint(NSMidX(rect),NSMidY(rect)) toView:nil];
    auto event=[NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
    return [canvas menuForEvent:event];
}
int main(){@autoreleasepool{try{
    [NSApplication sharedApplication];
    PitchCanvas *canvas=[[PitchCanvas alloc] initWithFrame:NSMakeRect(0,0,900,400)];
    pitch::Analysis analysis;analysis.duration=2;analysis.notes={{7,.2,1.8,60,.37}};
    [canvas setAnalysis:analysis];__block int publications=0;
    canvas.editCommitted=^(std::vector<pitch::Note> notes){require(!notes.empty(),"empty publication");++publications;};
    auto menu=noteMenu(canvas,0);
    require(menu.numberOfItems==4&&[menu itemAtIndex:0].enabled&&![menu itemAtIndex:1].enabled,"initial menu state");
    [menu performActionForItemAtIndex:0];
    require([canvas noteSnapshot].size()==2&&publications==1,"split action publication");
    menu=noteMenu(canvas,1);
    require(![menu itemAtIndex:1].enabled,"last note join enabled");
    [canvas undoEdit];
    require([canvas noteSnapshot].size()==1&&[[canvas accessibilityValue] containsString:@"Note 1"],"selection after structural undo");
    [canvas redoEdit];menu=noteMenu(canvas,0);
    require([menu itemAtIndex:1].enabled,"split children not joinable");
    [menu performActionForItemAtIndex:1];
    require([canvas noteSnapshot].size()==1&&publications==4,"join action publication");
    [canvas undoEdit];require([canvas noteSnapshot].size()==2,"join undo");
    __block double sought=-1;
    canvas.cursorRequested=^(double seconds){sought=seconds;};
    auto eventAt=[&](NSPoint point,NSEventType type){return [NSEvent mouseEventWithType:type location:[canvas convertPoint:point toView:nil] modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];};
    // Empty plot clicks seek, while note clicks remain selection/audition.
    [canvas mouseDown:eventAt(NSMakePoint(468,30),NSEventTypeLeftMouseDown)];
    require(std::abs(sought-1)<1e-9,"empty-space seek mapping");
    [canvas mouseUp:eventAt(NSMakePoint(468,30),NSEventTypeLeftMouseUp)];
    sought=-1;auto rect=[canvas rectForNote:[canvas noteSnapshot][0] index:0];
    [canvas mouseDown:eventAt(NSMakePoint(NSMidX(rect),NSMidY(rect)),NSEventTypeLeftMouseDown)];
    require(sought==-1,"note click moved transport");
    [canvas mouseUp:eventAt(NSMakePoint(NSMidX(rect),NSMidY(rect)),NSEventTypeLeftMouseUp)];
    [canvas mouseDown:eventAt(NSMakePoint(468,10),NSEventTypeLeftMouseDown)];
    [canvas mouseUp:eventAt(NSMakePoint(468,10),NSEventTypeLeftMouseUp)];
    require(std::abs(sought-1)<1e-9,"ruler click seek");
    sought=-1;
    [canvas mouseDown:eventAt(NSMakePoint(468,10),NSEventTypeLeftMouseDown)];
    [canvas mouseDragged:eventAt(NSMakePoint(488,10),NSEventTypeLeftMouseDragged)];
    [canvas mouseUp:eventAt(NSMakePoint(488,10),NSEventTypeLeftMouseUp)];
    require(sought==-1,"ruler pan moved transport");
    menu=noteMenu(canvas,0);[menu performActionForItemAtIndex:3];
    require([canvas noteSnapshot].size()==1,"remove menu action");
    [canvas undoEdit];require([canvas noteSnapshot].size()==2,"remove menu undo");
    rect=[canvas rectForNote:[canvas noteSnapshot][0] index:0];
    NSPoint edge=NSMakePoint(NSMinX(rect)+1,NSMidY(rect));
    [canvas mouseDown:eventAt(edge,NSEventTypeLeftMouseDown)];
    [canvas mouseDragged:eventAt(NSMakePoint(edge.x+42,edge.y),NSEventTypeLeftMouseDragged)];
    [canvas mouseUp:eventAt(NSMakePoint(edge.x+42,edge.y),NSEventTypeLeftMouseUp)];
    require(std::abs([canvas noteSnapshot][0].start-.3)<1e-9,"edge drag source boundary");
    require([canvas noteSnapshot][0].semitones==.37,"edge drag changed pitch");
    [canvas undoEdit];require(std::abs([canvas noteSnapshot][0].start-.2)<1e-9,"edge drag undo");
    auto gainRect=[canvas gainHandleRect];NSPoint gainPoint=NSMakePoint(NSMidX(gainRect),NSMidY(gainRect));
    [canvas mouseDown:eventAt(gainPoint,NSEventTypeLeftMouseDown)];
    [canvas mouseDragged:eventAt(NSMakePoint(gainPoint.x,gainPoint.y+60),NSEventTypeLeftMouseDragged)];
    [canvas mouseUp:eventAt(NSMakePoint(gainPoint.x,gainPoint.y+60),NSEventTypeLeftMouseUp)];
    require([canvas noteSnapshot][0].gainDb==-6&&[canvas noteSnapshot][0].semitones==.37,"gain drag changed wrong parameter");
    [canvas undoEdit];require([canvas noteSnapshot][0].gainDb==0,"gain gesture undo");
    [canvas redoEdit];require([canvas noteSnapshot][0].gainDb==-6,"gain gesture redo");
    auto doubleClick=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:[canvas convertPoint:gainPoint toView:nil] modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:2 pressure:1];
    [canvas mouseDown:doubleClick];require([canvas noteSnapshot][0].gainDb==0,"gain reset");
    auto vibratoRect=[canvas vibratoHandleRect];NSPoint vibratoPoint=NSMakePoint(NSMidX(vibratoRect),NSMidY(vibratoRect));
    [canvas mouseDown:eventAt(vibratoPoint,NSEventTypeLeftMouseDown)];
    [canvas mouseDragged:eventAt(NSMakePoint(vibratoPoint.x,vibratoPoint.y+50),NSEventTypeLeftMouseDragged)];
    [canvas mouseUp:eventAt(NSMakePoint(vibratoPoint.x,vibratoPoint.y+50),NSEventTypeLeftMouseUp)];
    require([canvas noteSnapshot][0].vibrato==.5&&[canvas noteSnapshot][0].semitones==.37,"vibrato drag changed wrong parameter");
    [canvas undoEdit];require([canvas noteSnapshot][0].vibrato==1,"vibrato undo");
    [canvas redoEdit];require([canvas noteSnapshot][0].vibrato==.5,"vibrato redo");
    auto resetVibrato=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:[canvas convertPoint:vibratoPoint toView:nil] modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:2 pressure:1];
    [canvas mouseDown:resetVibrato];require([canvas noteSnapshot][0].vibrato==1,"vibrato reset");
    auto driftRect=[canvas driftHandleRect:-1];NSPoint driftPoint=NSMakePoint(NSMidX(driftRect),NSMidY(driftRect));
    [canvas mouseDown:eventAt(driftPoint,NSEventTypeLeftMouseDown)];
    [canvas mouseDragged:eventAt(NSMakePoint(driftPoint.x,driftPoint.y-25),NSEventTypeLeftMouseDragged)];
    [canvas mouseUp:eventAt(NSMakePoint(driftPoint.x,driftPoint.y-25),NSEventTypeLeftMouseUp)];
    require([canvas noteSnapshot][0].driftStart==50&&[canvas noteSnapshot][0].driftEnd==0&&[canvas noteSnapshot][0].semitones==.37,"drift gesture");
    require(![noteMenu(canvas,0) itemAtIndex:0].enabled,"split drift enabled");
    [canvas undoEdit];require([canvas noteSnapshot][0].driftStart==0,"drift undo");
    [canvas redoEdit];require([canvas noteSnapshot][0].driftStart==50,"drift redo");
    auto resetDrift=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:[canvas convertPoint:driftPoint toView:nil] modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:2 pressure:1];
    [canvas mouseDown:resetDrift];require([canvas noteSnapshot][0].driftStart==0,"drift reset");
    auto formantRect=[canvas formantHandleRect];NSPoint formantPoint=NSMakePoint(NSMidX(formantRect),NSMidY(formantRect));
    [canvas mouseDown:eventAt(formantPoint,NSEventTypeLeftMouseDown)];
    [canvas mouseDragged:eventAt(NSMakePoint(formantPoint.x,formantPoint.y-40),NSEventTypeLeftMouseDragged)];
    [canvas mouseUp:eventAt(NSMakePoint(formantPoint.x,formantPoint.y-40),NSEventTypeLeftMouseUp)];
    require([canvas noteSnapshot][0].formant==2&&[canvas noteSnapshot][0].semitones==.37,"formant drag changed pitch");
    [canvas undoEdit];require([canvas noteSnapshot][0].formant==0,"formant undo");
    [canvas redoEdit];require([canvas noteSnapshot][0].formant==2,"formant redo");
    auto resetFormant=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:[canvas convertPoint:formantPoint toView:nil] modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:0 clickCount:2 pressure:1];
    [canvas mouseDown:resetFormant];require([canvas noteSnapshot][0].formant==0,"formant reset");
    std::cout<<"PASS: context split/join, publication, selection and undo/redo\n";
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}}
