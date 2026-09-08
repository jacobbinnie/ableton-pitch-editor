#pragma once
#include "pitch_render.hpp"
#include "pitch_stream.hpp"
#include <array>

namespace pitch {
// Construct/publish on the control thread. render() runs on one audio thread.
// The AVAudioSourceNode owns this runtime for the lifetime of its render block.
class AuditionRuntime {
    std::shared_ptr<const AudioAsset> source;
    StreamStateStore states;
    StreamShifter shifter;
    std::size_t position;
    std::array<double,64> left{},right{},outLeft{},outRight{};
public:
    AuditionRuntime(std::shared_ptr<const AudioAsset> audio,Note note,const std::vector<Frame>& frames,std::size_t pitchLag=1024)
        :source(std::move(audio)),shifter(source->sampleRate,pitchLag),position((std::size_t)(note.start*source->sampleRate)) {publish(note,frames);}
    void publish(Note note,const std::vector<Frame>& frames){
        StreamState state;state.enabled=true;state.end=source->frames()/source->sampleRate;
        state.warp={{0,0},{state.end,state.end}};state.notes={note};
        state.expression=std::make_shared<const ExpressionCurve>(expressionCurve(frames,state.notes));states.publish(std::move(state));
    }
    void render(float *l,float *r,std::size_t count){
        const auto* state=states.acquire();
        if(!state||state->notes.empty()){std::fill(l,l+count,0);std::fill(r,r+count,0);states.release();return;}
        const auto& note=state->notes[0];
        std::size_t begin=std::min(source->frames(),(std::size_t)std::max(0.,std::floor(note.start*source->sampleRate)));
        std::size_t end=std::min(source->frames(),(std::size_t)std::ceil(note.end*source->sampleRate));
        if(end<=begin){std::fill(l,l+count,0);std::fill(r,r+count,0);states.release();return;}
        for(std::size_t offset=0;offset<count;){
            if(position<begin||position>=end)position=begin;
            auto n=std::min({left.size(),count-offset,end-position});
            double time=position/source->sampleRate;
            for(std::size_t i=0;i<n;++i){
                double fade=std::min(1.,std::min(double(position+i-begin),double(end-1-position-i))/(source->sampleRate*.005));
                left[i]=source->channels[0][position+i]*fade*.8;
                right[i]=source->channels[source->channels.size()>1?1:0][position+i]*fade*.8;
            }
            shifter.process(left.data(),right.data(),outLeft.data(),outRight.data(),n,state->shiftAt(time),state->gainAt(time),state->expression&&!state->expression->empty(),state->formantAt(time));
            for(std::size_t i=0;i<n;++i){l[offset+i]=(float)outLeft[i];r[offset+i]=(float)outRight[i];}
            position+=n;offset+=n;
        }
        states.release();
    }
};
}
