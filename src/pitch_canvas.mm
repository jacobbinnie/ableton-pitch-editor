#import "pitch_canvas.hpp"
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

@implementation PitchCanvas
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) { selected = -1; lowest = 48; highest = 84; }
    return self;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)isAccessibilityElement { return YES; }
- (NSString*)accessibilityRole { return NSAccessibilityGroupRole; }
- (NSString*)accessibilityLabel { return @"Pitch notes"; }
- (NSString*)accessibilityHelp { return @"Scroll to pan. Command-scroll or pinch to zoom time; Option-scroll zooms pitch. Option-drag or ruler drag pans. Shift-arrows pan. Plus/minus zoom; F fits. Left/right select notes, up/down transpose. Command Z undoes."; }
- (id)accessibilityValue {
    NSString *play=playheadVisible?[NSString stringWithFormat:@"; playhead %.2fs %@",playheadSeconds,playbackRunning?@"playing":@"stopped"]:@"";
    if (!document) return @"No audio loaded";
    if (selected < 0) return [NSString stringWithFormat:@"%lu notes; no selection; view %.2f to %.2f seconds; %.1f pitch rows, top %.1f%@",static_cast<unsigned long>(document->analysis().notes.size()),viewport.start,viewport.start+viewport.span,viewport.rows,viewport.top,play];
    const auto& note = document->analysis().notes[selected];
    return [NSString stringWithFormat:@"Note %ld, %.2f to %.2f seconds, transposition %+.0f semitones%@",static_cast<long>(selected+1),note.start,note.end,note.semitones,play];
}
- (void)setAnalysis:(pitch::Analysis)analysis {
    document = std::make_unique<pitch::Document>(std::move(analysis));
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
    if(playing){
        playheadSeconds=seconds;playheadVisible=seconds>=0&&seconds<=document->analysis().duration;
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
    return NSMakeRect([self xForTime:note.start], [self yForPitch:note.originalMidi + shift],
                      std::max(3.0, [self xForTime:note.end] - [self xForTime:note.start]), [self rowHeight] * 0.78);
}
- (void)drawRect:(NSRect)dirty {
    (void)dirty;
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
    label(@"Scroll / ruler drag: pan   ⌘ scroll: time zoom   ⌥ scroll: pitch zoom   F: fit",NSMakePoint(48,self.bounds.size.height-15),neutral(0x91),9);

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
            float lo = analysis.waveform[first].minimum, hi = analysis.waveform[first].maximum;
            for (auto i = first + 1; i < last; ++i) {
                lo = std::min(lo, analysis.waveform[i].minimum);
                hi = std::max(hi, analysis.waveform[i].maximum);
            }
            double top = NSMidY(plot) - std::clamp(hi, -1.0f, 1.0f) * amplitude;
            double bottom = NSMidY(plot) - std::clamp(lo, -1.0f, 1.0f) * amplitude;
            NSRectFillUsingOperation(NSMakeRect(plot.origin.x + column, top, 1, std::max(.5, bottom - top)), NSCompositingOperationSourceOver);
        }
    }
    const auto& notes = document->analysis().notes;
    for (std::size_t i = 0; i < notes.size(); ++i) {
        const auto& note = notes[i];
        NSRect rect = [self rectForNote:note index:i];
        if(!NSIntersectsRect(rect,plot))continue;
        [(selected == static_cast<NSInteger>(i) ? color(.94,.72,.35) : color(.72,.49,.73)) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3] fill];
        if (rect.size.width > 45 && row > 16) {
            double shift = dragging && selected == static_cast<NSInteger>(i) ? previewShift : note.semitones;
            label([NSString stringWithFormat:@"%+.0f st",shift], NSMakePoint(rect.origin.x+6,rect.origin.y+1),color(.16,.13,.17),10);
        }
    }
    // Original contour stays visible, so edits do not conceal detector errors.
    NSBezierPath* contour = [NSBezierPath bezierPath];
    BOOL active = NO;
    for (const auto& frame : document->analysis().frames) {
        if (!frame.voiced) { active = NO; continue; }
        NSPoint p = NSMakePoint([self xForTime:frame.time],[self yForPitch:frame.midi] + row * .39);
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
- (void)mouseDown:(NSEvent*)event {
    [self.window makeFirstResponder:self];
    if (!document) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    if(point.y<24&&point.x<48){[self fitView];return;}
    if((event.modifierFlags&NSEventModifierFlagOption)||point.y<24||point.x<48){panning=YES;followSuspended=YES;lastPan=point;return;}
    if(!NSPointInRect(point,[self plotRect]))return;
    if(event.clickCount==2){[self fitView];return;}
    selected = -1;
    const auto& notes = document->analysis().notes;
    for (std::size_t i = 0; i < notes.size(); ++i) {
        if (NSPointInRect(point,[self rectForNote:notes[i] index:i])) {
            selected = i; initialShift = previewShift = notes[i].semitones;
            dragOrigin = point; dragging = YES; break;
        }
    }
    self.needsDisplay = YES;
}
- (void)mouseDragged:(NSEvent*)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    if(panning){NSRect r=[self plotRect];viewport.pan((lastPan.x-p.x)/r.size.width*viewport.span,(p.y-lastPan.y)/r.size.height*viewport.rows);lastPan=p;self.needsDisplay=YES;return;}
    if (!dragging) return;
    previewShift = std::clamp(initialShift + std::round((dragOrigin.y - p.y) / [self rowHeight]), -24.0, 24.0);
    self.needsDisplay = YES;
}
- (void)mouseUp:(NSEvent*)event {
    (void)event;panning=NO;
    dispatch_async(dispatch_get_main_queue(),^{if(self.window)[self.window makeFirstResponder:self];});
    if (!dragging || !document) return;
    document->transpose(document->analysis().notes[selected].id, previewShift);
    dragging = NO; self.needsDisplay = YES;
}
- (void)undoEdit { if (document && !dragging) { document->undo(); self.needsDisplay = YES; } }
- (void)redoEdit { if (document && !dragging) { document->redo(); self.needsDisplay = YES; } }
- (void)keyDown:(NSEvent*)event {
    if([self handleNavigationKey:event])return;
    if ((event.modifierFlags & NSEventModifierFlagCommand) && [event.charactersIgnoringModifiers.lowercaseString isEqual:@"z"]) {
        if (event.modifierFlags & NSEventModifierFlagShift) [self redoEdit]; else [self undoEdit];
    } else if (document && !document->analysis().notes.empty() && !dragging && event.keyCode >= 123 && event.keyCode <= 126) {
        const auto& notes = document->analysis().notes;
        if (event.keyCode == 123 || event.keyCode == 124) {
            selected = selected < 0 ? 0 : std::clamp<NSInteger>(selected + (event.keyCode == 124 ? 1 : -1),0,notes.size()-1);
        } else {
            if (selected < 0) selected = 0;
            document->transpose(notes[selected].id, notes[selected].semitones + (event.keyCode == 126 ? 1 : -1));
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
