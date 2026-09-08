#import <AVFoundation/AVFoundation.h>
#include "pitch_core.hpp"
#include "pitch_render.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <iostream>
#include <stdexcept>

int main(int argc,char** argv){ @autoreleasepool { try {
    if(argc!=3&&argc!=5)throw std::runtime_error("Usage: pitch-render input.wav output.wav [note-number(1-based) semitones]; omit edit for exact PCM bypass");
    NSString *inPath=[NSString stringWithUTF8String:argv[1]], *outPath=[NSString stringWithUTF8String:argv[2]];
    if([[NSFileManager defaultManager] fileExistsAtPath:outPath])throw std::runtime_error("Output already exists; choose a new path");
    NSError *error=nil;
    AVAudioFile *file=[[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:inPath] error:&error];
    if(!file)throw std::runtime_error(error.localizedDescription.UTF8String);
    if(file.length<=0||file.length>file.processingFormat.sampleRate*60||file.processingFormat.channelCount>2)throw std::runtime_error("Expected nonempty mono/stereo audio, maximum 60 seconds");
    AVAudioPCMBuffer *buffer=[[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat frameCapacity:(AVAudioFrameCount)file.length];
    if(![file readIntoBuffer:buffer error:&error]||!buffer.floatChannelData)throw std::runtime_error("Cannot decode float PCM");
    pitch::AudioAsset source;source.sampleRate=buffer.format.sampleRate;
    std::size_t strongest=0;double bestEnergy=-1;
    for(unsigned c=0;c<buffer.format.channelCount;++c){
        auto data=buffer.floatChannelData[c]; source.channels.emplace_back(data,data+buffer.frameLength);
        double sum=0,squares=0;for(auto v:source.channels.back()){sum+=v;squares+=v*v;}
        double energy=squares-sum*sum/source.frames(); if(energy>bestEnergy){bestEnergy=energy;strongest=c;}
    }
    auto analysis=pitch::analyze(source.channels[strongest],source.sampleRate);
    NSMutableArray *notes=[NSMutableArray array];
    for(const auto& n:analysis.notes)[notes addObject:@{@"number":@(n.id+1),@"start":@(n.start),@"end":@(n.end),@"midi":@(n.originalMidi)}];
    pitch::RenderPlan plan;
    if(argc==5){
        std::size_t used=0;int number=std::stoi(argv[3],&used);
        if(used!=strlen(argv[3])||number<1||number>(int)analysis.notes.size())throw std::runtime_error("Invalid note number");
        double shift=std::stod(argv[4],&used);if(used!=strlen(argv[4]))throw std::runtime_error("Invalid semitone value");
        auto n=analysis.notes[number-1];plan.regions.push_back({(std::size_t)std::llround(n.start*source.sampleRate),(std::size_t)std::llround(n.end*source.sampleRate),shift});
    }
    auto begin=std::chrono::steady_clock::now();auto result=pitch::RubberBandRenderer().render(source,plan);
    double elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count();
    AVAudioFormat *format=[[AVAudioFormat alloc] initStandardFormatWithSampleRate:source.sampleRate channels:(AVAudioChannelCount)source.channels.size()];
    AVAudioPCMBuffer *rendered=[[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:(AVAudioFrameCount)source.frames()];rendered.frameLength=(AVAudioFrameCount)source.frames();
    for(unsigned c=0;c<format.channelCount;++c)std::copy(result.audio.channels[c].begin(),result.audio.channels[c].end(),rendered.floatChannelData[c]);
    NSString *temp=[outPath stringByAppendingFormat:@".%@.tmp.wav",NSUUID.UUID.UUIDString];
    NSDictionary *settings=@{AVFormatIDKey:@(kAudioFormatLinearPCM),AVSampleRateKey:@(source.sampleRate),AVNumberOfChannelsKey:@(source.channels.size()),AVLinearPCMBitDepthKey:@32,AVLinearPCMIsFloatKey:@YES,AVLinearPCMIsBigEndianKey:@NO,AVLinearPCMIsNonInterleaved:@NO};
    AVAudioFile *writer=[[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:temp] settings:settings error:&error];
    BOOL written=writer&&[writer writeFromBuffer:rendered error:&error];writer=nil;
    if(!written||![[NSFileManager defaultManager] moveItemAtPath:temp toPath:outPath error:&error]){
        [[NSFileManager defaultManager] removeItemAtPath:temp error:nil];throw std::runtime_error(error.localizedDescription.UTF8String);
    }
    NSMutableArray *edits=[NSMutableArray array];
    for(const auto& region:plan.regions)[edits addObject:@{@"beginFrame":@(region.begin),@"endFrame":@(region.end),@"semitones":@(region.semitones)}];
    NSDictionary *report=@{@"source":inPath,@"output":outPath,@"edits":edits,@"transitionSeconds":@(plan.transitionSeconds),@"preserveFormants":@(plan.preserveFormants),@"backend":@"Rubber Band 4.0.0 R3",@"sampleRate":@(source.sampleRate),@"frames":@(source.frames()),@"channels":@(source.channels.size()),@"bypassed":@(result.bypassed),@"peak":@(result.peak),@"renderSeconds":@(elapsed),@"startPad":@(result.startPad),@"startDelay":@(result.startDelay),@"notes":notes};
    NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
    std::cout<<[[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] UTF8String]<<"\n";
    return 0;
} catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;} } }
