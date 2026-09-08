#pragma once
#import <Cocoa/Cocoa.h>
#include "pitch_core.hpp"
#include "pitch_viewport.hpp"
#include "pitch_expression.hpp"
#include <memory>

// Reusable view only: does not create a window or register with Live.
@interface PitchCanvas : NSView {
    std::shared_ptr<pitch::Document> document;
    NSInteger selected;
    NSPoint dragOrigin;
    double initialShift, previewShift;
    int lowest, highest;
    BOOL dragging, panning;
    BOOL rulerClick;
    NSButton *snapButton;
    NSInteger resizeEdge;
    double previewStart,previewEnd;
    BOOL gainDragging,vibratoDragging;
    NSInteger driftDragging;
    double initialDrift,previewDrift;
    double initialVibrato,previewVibrato;
    pitch::ExpressionCurve expression;
    double initialGain,previewGain;
    NSString *audioStatus;
    pitch::Viewport viewport;
    NSPoint lastPan;
    double playheadSeconds;
    BOOL playheadVisible, playbackRunning, followSuspended;
}
@property BOOL embeddedTimeline;
@property (copy) void (^editCommitted)(std::vector<pitch::Note> notes);
@property (copy) void (^documentCommitted)(std::shared_ptr<pitch::Document> document);
@property (copy) void (^noteAudition)(pitch::Note note, BOOL finished);
@property (copy) void (^cursorRequested)(double sourceSeconds);

- (void)enableAudioControls;
- (void)setAudioStatus:(NSString*)status ready:(BOOL)ready;
- (std::vector<pitch::Note>)noteSnapshot;
@property (nonatomic) BOOL followPlayback;
- (void)setAnalysis:(pitch::Analysis)analysis;
- (void)setDocument:(std::shared_ptr<pitch::Document>)value;
- (void)setPlayheadSeconds:(double)seconds playing:(BOOL)playing valid:(BOOL)valid;
- (void)fitView;
- (BOOL)handleNavigationKey:(NSEvent*)event;
- (BOOL)handleRegionKey:(NSEvent*)event;
- (void)undoEdit;
- (void)redoEdit;
@end
