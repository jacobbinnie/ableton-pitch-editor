#include "pitch_render.hpp"
#include <algorithm>
#include <cmath>
#include <iostream>
#include <stdexcept>
static void require(bool v,const char* message){if(!v)throw std::runtime_error(message);}
// Independent normalized autocorrelation, evaluated well inside stable regions.
static double frequency(const std::vector<float>& data,double sr,double start){
    std::size_t offset=(std::size_t)(start*sr), count=1024;double best=-2;int lagBest=0;
    for(int lag=(int)(sr/300);lag<(int)(sr/180);++lag){
        double ab=0,aa=0,bb=0;
        for(std::size_t i=0;i<count;++i){double a=data[offset+i],b=data[offset+i+lag];ab+=a*b;aa+=a*a;bb+=b*b;}
        double score=ab/std::sqrt(aa*bb);if(score>best){best=score;lagBest=lag;}
    }
    return sr/lagBest;
}
int main(){try{
    pitch::RubberBandRenderer renderer;
    for(double rate:{44100.,48000.})for(double shift:{2.,-2.,3.,-3.}){
        pitch::AudioAsset source;source.sampleRate=rate;source.channels.resize(2,std::vector<float>((std::size_t)(rate*2)));
        for(std::size_t i=0;i<source.frames();++i){source.channels[0][i]=.2*std::sin(2*3.141592653589793*220*i/rate);source.channels[1][i]=source.channels[0][i];}
        auto bypass=renderer.render(source,{});require(bypass.bypassed&&bypass.audio.channels==source.channels,"bypass must preserve PCM exactly");
        pitch::RenderPlan plan;plan.regions.push_back({(std::size_t)(.5*rate),(std::size_t)(1.5*rate),shift});
        require(pitch::semitonesAt(plan,.5*rate,rate)==0,"boundary ramp");
        require(pitch::semitonesAt(plan,rate,rate)==shift,"region shift");
        auto result=renderer.render(source,plan);require(result.audio.frames()==source.frames()&&result.audio.channels.size()==2,"duration/channel count");
        double hz=frequency(result.audio.channels[0],rate,.9), original=frequency(result.audio.channels[0],rate,.15);
        std::cout<<rate<<" Hz: shifted="<<hz<<", original="<<original<<", peak="<<result.peak<<"\n";
        require(std::abs(12*std::log2(hz/220)-shift)<.12,"incorrect shifted pitch");
        require(std::abs(12*std::log2(original/220))<.12,"unselected pitch changed");
        double stereoError=0,maxStep=0;
        for(std::size_t i=1;i<source.frames();++i){stereoError=std::max(stereoError,(double)std::abs(result.audio.channels[0][i]-result.audio.channels[1][i]));maxStep=std::max(maxStep,(double)std::abs(result.audio.channels[0][i]-result.audio.channels[0][i-1]));}
        require(stereoError<1e-5,"linked stereo mismatch");require(maxStep<.08,"large discontinuity");require(result.peak<1,"unexpected clipping");
        for(double time:{.43,.58,1.43,1.62}) {
            double measured=12*std::log2(frequency(result.audio.channels[0],rate,time)/220);
            double expected=(time>.5&&time<1.5)?shift:0;
            std::cout<<"time="<<time<<" shift="<<measured<<" expected="<<expected<<"\n";
            require(std::abs(measured-expected)<.15,"pitch change scheduled outside expected region");
        }
        pitch::AudioAsset impulses;impulses.sampleRate=rate;impulses.channels.resize(1,std::vector<float>(source.frames()));
        for(double time:{.2,1.8})impulses.channels[0][(std::size_t)(time*rate)]=.5;
        auto impulseRender=renderer.render(impulses,plan);
        for(double time:{.2,1.8}) {
            auto center=(std::size_t)(time*rate), radius=(std::size_t)(rate*.05);
            auto first=impulseRender.audio.channels[0].begin()+center-radius;
            auto peak=std::max_element(first,first+radius*2,[](float a,float b){return std::abs(a)<std::abs(b);});
            auto position=static_cast<std::size_t>(peak-impulseRender.audio.channels[0].begin());
            require(std::abs((double)position-center)<rate*.005,"transient alignment exceeds 5 ms");
        }
        auto bad=plan;bad.regions.push_back(plan.regions[0]);bool rejected=false;
        try{renderer.render(source,bad);}catch(const std::invalid_argument&){rejected=true;}require(rejected,"overlap accepted");
        bad=plan;bad.regions[0].semitones=NAN;rejected=false;
        try{renderer.render(source,bad);}catch(const std::invalid_argument&){rejected=true;}require(rejected,"NaN edit accepted");
    }
    pitch::AudioAsset shortSilence{44100, {std::vector<float>(64,0)}};
    pitch::RenderPlan shortPlan;shortPlan.regions.push_back({0,64,2});
    auto shortResult=renderer.render(shortSilence,shortPlan);
    require(shortResult.audio.frames()==64&&shortResult.peak==0,"short silent render tail");
    std::cout<<"PASS: renderer identity, pitch, timing length, stereo, transitions, invalid edits\n";
}catch(const std::exception& e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}}
