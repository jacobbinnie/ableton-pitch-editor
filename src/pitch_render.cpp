#include "pitch_render.hpp"
#include <rubberband/RubberBandStretcher.h>
#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace pitch {
static double smooth(double v) { v = std::clamp(v, 0.0, 1.0); return v*v*(3-2*v); }
double semitonesAt(const RenderPlan& plan, double frame, double rate) {
    for (const auto& region : plan.regions) {
        if (frame < region.begin || frame >= region.end) continue;
        double ramp = std::min(plan.transitionSeconds * rate, (region.end-region.begin)*.5);
        double weight = ramp > 0 ? smooth(std::min(frame-region.begin, region.end-frame)/ramp) : 1;
        return region.semitones * weight;
    }
    return 0;
}
RenderResult RubberBandRenderer::render(const AudioAsset& source, const RenderPlan& plan) const {
    if (!std::isfinite(source.sampleRate) || source.sampleRate < 8000 || source.sampleRate > 192000 ||
        std::floor(source.sampleRate) != source.sampleRate || source.channels.empty() || source.channels.size() > 2 ||
        source.frames() > source.sampleRate * 60)
        throw std::invalid_argument("Expected mono/stereo, integer 8–192 kHz, at most 60 seconds");
    for (const auto& channel : source.channels) {
        if(channel.size()!=source.frames()) throw std::invalid_argument("Channel lengths differ");
        for(float sample:channel) if(!std::isfinite(sample)) throw std::invalid_argument("Non-finite sample");
    }
    if(!std::isfinite(plan.transitionSeconds)||plan.transitionSeconds<0||plan.transitionSeconds>.25)
        throw std::invalid_argument("Invalid transition duration");
    std::size_t previousEnd=0; bool edited=false;
    for(const auto& region:plan.regions) {
        if(region.begin<previousEnd||region.end<=region.begin||region.end>source.frames()||
           !std::isfinite(region.semitones)||std::abs(region.semitones)>24)
            throw std::invalid_argument("Invalid, overlapping or unordered edit region");
        previousEnd=region.end; edited |= region.semitones!=0;
    }
    RenderResult result;
    if(!edited) { result.audio=source; result.bypassed=true; }
    else {
        using RB=RubberBand::RubberBandStretcher;
        auto options=RB::OptionProcessRealTime|RB::OptionEngineFiner|RB::OptionChannelsTogether|
            RB::OptionPitchHighConsistency|RB::OptionWindowShort|RB::OptionThreadingNever;
        if(plan.preserveFormants) options |= RB::OptionFormantPreserved;
        RB engine(static_cast<std::size_t>(source.sampleRate),source.channels.size(),options,1,1);
        constexpr std::size_t block=128;
        engine.setMaxProcessSize(block);
        result.startPad=engine.getPreferredStartPad(); result.startDelay=engine.getStartDelay();
        std::vector<std::vector<float>> collected(source.channels.size());
        std::vector<std::vector<float>> scratch(source.channels.size(),std::vector<float>(block));
        std::vector<float*> output(source.channels.size());
        std::vector<const float*> input(source.channels.size());
        for(std::size_t c=0;c<input.size();++c){ input[c]=scratch[c].data(); output[c]=scratch[c].data(); }
        auto drain=[&]{
            while(engine.available()>0){
                auto got=engine.retrieve(output.data(),std::min<std::size_t>(block,engine.available()));
                if(!got)throw std::runtime_error("Renderer output stalled");
                for(std::size_t c=0;c<output.size();++c)collected[c].insert(collected[c].end(),output[c],output[c]+got);
            }
        };
        const auto total=result.startPad+source.frames();
        for(std::size_t offset=0;offset<total;){
            const auto count=std::min(block,total-offset);
            // Pitch controls act on the next processed output window, not newly queued input.
            // Use the drained output clock, excluding startup latency; benchmark boundaries.
            double position=static_cast<double>(collected.front().size())-result.startDelay;
            engine.setPitchScale(std::exp2(semitonesAt(plan,position,source.sampleRate)/12));
            for(std::size_t c=0;c<input.size();++c)
                for(std::size_t i=0;i<count;++i)
                    scratch[c][i]=offset+i<result.startPad?0:source.channels[c][offset+i-result.startPad];
            engine.process(input.data(),count,offset+count==total); drain(); offset+=count;
        }
        result.audio.sampleRate=source.sampleRate;
        for(const auto& channel:collected){
            if(channel.size()<result.startDelay+source.frames())throw std::runtime_error("Renderer returned insufficient audio");
            result.audio.channels.emplace_back(channel.begin()+result.startDelay,channel.begin()+result.startDelay+source.frames());
        }
    }
    for(const auto& channel:result.audio.channels)for(float sample:channel){
        if(!std::isfinite(sample))throw std::runtime_error("Non-finite render output");
        result.peak=std::max(result.peak,std::abs(static_cast<double>(sample)));
    }
    return result;
}
}
