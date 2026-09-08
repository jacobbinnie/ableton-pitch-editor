#import "pitch_render_session.hpp"
#import <AVFoundation/AVFoundation.h>
#include "pitch_audition.hpp"

@implementation PitchRenderSession {
    std::shared_ptr<const pitch::AudioAsset> source;
    std::vector<pitch::Frame> analysisFrames;
    std::shared_ptr<pitch::AuditionRuntime> runtime;
    AVAudioEngine *audioEngine;
    AVAudioSourceNode *sourceNode;
    std::size_t activeNote;
    NSUInteger ticket;
    BOOL invalid;
}
- (instancetype)initWithAudio:(std::shared_ptr<const pitch::AudioAsset>)audio frames:(std::vector<pitch::Frame>)frames {
    if((self=[super init])){source=std::move(audio);analysisFrames=std::move(frames);activeNote=SIZE_MAX;}
    return self;
}
- (void)stop {++ticket;[audioEngine stop];audioEngine=nil;sourceNode=nil;runtime.reset();activeNote=SIZE_MAX;if(!invalid&&self.statusChanged)self.statusChanged(@"Live pitch editing",NO);}
- (void)invalidate {invalid=YES;[self stop];self.statusChanged=nil;}
- (void)dealloc {[audioEngine stop];}
- (void)auditionNote:(pitch::Note)note {
    if(invalid)return;
    ++ticket;
    if(audioEngine&&activeNote==note.id){runtime->publish(note,analysisFrames);return;}
    [self stop];activeNote=note.id;
    runtime=std::make_shared<pitch::AuditionRuntime>(source,note,analysisFrames);
    auto ownedRuntime=runtime;
    audioEngine=[AVAudioEngine new];
    auto format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:source->sampleRate channels:2];
    sourceNode=[[AVAudioSourceNode alloc] initWithFormat:format renderBlock:^OSStatus(BOOL *silent,const AudioTimeStamp *timestamp,AVAudioFrameCount count,AudioBufferList *buffers){
        (void)timestamp;
        if(buffers->mNumberBuffers!=2)return kAudio_ParamError;
        ownedRuntime->render((float*)buffers->mBuffers[0].mData,(float*)buffers->mBuffers[1].mData,count);
        *silent=NO;return noErr;
    }];
    [audioEngine attachNode:sourceNode];[audioEngine connect:sourceNode to:audioEngine.mainMixerNode format:format];
    NSError *error=nil;
    if(![audioEngine startAndReturnError:&error]){[self stop];if(self.statusChanged)self.statusChanged(@"Note audition unavailable",NO);return;}
    if(self.statusChanged)self.statusChanged(@"Auditioning note",YES);
}
- (void)finishAudition {
    NSUInteger expected=++ticket;__weak PitchRenderSession *weakSelf=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{PitchRenderSession *s=weakSelf;if(s&&s->ticket==expected)[s stop];});
}
@end
