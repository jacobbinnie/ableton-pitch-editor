#include "pitch_core.hpp"
#include <algorithm>
#include <cmath>
#include <functional>
#include <iostream>
#include <random>
#include <string>
#include <vector>

struct TruthNote { double start,end,midi; };
struct Fixture {
    std::string name;
    std::vector<TruthNote> notes;
    bool harmonics=false,missingFundamental=false,vibrato=false,noise=false;
    bool slide=false,softOnsets=false;
};
static double pitchAt(const Fixture& f,double t,const TruthNote& n) {
    return n.midi+(f.vibrato?.3*std::sin(2*M_PI*5*t):0)+(f.slide?2*(t-n.start)/(n.end-n.start):0);
}
int main() {
    const std::vector<Fixture> fixtures={
        {"steady",{{.1,.9,57}}},
        {"harmonics",{{.1,.9,57}},true},
        {"missing_fundamental",{{.1,.9,57}},true,true},
        {"vibrato",{{.1,.9,69}},true,false,true},
        {"legato",{{.1,.5,57},{.5,.9,59}},true},
        {"octave_jump",{{.1,.5,57},{.5,.9,69}},true},
        {"repeated_syllables",{{.1,.35,57},{.38,.63,57},{.66,.91,57}},true,false,false,false,false,true},
        {"short_notes",{{.1,.19,60},{.22,.31,62},{.34,.43,64},{.46,.55,65}},true},
        {"slide",{{.1,.9,57}},true,false,false,false,true},
        {"low_voice",{{.1,.9,40}},true},
        {"high_voice",{{.1,.9,81}},true},
        {"noise",{},false,false,false,true},
        {"silence",{}}
    };
    std::cout<<"{\"schema\":1,\"kind\":\"synthetic detector benchmark\",\"cases\":[\n";
    bool first=true;
    for(double rate:{22050.,44100.,48000.})for(const auto& f:fixtures){
        std::vector<float> audio((std::size_t)(rate*1.05));
        std::mt19937 rng(1729);std::uniform_real_distribution<double> random(-.2,.2);
        double phase=0;
        for(std::size_t i=0;i<audio.size();++i){
            double t=i/rate;if(f.noise){audio[i]=(float)random(rng);continue;}
            for(const auto& n:f.notes)if(t>=n.start&&t<n.end){
                double midi=pitchAt(f,t,n);phase+=2*M_PI*440*std::exp2((midi-69)/12)/rate;
                double edge=f.softOnsets?.025:.005;
                double envelope=std::clamp(std::min(t-n.start,n.end-t)/edge,0.,1.);
                audio[i]=(float)(envelope*((f.missingFundamental?0:.2)*std::sin(phase)+(f.harmonics?.3*std::sin(2*phase)+.12*std::sin(3*phase):0)));
                break;
            }
        }
        auto analysis=pitch::analyze(audio,rate);
        int voicedTruth=0,voicedDetected=0,trueVoiced=0,octaves=0;
        std::vector<double> errors,onsets,offsets;
        for(const auto& frame:analysis.frames){
            const TruthNote* truth=nullptr;
            for(const auto& n:f.notes)if(frame.time>=n.start&&frame.time<n.end){truth=&n;break;}
            if(truth)++voicedTruth;if(frame.voiced)++voicedDetected;
            if(truth&&frame.voiced){
                ++trueVoiced;double cents=std::abs(frame.midi-pitchAt(f,frame.time,*truth))*100;
                errors.push_back(cents);if(std::abs(cents-1200)<50||std::abs(cents-2400)<50)++octaves;
            }
        }
        // Chronological one-to-one matching: a detected region cannot satisfy two truth notes.
        std::vector<bool> used(analysis.notes.size());int matched=0;
        for(const auto& n:f.notes){
            std::size_t best=analysis.notes.size();double distance=1e9;
            for(std::size_t i=0;i<analysis.notes.size();++i){const auto& d=analysis.notes[i];
                double onset=std::abs(d.start-n.start),offset=std::abs(d.end-n.end);
                if(!used[i]&&onset<=.05&&offset<=.08&&std::abs(d.originalMidi-pitchAt(f,(n.start+n.end)/2,n))<=.5&&onset+offset<distance){best=i;distance=onset+offset;}}
            if(best<used.size()){used[best]=true;++matched;onsets.push_back(std::abs(analysis.notes[best].start-n.start)*1000);offsets.push_back(std::abs(analysis.notes[best].end-n.end)*1000);}
        }
        auto p95=[](std::vector<double> values){if(values.empty())return -1.;std::sort(values.begin(),values.end());return values[(std::size_t)std::ceil(.95*values.size())-1];};
        if(!first)std::cout<<",\n";first=false;
        std::cout<<"{\"name\":\""<<f.name<<"\",\"sample_rate\":"<<rate
            <<",\"truth_notes\":"<<f.notes.size()<<",\"detected_notes\":"<<analysis.notes.size()<<",\"matched_notes\":"<<matched
            <<",\"truth_voiced_frames\":"<<voicedTruth<<",\"detected_voiced_frames\":"<<voicedDetected<<",\"correct_voiced_frames\":"<<trueVoiced
            <<",\"octave_error_frames\":"<<octaves<<",\"pitch_p95_cents\":"<<p95(errors)
            <<",\"matched_onset_p95_ms\":"<<p95(onsets)<<",\"matched_offset_p95_ms\":"<<p95(offsets)<<"}";
    }
    std::cout<<"\n]}\n";
}
