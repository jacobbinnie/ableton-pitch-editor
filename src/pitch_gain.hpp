#pragma once
#include "pitch_core.hpp"
#include <algorithm>
#include <cmath>
namespace pitch {
// Source-time envelope shared by playback and waveform display. Equal-gain
// split regions share outer ramps so segmentation alone cannot change volume.
inline double gainAtTime(const std::vector<Note>& notes,double time) {
    for(std::size_t i=0;i<notes.size();++i){
        const auto& n=notes[i];if(time<n.start||time>=n.end)continue;
        double begin=n.start,end=n.end;
        for(std::size_t j=i;j>0;--j){const auto& p=notes[j-1];if(std::abs(p.end-begin)>1e-6||p.gainDb!=n.gainDb)break;begin=p.start;}
        for(std::size_t j=i+1;j<notes.size();++j){const auto& p=notes[j];if(std::abs(p.start-end)>1e-6||p.gainDb!=n.gainDb)break;end=p.end;}
        double ramp=std::min(.005,(end-begin)*.5);
        if(ramp<=0)return 1;
        double w=std::clamp(std::min(time-begin,end-time)/ramp,0.,1.);
        return std::pow(10.,n.gainDb*w*w*(3-2*w)/20.);
    }
    return 1;
}
}
