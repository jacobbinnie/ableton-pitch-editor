#pragma once
#include "pitch_core.hpp"
#include "pitch_gain.hpp"
#include "pitch_expression.hpp"
#include "pitch_playback.hpp"
#include <rubberband/RubberBandLiveShifter.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <memory>
#include <vector>

namespace pitch {
struct StreamState {
    std::vector<Note> notes;
    std::vector<WarpPoint> warp;
    std::shared_ptr<const ExpressionCurve> expression;
    double start=0,end=0,marker=0,loopStart=0,loopEnd=0;
    bool enabled=false,loop=false;
    double gainAt(double songBeat) const {
        if(!enabled||songBeat<start||songBeat>=end)return 1;
        double beat=marker+songBeat-start;
        if(loop&&loopEnd>loopStart&&beat>=loopEnd)beat=loopStart+std::fmod(beat-loopStart,loopEnd-loopStart);
        auto time=sourceTime(beat,true,warp);return time?gainAtTime(notes,*time):1;
    }
    double shiftAt(double songBeat) const {
        if(!enabled||songBeat<start||songBeat>=end)return 0;
        double beat=marker+songBeat-start;
        if(loop&&loopEnd>loopStart&&beat>=loopEnd)beat=loopStart+std::fmod(beat-loopStart,loopEnd-loopStart);
        auto time=sourceTime(beat,true,warp);if(!time)return 0;
        for(std::size_t i=0;i<notes.size();++i)if(*time>=notes[i].start&&*time<notes[i].end){
            const auto& n=notes[i];double begin=n.start,finish=n.end;
            // Editing segmentation alone must not add a dip to the pitch curve.
            for(std::size_t j=i;j>0;--j){const auto& prev=notes[j-1];if(std::abs(prev.end-begin)>1e-6||std::abs(prev.semitones-n.semitones)>1e-9)break;begin=prev.start;}
            for(std::size_t j=i+1;j<notes.size();++j){const auto& next=notes[j];if(std::abs(next.start-finish)>1e-6||std::abs(next.semitones-n.semitones)>1e-9)break;finish=next.end;}
            double ramp=std::min(.015,(finish-begin)*.5);
            double w=std::clamp(std::min(*time-begin,finish-*time)/ramp,0.,1.);
            return std::clamp(n.semitones*w*w*(3-2*w)+(expression?expressionAt(*expression,*time):0),-24.,24.);
        }
        return 0;
    }
};
// Single control-thread publisher; sequentially consistent reader guard prevents
// deletion on the audio callback. Reclamation happens only on the control thread.
class StreamStateStore {
    std::atomic<const StreamState*> current{nullptr};
    std::atomic<unsigned> readers{0};
    std::unique_ptr<StreamState> owned;
    std::vector<std::unique_ptr<StreamState>> retired;
public:
    const StreamState* acquire(){++readers;return current.load();}
    void release(){--readers;}
    void publish(StreamState state){
        auto next=std::make_unique<StreamState>(std::move(state));
        current.store(next.get());if(owned)retired.push_back(std::move(owned));owned=std::move(next);
        if(readers.load()==0)retired.clear();
    }
};
class StreamShifter {
    RubberBand::RubberBandLiveShifter engine;
    std::vector<float> input[2],output[2],dry[2];
    std::size_t cursor=0,dryCursor=0;
    double wet=0,smoothedGain=1,gainCoefficient=0;
    std::vector<double> gainDelay,pitchDelay;
    std::size_t pitchCursor=0;
public:
    const std::size_t block,delay;
    explicit StreamShifter(double rate,std::size_t pitchLag=1024):engine((std::size_t)rate,2,RubberBand::RubberBandLiveShifter::OptionFormantPreserved|RubberBand::RubberBandLiveShifter::OptionChannelsTogether),block(engine.getBlockSize()),delay(engine.getStartDelay()+block){
        // Pinned R3 short-window control alignment: two 512-frame blocks.
        // Audio delay and parameter delay are different; see dynamic-F0 tests.
        pitchDelay.assign(pitchLag+1,0);gainDelay.assign(delay,1);gainCoefficient=1-std::exp(-1/(rate*.005));
        for(int c=0;c<2;++c){input[c].resize(block);output[c].resize(block);dry[c].resize(delay);}
    }
    void process(const double *left,const double *right,double *outLeft,double *outRight,std::size_t count,double shift,double gain=1,bool forceWet=false){
        for(std::size_t i=0;i<count;++i){
            input[0][cursor]=(float)left[i];input[1][cursor]=(float)right[i];
            // Delay-matched bypass keeps unity regions free from resynthesis.
            const double target=forceWet||std::abs(shift)>.0001?1:0;wet+=std::clamp(target-wet,-.002,.002);
            smoothedGain+=gainCoefficient*(gain-smoothedGain);
            double appliedGain=gainDelay[dryCursor];gainDelay[dryCursor]=smoothedGain;
            double dryL=dry[0][dryCursor],dryR=dry[1][dryCursor];dry[0][dryCursor]=(float)left[i];dry[1][dryCursor]=(float)right[i];dryCursor=(dryCursor+1)%delay;
            outLeft[i]=(dryL*(1-wet)+output[0][cursor]*wet)*appliedGain;outRight[i]=(dryR*(1-wet)+output[1][cursor]*wet)*appliedGain;
            pitchDelay[pitchCursor]=shift;pitchCursor=(pitchCursor+1)%pitchDelay.size();
            if(++cursor==block){
                engine.setPitchScale(std::exp2(pitchDelay[pitchCursor]/12));
                const float *in[]={input[0].data(),input[1].data()};float *out[]={output[0].data(),output[1].data()};
                engine.shift(in,out);cursor=0;
            }
        }
    }
};
}
