#pragma once
#import <Cocoa/Cocoa.h>
#include "pitch_render.hpp"
#include "pitch_core.hpp"
#include <memory>

// In-memory note audition. Live transport audio is processed by the MSP callback.
@interface PitchRenderSession : NSObject
@property (copy) void (^statusChanged)(NSString *status, BOOL ready);
- (instancetype)initWithAudio:(std::shared_ptr<const pitch::AudioAsset>)audio frames:(std::vector<pitch::Frame>)frames;
- (void)auditionNote:(pitch::Note)note;
- (void)finishAudition;
- (void)stop;
- (void)invalidate;
@end
