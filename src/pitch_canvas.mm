#import "pitch_canvas.hpp"
#include "pitch_gain.hpp"
#include "pitch_gestures.hpp"
#include <algorithm>
#include <cmath>

static NSColor* color(CGFloat r, CGFloat g, CGFloat b) {
    return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];
}
// Default Dark Neutral Medium: the same palette used by the native Envelopes view.
static NSColor *neutral(unsigned value,CGFloat alpha=1) {
    return [NSColor colorWithSRGBRed:value/255.0 green:value/255.0 blue:value/255.0 alpha:alpha];
}
static void label(NSString* text, NSPoint at, NSColor* ink, CGFloat size) {
    [text drawAtPoint:at withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:size], NSForegroundColorAttributeName:ink}];
}
@interface PitchSnapButton33 : NSButton
@end
@implementation PitchSnapButton33
- (void)drawRect:(NSRect)dirty {
    (void)dirty;BOOL on=self.state==NSControlStateValueOn;
    [(on?color(1,.67,.3):neutral(0x46)) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,1,1) xRadius:2 yRadius:2] fill];
    NSDictionary *attrs=@{NSFontAttributeName:[NSFont systemFontOfSize:10],NSForegroundColorAttributeName:on?neutral(0x20):neutral(0xb5)};
    NSSize size=[self.title sizeWithAttributes:attrs];
    [self.title drawAtPoint:NSMakePoint(std::round((self.bounds.size.width-size.width)/2),std::round((self.bounds.size.height-size.height)/2)) withAttributes:attrs];
}
- (void)setState:(NSControlStateValue)value {[super setState:value];self.needsDisplay=YES;}
@end

