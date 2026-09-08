#pragma once
#import <Cocoa/Cocoa.h>
#include "pitch_core.hpp"
#include "pitch_viewport.hpp"
#include <memory>

// Reusable view only: does not create a window or register with Live.
@interface PitchCanvas : NSView {
    std::unique_ptr<pitch::Document> document;
    NSInteger selected;
    NSPoint dragOrigin;
    double initialShift, previewShift;
    int lowest, highest;
    BOOL dragging, panning;
    pitch::Viewport viewport;
    NSPoint lastPan;
    double playheadSeconds;
    BOOL playheadVisible, playbackRunning, followSuspended;
}
@property BOOL embeddedTimeline;
@property (nonatomic) BOOL followPlayback;
- (void)setAnalysis:(pitch::Analysis)analysis;
- (void)setPlayheadSeconds:(double)seconds playing:(BOOL)playing valid:(BOOL)valid;
- (void)fitView;
- (BOOL)handleNavigationKey:(NSEvent*)event;
- (void)undoEdit;
- (void)redoEdit;
@end