@implementation PitchCanvas
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) { selected = -1; lowest = 48; highest = 84; self.toolTip=@"Click empty space or the ruler to position playback. Drag notes vertically to transpose; Shift-drag to fine-tune. Option-Up/Down adjusts one cent. Scroll to pan; Command-scroll to zoom time; Option-scroll to zoom pitch. F fits the clip. Right-click to split or join. Drag the lower-right handle for formant tone. Drag upper corner handles to adjust start/end drift in cents. Drag Gain below the note to balance volume. Drag Vibrato above it downward to reduce variation; double-click either handle to reset. Command-Z undoes."; }
    if(self){
        NSUserDefaults *preferences=[[NSUserDefaults alloc] initWithSuiteName:@"local.jacob.pitch-editor"];
        BOOL on=[preferences objectForKey:@"snapPitch"]?[preferences boolForKey:@"snapPitch"]:YES;
        snapButton=[PitchSnapButton33 buttonWithTitle:@"Snap" target:self action:@selector(toggleSnap:)];
        snapButton.buttonType=NSButtonTypePushOnPushOff;snapButton.bordered=NO;
        snapButton.frame=NSMakeRect(std::max(0.,frame.size.width-65),frame.size.height-19,60,18);
        snapButton.autoresizingMask=NSViewMinXMargin|NSViewMinYMargin;
        snapButton.state=on?NSControlStateValueOn:NSControlStateValueOff;
        snapButton.accessibilityIdentifier=@"PitchEditor.Snap";
        snapButton.toolTip=@"Snap dragged notes to semitones. Turn off for free pitch movement. Shift-drag always fine-tunes.";
        [self addSubview:snapButton];
    }
    return self;
}
- (void)toggleSnap:(id)sender {
    (void)sender;NSUserDefaults *preferences=[[NSUserDefaults alloc] initWithSuiteName:@"local.jacob.pitch-editor"];
    [preferences setBool:snapButton.state==NSControlStateValueOn forKey:@"snapPitch"];
    [self.window makeFirstResponder:self];
}
- (void)enableAudioControls {audioStatus=@"Live pitch editing • Drag notes to audition";}
- (void)setAudioStatus:(NSString*)status ready:(BOOL)ready {(void)ready;audioStatus=[status copy];self.needsDisplay=YES;}
- (std::vector<pitch::Note>)noteSnapshot {return document?document->analysis().notes:std::vector<pitch::Note>{};}
- (void)rebuildExpression {if(document)expression=pitch::expressionCurve(document->analysis().frames,[self noteSnapshot]);}
- (void)notifyEdit {[self rebuildExpression];if(self.editCommitted)self.editCommitted([self noteSnapshot]);if(self.documentCommitted)self.documentCommitted(document);}
- (void)clampSelection {
    if(!document||document->analysis().notes.empty())selected=-1;
    else selected=std::min<NSInteger>(selected,document->analysis().notes.size()-1);
}
- (void)splitHere:(NSMenuItem*)item {
    if(!document||selected<0||dragging)return;
    if(document->split(document->analysis().notes[selected].id,[item.representedObject doubleValue])){
        [self notifyEdit];self.needsDisplay=YES;
    }
}
- (void)joinNext:(id)sender {
    (void)sender;if(!document||selected<0||dragging)return;
    if(document->joinNext(document->analysis().notes[selected].id)){
        [self clampSelection];[self notifyEdit];self.needsDisplay=YES;
    }
}
- (void)removeRegion:(id)sender {
    (void)sender;if(!document||selected<0||dragging)return;
    if(document->remove(document->analysis().notes[selected].id)){
        selected=-1;[self notifyEdit];self.needsDisplay=YES;
    }
}
- (BOOL)handleRegionKey:(NSEvent*)event {
    if((event.keyCode==51||event.keyCode==117)&&!(event.modifierFlags&(NSEventModifierFlagCommand|NSEventModifierFlagControl|NSEventModifierFlagOption))){[self removeRegion:nil];return YES;}
    return NO;
}
- (NSMenu*)menuForEvent:(NSEvent*)event {
    if(!document||dragging)return nil;
    NSPoint point=[self convertPoint:event.locationInWindow fromView:nil];
    if(!NSPointInRect(point,[self plotRect]))return nil;
    const auto& notes=document->analysis().notes;selected=-1;
    for(std::size_t i=0;i<notes.size();++i)if(NSPointInRect(point,[self rectForNote:notes[i] index:i])){selected=i;break;}
    self.needsDisplay=YES;if(selected<0)return nil;
    [self.window makeFirstResponder:self];
    double seconds=viewport.start+(point.x-[self plotRect].origin.x)/[self plotRect].size.width*viewport.span;
    NSMenu *menu=[[NSMenu alloc] initWithTitle:@"Edit Note"];menu.autoenablesItems=NO;
    NSMenuItem *split=[[NSMenuItem alloc] initWithTitle:@"Split Note Here" action:@selector(splitHere:) keyEquivalent:@""];
    split.target=self;split.representedObject=@(seconds);
    split.enabled=seconds-notes[selected].start>=.02&&notes[selected].end-seconds>=.02&&notes[selected].driftStart==0&&notes[selected].driftEnd==0;
    split.toolTip=@"Reset drift before splitting; splitting would change its midpoint and shape.";
    [menu addItem:split];
    NSMenuItem *join=[[NSMenuItem alloc] initWithTitle:@"Join with Next Note" action:@selector(joinNext:) keyEquivalent:@""];
    join.target=self;join.enabled=document->canJoinNext(notes[selected].id);
    join.toolTip=@"Join touching notes with matching pitch, gain, vibrato and formant. Reset drift before joining.";
    [menu addItem:join];[menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *remove=[[NSMenuItem alloc] initWithTitle:@"Remove Pitch Region" action:@selector(removeRegion:) keyEquivalent:@""];
    remove.target=self;remove.toolTip=@"Leave the audio unchanged in this region.";[menu addItem:remove];return menu;
}
- (void)rightMouseDown:(NSEvent*)event {
    NSMenu *menu=[self menuForEvent:event];if(menu)[NSMenu popUpContextMenu:menu withEvent:event forView:self];
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString*)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString*)accessibilityLabel { return @"Pitch notes"; }
- (NSString*)accessibilityHelp { return @"Click empty space or the ruler to position playback. Drag the ruler to pan. Command-scroll or pinch to zoom time; Option-scroll zooms pitch. Option-drag or ruler drag pans. Shift-arrows pan. Plus/minus zoom; F fits. Left/right select notes, up/down transpose; Option-Up/Down adjusts one cent. Shift-drag fine-tunes. Drag note edges to resize. Delete removes the pitch region, leaving audio intact. Right-click a note to split or join. Drag the lower-right handle for formant tone. Drag upper corner handles to adjust start/end drift in cents. Drag Gain below the note to balance volume. Drag Vibrato above it downward to reduce variation; double-click either handle to reset. Command Z undoes."; }
- (id)accessibilityValue {
    NSString *render=audioStatus?[@"; " stringByAppendingString:audioStatus]:@"";
    NSString *play=playheadVisible?[NSString stringWithFormat:@"; playhead %.2fs %@",playheadSeconds,playbackRunning?@"playing":@"stopped"]:@"";
    if (!document) return @"No audio loaded";
    if (selected < 0) return [NSString stringWithFormat:@"%lu notes; no selection; view %.2f to %.2f seconds; %.1f pitch rows, top %.1f%@",static_cast<unsigned long>(document->analysis().notes.size()),viewport.start,viewport.start+viewport.span,viewport.rows,viewport.top,[play stringByAppendingString:render]];
    const auto& note = document->analysis().notes[selected];
    return [NSString stringWithFormat:@"Note %ld, %.2f to %.2f seconds, transposition %+.2f semitones, gain %+.1f dB, vibrato %.0f%%, drift start %+.0f cents, end %+.0f cents, formant %+.2f semitones%@",static_cast<long>(selected+1),note.start,note.end,note.semitones,note.gainDb,note.vibrato*100,note.driftStart,note.driftEnd,note.formant,[play stringByAppendingString:render]];
}
- (void)setAnalysis:(pitch::Analysis)analysis {
    [self setDocument:std::make_shared<pitch::Document>(std::move(analysis))];
}
- (void)setDocument:(std::shared_ptr<pitch::Document>)value {
    document=std::move(value);[self rebuildExpression];
    selected = -1; dragging = NO; panning = NO;playheadVisible=NO;playbackRunning=NO;
    double lo = 60, hi = 72;
    if (!document->analysis().notes.empty()) {
        lo = 127; hi = 0;
        for (const auto& n : document->analysis().notes) { lo = std::min(lo, n.originalMidi); hi = std::max(hi, n.originalMidi); }
    }
    lowest = static_cast<int>(std::floor(lo)) - 7;
    highest = static_cast<int>(std::ceil(hi)) + 7;
    [self fitView];
}
- (NSRect)plotRect { return NSMakeRect(48,24,std::max(1.0,self.bounds.size.width-60),std::max(1.0,self.bounds.size.height-42)); }
- (void)setFollowPlayback:(BOOL)value { if(_followPlayback!=value)followSuspended=NO;_followPlayback=value; }
- (void)setPlayheadSeconds:(double)seconds playing:(BOOL)playing valid:(BOOL)valid {
    if(!document||!valid){playheadVisible=NO;playbackRunning=NO;self.needsDisplay=YES;return;}
    if(playing&&!playbackRunning)followSuspended=NO;
    playheadSeconds=seconds;playheadVisible=seconds>=0&&seconds<=document->analysis().duration;
    if(playing){
        if(self.followPlayback&&!followSuspended&&!dragging&&!panning&&playheadVisible&&
           (seconds<viewport.start||seconds>=viewport.start+viewport.span)){
            viewport.start=seconds-viewport.span*.1;viewport.clamp();
        }
    }
    playbackRunning=playing;
    self.needsDisplay=YES;
}
- (void)fitView { if(document)viewport.fit(document->analysis().duration,lowest,highest);self.needsDisplay=YES; }
- (double)rowHeight { return [self plotRect].size.height/viewport.rows; }
- (double)xForTime:(double)t { NSRect r=[self plotRect];return r.origin.x+(t-viewport.start)/viewport.span*r.size.width; }
- (double)yForPitch:(double)midi { return [self plotRect].origin.y+(viewport.top-midi)*[self rowHeight]; }
- (void)zoomAt:(NSPoint)p factor:(double)factor vertical:(BOOL)vertical {
    if(!document||dragging)return;
    followSuspended=YES;NSRect r=[self plotRect];viewport.zoom(factor,vertical?(p.y-r.origin.y)/r.size.height:(p.x-r.origin.x)/r.size.width,vertical);self.needsDisplay=YES;
}
- (void)scrollWheel:(NSEvent*)e {
    if(!document||dragging)return;
    [self.window makeFirstResponder:self];
    NSPoint p=[self convertPoint:e.locationInWindow fromView:nil];
    followSuspended=YES;double unit=e.hasPreciseScrollingDeltas?1:12;
    if(e.modifierFlags&(NSEventModifierFlagCommand|NSEventModifierFlagOption)){
        [self zoomAt:p factor:std::exp(std::clamp(e.scrollingDeltaY*unit*.012,-1.0,1.0)) vertical:(e.modifierFlags&NSEventModifierFlagOption)!=0];
    }else{
        NSRect r=[self plotRect];double dx=e.scrollingDeltaX*unit,dy=e.scrollingDeltaY*unit;
        if(e.modifierFlags&NSEventModifierFlagShift){if(std::abs(dx)<.01)dx=dy;dy=0;}
        viewport.pan(-dx/r.size.width*viewport.span,dy/r.size.height*viewport.rows);self.needsDisplay=YES;
    }
}
- (void)magnifyWithEvent:(NSEvent*)e { [self zoomAt:[self convertPoint:e.locationInWindow fromView:nil] factor:std::exp(e.magnification*2) vertical:NO]; }
- (BOOL)handleNavigationKey:(NSEvent*)e {
    if(!document||dragging)return NO;
    if((e.modifierFlags&NSEventModifierFlagShift)&&e.keyCode>=123&&e.keyCode<=126){
        followSuspended=YES;viewport.pan(e.keyCode==123?-viewport.span*.2:e.keyCode==124?viewport.span*.2:0,e.keyCode==126?viewport.rows*.2:e.keyCode==125?-viewport.rows*.2:0);self.needsDisplay=YES;return YES;
    }
    NSString *key=e.charactersIgnoringModifiers.lowercaseString;
    if([key isEqual:@"f"]&&!(e.modifierFlags&(NSEventModifierFlagCommand|NSEventModifierFlagControl))){[self fitView];return YES;}
    if([key isEqual:@"+"]||[key isEqual:@"="]||[key isEqual:@"-"]){NSRect r=[self plotRect];[self zoomAt:NSMakePoint(NSMidX(r),NSMidY(r)) factor:[key isEqual:@"-"]?1/1.5:1.5 vertical:(e.modifierFlags&NSEventModifierFlagOption)!=0];return YES;}
    return NO;
}
- (NSRect)rectForNote:(const pitch::Note&)note index:(NSInteger)index {
    double shift = dragging && index == selected ? previewShift : note.semitones;
    double start=dragging&&resizeEdge&&index==selected?previewStart:note.start;
    double end=dragging&&resizeEdge&&index==selected?previewEnd:note.end;
    return NSMakeRect([self xForTime:start], [self yForPitch:note.originalMidi + shift],
                      std::max(3.0, [self xForTime:end] - [self xForTime:start]), [self rowHeight] * 0.78);
}
- (void)resetCursorRects {
    [super resetCursorRects];if(!document)return;
    const auto& notes=document->analysis().notes;
    for(std::size_t i=0;i<notes.size();++i){NSRect rect=[self rectForNote:notes[i] index:i];double hit=std::min(5.,rect.size.width*.2);
        [self addCursorRect:NSIntersectionRect([self plotRect],NSMakeRect(NSMinX(rect),NSMinY(rect),hit,rect.size.height)) cursor:NSCursor.resizeLeftRightCursor];
        [self addCursorRect:NSIntersectionRect([self plotRect],NSMakeRect(NSMaxX(rect)-hit,NSMinY(rect),hit,rect.size.height)) cursor:NSCursor.resizeLeftRightCursor];
    }
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
    [self.window invalidateCursorRectsForView:self];
    [neutral(0x36) setFill]; NSRectFill(self.bounds);
    const double row = [self rowHeight];
    NSRect plot=[self plotRect];
    [NSGraphicsContext saveGraphicsState];NSRectClip(plot);
    [neutral(0x3e) setFill];NSRectFill(plot); // DetailViewBackground
    for (int midi = (int)std::floor(viewport.top-viewport.rows); midi <= (int)std::ceil(viewport.top); ++midi) {
        int pc = ((midi % 12) + 12) % 12;
        BOOL black = pc == 1 || pc == 3 || pc == 6 || pc == 8 || pc == 10;
        double y = [self yForPitch:midi];
        [(black ? neutral(0x36) : neutral(0x3e)) setFill];
        double left=plot.origin.x;
        NSRectFill(NSMakeRect(left, y, self.bounds.size.width-left, row));
        [neutral(0x39) setFill]; NSRectFill(NSMakeRect(left,y,self.bounds.size.width-left,0.5));
    }
    [NSGraphicsContext restoreGraphicsState];
    for(int midi=(int)std::ceil(viewport.top-viewport.rows+1);midi<=std::floor(viewport.top);midi++){
        int pc=((midi%12)+12)%12;
        if(pc==0||row>=17){NSArray *names=@[@"C",@"C♯",@"D",@"D♯",@"E",@"F",@"F♯",@"G",@"G♯",@"A",@"A♯",@"B"];label([NSString stringWithFormat:@"%@%d",names[pc],midi/12-1],NSMakePoint(8,[self yForPitch:midi]+1),neutral(0x91),10);}
    }
    label(@"Fit",NSMakePoint(8,5),neutral(0xb5),10);

    NSString *hint=@"Drag a note up or down to change pitch";
    if(document&&selected>=0){const auto& n=document->analysis().notes[selected];double shift=dragging?previewShift:n.semitones;
        int midi=(int)std::round(n.originalMidi+shift);NSArray *names=@[@"C",@"C♯",@"D",@"D♯",@"E",@"F",@"F♯",@"G",@"G♯",@"A",@"A♯",@"B"];
        hint=[NSString stringWithFormat:@"%@%d %+.0f cents  ·  %+.2f semitones",names[((midi%12)+12)%12],midi/12-1,(n.originalMidi+shift-midi)*100,shift];}
    label(hint,NSMakePoint(48,self.bounds.size.height-15),neutral(0xb5),10);

    if (!document) {
        label(self.embeddedTimeline ? @"Analyzing selected audio clip…" : @"Open a solo vocal recording to detect its notes", NSMakePoint(88,90), neutral(0xb5), 16);
        if(!self.embeddedTimeline)label(@"Development editor • Audio rendering pending", NSMakePoint(88,120), neutral(0x91), 12);
        return;
    }
    double desired=viewport.span/(plot.size.width/80);
    double base=std::pow(10,std::floor(std::log10(std::max(.001,desired))));
    double step=(desired/base<=1?1:desired/base<=2?2:desired/base<=5?5:10)*base;
    for(double t=std::ceil(viewport.start/step)*step;t<=viewport.start+viewport.span;t+=step){
        double x=[self xForTime:t];label([NSString stringWithFormat:@"%.*fs",step<1?2:0,t],NSMakePoint(x+3,5),neutral(0x91),10);
    }
    [NSGraphicsContext saveGraphicsState];NSRectClip(plot);
    for(double t=std::ceil(viewport.start/step)*step;t<=viewport.start+viewport.span;t+=step){[neutral(0x2b) setFill];NSRectFill(NSMakeRect([self xForTime:t],plot.origin.y,.5,plot.size.height));}
    auto gainNotes=document->analysis().notes;
    if(dragging&&selected>=0){
        if(gainDragging)gainNotes[selected].gainDb=previewGain;
        if(resizeEdge){gainNotes[selected].start=previewStart;gainNotes[selected].end=previewEnd;}
    }
    // Reduce visible source peaks per screen column; never decode PCM during drawing.
    const auto& analysis = document->analysis();
    if (!analysis.waveform.empty() && analysis.waveformStep > 0) {
        [neutral(0x1b, .8) setFill];
        const double amplitude = plot.size.height * .44;
        for (double column = 0; column < plot.size.width; column += 1) {
            double begin = viewport.start + column / plot.size.width * viewport.span;
            double end = viewport.start + std::min(column + 1, plot.size.width) / plot.size.width * viewport.span;
            if (begin >= analysis.duration || end <= 0) continue;
            auto first = static_cast<std::size_t>(std::max(0.0, std::floor(begin / analysis.waveformStep)));
            auto last = std::min(analysis.waveform.size(), static_cast<std::size_t>(std::ceil(end / analysis.waveformStep)));
            if (first >= last) continue;
            float lo=0,hi=0;
            for(auto i=first;i<last;++i){
                double gain=pitch::gainAtTime(gainNotes,(i+.5)*analysis.waveformStep);
                lo=std::min(lo,(float)(analysis.waveform[i].minimum*gain));
                hi=std::max(hi,(float)(analysis.waveform[i].maximum*gain));
            }
            double top = NSMidY(plot) - std::clamp(hi, -1.0f, 1.0f) * amplitude;
            double bottom = NSMidY(plot) - std::clamp(lo, -1.0f, 1.0f) * amplitude;
            NSRectFillUsingOperation(NSMakeRect(plot.origin.x + column, top, 1, std::max(.5, bottom - top)), NSCompositingOperationSourceOver);
        }
    }
    auto notes = document->analysis().notes;
    if(dragging&&resizeEdge&&selected>=0){notes[selected].start=previewStart;notes[selected].end=previewEnd;}
    for (std::size_t i = 0; i < notes.size(); ++i) {
        const auto& note = notes[i];
        NSRect rect = [self rectForNote:note index:i];
        if(!NSIntersectsRect(rect,plot))continue;
        [(selected == static_cast<NSInteger>(i) ? color(.94,.72,.35) : color(.72,.49,.73)) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3] fill];
        if(selected==(NSInteger)i&&rect.size.width>=12){[neutral(0x40) setFill];NSRectFill(NSMakeRect(NSMinX(rect)+2,NSMinY(rect)+1,1,std::max(1.,rect.size.height-2)));NSRectFill(NSMakeRect(NSMaxX(rect)-3,NSMinY(rect)+1,1,std::max(1.,rect.size.height-2)));}
        if (rect.size.width > 45 && row > 16) {
            double shift = dragging && selected == static_cast<NSInteger>(i) ? previewShift : note.semitones;
            label([NSString stringWithFormat:@"%+.2f st",shift], NSMakePoint(rect.origin.x+6,rect.origin.y+1),color(.16,.13,.17),10);
        }
    }
    if(selected>=0){
        NSRect vibratoHandle=[self vibratoHandleRect];[neutral(0xb8) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:vibratoHandle] fill];
        double amount=vibratoDragging?previewVibrato:document->analysis().notes[selected].vibrato;
        for(NSInteger side:{-1,1}){NSRect handle=[self driftHandleRect:side];[neutral(0xb8) setFill];[[NSBezierPath bezierPathWithOvalInRect:handle] fill];}
        const auto& n=document->analysis().notes[selected];
        double start=driftDragging<0?previewDrift:n.driftStart,end=driftDragging>0?previewDrift:n.driftEnd;
        NSString *feedback=driftDragging?[NSString stringWithFormat:@"Drift %@ %+.0f cents",driftDragging<0?@"start":@"end",previewDrift]:[NSString stringWithFormat:@"Start %+.0fc   Vibrato %.0f%%   End %+.0fc",start,amount*100,end];
        label(feedback,NSMakePoint(std::clamp(NSMidX(vibratoHandle)-100,NSMinX(plot),std::max(NSMinX(plot),NSMaxX(plot)-215)),NSMinY(vibratoHandle)-14),neutral(0xc0),10);
        NSRect handle=[self gainHandleRect];[neutral(0xb8) setFill];
        [[NSBezierPath bezierPathWithOvalInRect:handle] fill];
        [neutral(0x35) setFill];NSRectFill(NSInsetRect(handle,2,4));
        double gain=gainDragging?previewGain:document->analysis().notes[selected].gainDb;
        NSRect toneHandle=[self formantHandleRect];[neutral(0xb8) setFill];[[NSBezierPath bezierPathWithOvalInRect:toneHandle] fill];
        double tone=formantDragging?previewFormant:n.formant;
        label([NSString stringWithFormat:@"Gain %+.1f dB   Formant %+.2f st",gain,tone],NSMakePoint(std::clamp(NSMidX(handle)-85,NSMinX(plot),std::max(NSMinX(plot),NSMaxX(plot)-200)),NSMaxY(handle)+2),neutral(0xc0),10);
    }
    // Show the estimated edited contour inside the moved notes; this is not re-analysis.
    NSBezierPath* contour = [NSBezierPath bezierPath];
    BOOL active = NO;
    for (const auto& frame : document->analysis().frames) {
        if (!frame.voiced) { active = NO; continue; }
        double offset=0;
        for(std::size_t i=0;i<notes.size();++i)if(frame.time>=notes[i].start&&frame.time<notes[i].end){offset=dragging&&selected==(NSInteger)i?previewShift:notes[i].semitones;break;}
        NSPoint p = NSMakePoint([self xForTime:frame.time],[self yForPitch:frame.midi+offset+pitch::expressionAt(expression,frame.time)] + row * .39);
        if (active) [contour lineToPoint:p]; else [contour moveToPoint:p];
        active = YES;
    }
    [color(.87,.84,.9) setStroke]; contour.lineWidth = 1; [contour stroke];
    if(playheadVisible){
        double x=[self xForTime:playheadSeconds];
        if(x>=NSMinX(plot)&&x<=NSMaxX(plot)){
            [color(.64,.64,.64) setFill];
            NSRectFill(NSMakeRect(std::round(x),NSMinY(plot),1,plot.size.height));

        }
    }
    [NSGraphicsContext restoreGraphicsState];
}
- (NSRect)driftHandleRect:(NSInteger)side {
    if(!document||selected<0)return NSZeroRect;
    NSRect note=[self rectForNote:document->analysis().notes[selected] index:selected];
    double x=side<0?std::min(NSMinX(note),NSMidX(note)-16):std::max(NSMaxX(note),NSMidX(note)+16);
    return NSMakeRect(x-5,NSMinY(note)-12,10,10);
}
- (NSRect)vibratoHandleRect {
    if(!document||selected<0)return NSZeroRect;
    NSRect note=[self rectForNote:document->analysis().notes[selected] index:selected];
    return NSMakeRect(NSMidX(note)-5,NSMinY(note)-12,10,10);
}
- (NSRect)formantHandleRect {
    if(!document||selected<0)return NSZeroRect;
    NSRect note=[self rectForNote:document->analysis().notes[selected] index:selected];
    return NSMakeRect(std::max(NSMaxX(note),NSMidX(note)+16)-5,NSMaxY(note)+2,10,10);
}
- (NSRect)gainHandleRect {
    if(!document||selected<0)return NSZeroRect;
    NSRect note=[self rectForNote:document->analysis().notes[selected] index:selected];
    return NSMakeRect(NSMidX(note)-5,NSMaxY(note)+2,10,10);
}
- (void)mouseDown:(NSEvent*)event {
    [self.window makeFirstResponder:self];
    if (!document) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if(point.y<24&&point.x<48){[self fitView];return;}
    rulerClick=NO;
    if((event.modifierFlags&NSEventModifierFlagOption)||point.y<24||point.x<48){panning=YES;followSuspended=YES;lastPan=point;dragOrigin=point;rulerClick=point.y<24&&point.x>=48&&!(event.modifierFlags&NSEventModifierFlagOption);return;}
    if(!NSPointInRect(point,[self plotRect]))return;
    gainDragging=NO;vibratoDragging=NO;driftDragging=0;formantDragging=NO;
    if(selected>=0&&NSPointInRect(point,[self formantHandleRect])){
        const auto& note=document->analysis().notes[selected];
        if(event.clickCount==2){if(document->setFormant(note.id,0))[self notifyEdit];self.needsDisplay=YES;return;}
        initialFormant=previewFormant=note.formant;initialShift=previewShift=note.semitones;
        formantDragging=YES;dragging=YES;resizeEdge=0;dragOrigin=point;
        if(self.noteAudition)self.noteAudition(note,NO);return;
    }
    if(selected>=0)for(NSInteger side:{-1,1})if(NSPointInRect(point,[self driftHandleRect:side])){
        const auto& note=document->analysis().notes[selected];
        if(event.clickCount==2){if(document->setDrift(note.id,side<0?0:note.driftStart,side>0?0:note.driftEnd))[self notifyEdit];self.needsDisplay=YES;return;}
        initialDrift=previewDrift=side<0?note.driftStart:note.driftEnd;
        initialShift=previewShift=note.semitones;driftDragging=side;dragging=YES;resizeEdge=0;dragOrigin=point;
        if(self.noteAudition)self.noteAudition(note,NO);return;
    }
    if(selected>=0&&NSPointInRect(point,[self vibratoHandleRect])){
        const auto& note=document->analysis().notes[selected];
        if(event.clickCount==2){if(document->setVibrato(note.id,1))[self notifyEdit];self.needsDisplay=YES;return;}
        initialVibrato=previewVibrato=note.vibrato;initialShift=previewShift=note.semitones;
        vibratoDragging=YES;dragging=YES;resizeEdge=0;dragOrigin=point;
        if(self.noteAudition)self.noteAudition(note,NO);return;
    }
    if(selected>=0&&NSPointInRect(point,[self gainHandleRect])){
        const auto& note=document->analysis().notes[selected];
        if(event.clickCount==2){if(document->setGain(note.id,0))[self notifyEdit];self.needsDisplay=YES;return;}
        initialGain=previewGain=note.gainDb;initialShift=previewShift=note.semitones;
        gainDragging=YES;dragging=YES;resizeEdge=0;dragOrigin=point;
        if(self.noteAudition)self.noteAudition(note,NO);return;
    }
    // A second click on a note keeps selection; only the Fit control changes the viewport.
    selected = -1;
    const auto& notes = document->analysis().notes;
    for (std::size_t i = 0; i < notes.size(); ++i) {
        if (NSPointInRect(point,[self rectForNote:notes[i] index:i])) {
            selected = i; initialShift = previewShift = notes[i].semitones;
            NSRect rect=[self rectForNote:notes[i] index:i];double hit=std::min(5.,rect.size.width*.2);
            resizeEdge=point.x-NSMinX(rect)<hit?-1:NSMaxX(rect)-point.x<hit?1:0;
            previewStart=notes[i].start;previewEnd=notes[i].end;
            dragOrigin = point; dragging = YES; if(!resizeEdge&&self.noteAudition)self.noteAudition(notes[i],NO); break;
        }
    }
    if(selected<0)[self requestCursor:point];
    self.needsDisplay = YES;
}
- (void)requestCursor:(NSPoint)point {
    if(!document)return;
    double seconds=std::clamp(viewport.start+(point.x-[self plotRect].origin.x)/[self plotRect].size.width*viewport.span,0.,document->analysis().duration);
    if(self.cursorRequested)self.cursorRequested(seconds);
    else [self setPlayheadSeconds:seconds playing:NO valid:YES];
}
- (void)mouseDragged:(NSEvent*)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if(panning){if(rulerClick&&std::hypot(p.x-dragOrigin.x,p.y-dragOrigin.y)<3)return;rulerClick=NO;NSRect r=[self plotRect];viewport.pan((lastPan.x-p.x)/r.size.width*viewport.span,(p.y-lastPan.y)/r.size.height*viewport.rows);lastPan=p;self.needsDisplay=YES;return;}
    if (!dragging) return;
    if(formantDragging){
        previewFormant=std::clamp(initialFormant+(dragOrigin.y-p.y)*((event.modifierFlags&NSEventModifierFlagShift)?.01:.05),-6.,6.);
        auto notes=[self noteSnapshot];notes[selected].formant=previewFormant;
        if(self.editCommitted)self.editCommitted(notes);if(self.noteAudition)self.noteAudition(notes[selected],NO);
        self.needsDisplay=YES;return;
    }
    if(driftDragging){
        previewDrift=std::clamp(initialDrift+(dragOrigin.y-p.y)*((event.modifierFlags&NSEventModifierFlagShift)?.2:2.),-200.,200.);
        auto notes=[self noteSnapshot];if(driftDragging<0)notes[selected].driftStart=previewDrift;else notes[selected].driftEnd=previewDrift;
        expression=pitch::expressionCurve(document->analysis().frames,notes);
        if(self.editCommitted)self.editCommitted(notes);if(self.noteAudition)self.noteAudition(notes[selected],NO);
        self.needsDisplay=YES;return;
    }
    if(vibratoDragging){
        previewVibrato=std::clamp(initialVibrato+(dragOrigin.y-p.y)*((event.modifierFlags&NSEventModifierFlagShift)?.001:.01),0.,1.);
        auto notes=[self noteSnapshot];notes[selected].vibrato=previewVibrato;
        expression=pitch::expressionCurve(document->analysis().frames,notes);
        if(self.editCommitted)self.editCommitted(notes);if(self.noteAudition)self.noteAudition(notes[selected],NO);
        self.needsDisplay=YES;return;
    }
    if(gainDragging){
        previewGain=std::clamp(initialGain+(dragOrigin.y-p.y)*((event.modifierFlags&NSEventModifierFlagShift)?.02:.1),-24.,12.);
        auto notes=[self noteSnapshot];notes[selected].gainDb=previewGain;
        if(self.editCommitted)self.editCommitted(notes);if(self.noteAudition)self.noteAudition(notes[selected],NO);
        self.needsDisplay=YES;return;
    }
    if(resizeEdge){
        auto notes=[self noteSnapshot];const auto& note=notes[selected];
        double delta=(p.x-dragOrigin.x)/[self plotRect].size.width*viewport.span;
        if(resizeEdge<0){double lower=selected>0?notes[selected-1].end:0;double upper=note.end-.02;if(lower<=upper)previewStart=std::clamp(note.start+delta,lower,upper);}
        else {double lower=note.start+.02;double upper=selected+1<(NSInteger)notes.size()?notes[selected+1].start:document->analysis().duration;if(lower<=upper)previewEnd=std::clamp(note.end+delta,lower,upper);}
        notes[selected].start=previewStart;notes[selected].end=previewEnd;
        expression=pitch::expressionCurve(document->analysis().frames,notes);
        if(self.editCommitted)self.editCommitted(notes);self.needsDisplay=YES;return;
    }
    // Fine drag uses one cent per screen point, independent of vertical zoom.
    double next=pitch::dragPitchOffset(document->analysis().notes[selected].originalMidi,initialShift,dragOrigin.y-p.y,[self rowHeight],(event.modifierFlags&NSEventModifierFlagShift)!=0,snapButton.state==NSControlStateValueOn);
    if(next!=previewShift){previewShift=next;auto notes=[self noteSnapshot];notes[selected].semitones=next;if(self.editCommitted)self.editCommitted(notes);if(self.noteAudition)self.noteAudition(notes[selected],NO);}
    self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent*)event {
    if(rulerClick)[self requestCursor:[self convertPoint:event.locationInWindow fromView:nil]];
    rulerClick=NO;panning=NO;
    dispatch_async(dispatch_get_main_queue(),^{if(self.window)[self.window makeFirstResponder:self];});
    if (!dragging || !document) return;
    const auto& note=document->analysis().notes[selected];
    BOOL changed=formantDragging?document->setFormant(note.id,previewFormant):driftDragging?document->setDrift(note.id,driftDragging<0?previewDrift:note.driftStart,driftDragging>0?previewDrift:note.driftEnd):vibratoDragging?document->setVibrato(document->analysis().notes[selected].id,previewVibrato):gainDragging?document->setGain(document->analysis().notes[selected].id,previewGain):resizeEdge?document->resize(document->analysis().notes[selected].id,previewStart,previewEnd):document->transpose(document->analysis().notes[selected].id, previewShift);
    if(changed)[self notifyEdit];
    else if(self.editCommitted)self.editCommitted([self noteSnapshot]);
    if(!resizeEdge&&self.noteAudition)self.noteAudition(document->analysis().notes[selected],YES);
    dragging = NO;formantDragging=NO;gainDragging=NO;vibratoDragging=NO;driftDragging=0;resizeEdge=0;[self rebuildExpression]; self.needsDisplay = YES;
}
- (void)undoEdit { if (document && !dragging) { if(document->undo()){[self clampSelection];[self notifyEdit];} self.needsDisplay = YES; } }
- (void)redoEdit { if (document && !dragging) { if(document->redo()){[self clampSelection];[self notifyEdit];} self.needsDisplay = YES; } }
- (void)keyDown:(NSEvent*)event {
    if([self handleRegionKey:event])return;
    if([self handleNavigationKey:event])return;
    if ((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers.lowercaseString isEqual:@"z"]) {
        if (event.modifierFlags & NSEventModifierFlagShift) [self redoEdit]; else [self undoEdit];
    } else if (document && !document->analysis().notes.empty() && !dragging && event.keyCode >= 123 && event.keyCode <= 126) {
        const auto& notes = document->analysis().notes;
        if (event.keyCode == 123 || event.keyCode == 124) {
            selected = selected < 0 ? 0 : std::clamp<NSInteger>(selected + (event.keyCode == 124 ? 1 : -1),0,notes.size()-1);
        } else {
            if (selected < 0) selected = 0;
            if(document->transpose(notes[selected].id, std::round((notes[selected].semitones + (event.keyCode == 126 ? 1 : -1)*((event.modifierFlags&NSEventModifierFlagOption)?.01:1))*100)/100)){[self notifyEdit];if(self.noteAudition){self.noteAudition(notes[selected],NO);self.noteAudition(notes[selected],YES);}}
        }
        if(selected>=0){
            const auto& n=notes[selected];
            if(n.start<viewport.start)viewport.start=n.start;
            else if(n.end>viewport.start+viewport.span)viewport.start=std::max(n.start,n.end-viewport.span);
            double pitch=n.originalMidi+n.semitones;
            if(pitch>viewport.top)viewport.top=pitch+1;
            else if(pitch<viewport.top-viewport.rows+2)viewport.top=pitch+viewport.rows-2;
            viewport.clamp();
        }
        self.needsDisplay = YES;
    } else [super keyDown:event];
}
@end
