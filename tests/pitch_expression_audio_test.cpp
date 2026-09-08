#include "pitch_audition.hpp"
#include <iostream>
#include <stdexcept>
static void require(bool ok,const char *message){if(!ok)throw std::runtime_error(message);}
// Independent F0 measurement from interpolated positive zero crossings.
// Fit both quadratures so a processor phase lag does not masquerade as reduction.
static double depth(const std::vector<float>& audio,double rate,double start,double end,double frequency,double& mean){
    double previous=-1,sinSum=0,cosSum=0,meanSum=0;int count=0;
    for(std::size_t i=1;i<audio.size();++i){
        if(audio[i-1]<=0&&audio[i]>0){
            double crossing=(i-1)+(-audio[i-1])/(audio[i]-audio[i-1]);
            if(previous>=0){double t=(crossing+previous)*.5/rate;
                if(t>start&&t<end){double midi=12*std::log2(rate/(crossing-previous)/220);meanSum+=midi;sinSum+=midi*std::sin(2*M_PI*frequency*t);cosSum+=midi*std::cos(2*M_PI*frequency*t);++count;}}
            previous=crossing;
        }
    }
    require(count>100,"insufficient rendered voiced cycles");mean=meanSum/count;return 2*std::hypot(sinSum,cosSum)/count;
}
int main(){try{
    for(double rate:{44100.,48000.})for(double frequency:{4.,6.,8.}){
        auto source=std::make_shared<pitch::AudioAsset>();source->sampleRate=rate;source->channels.resize(1);source->channels[0].resize((std::size_t)(3*rate));
        double phase=0;for(std::size_t i=0;i<source->frames();++i){double t=i/rate;phase+=2*M_PI*220*std::exp2(.4*std::sin(2*M_PI*frequency*t)/12)/rate;source->channels[0][i]=.1*std::sin(phase);}
        // Include a production-detector path as well as an oracle curve, but
        // measure output independently using crossings, not that detector.
        auto detected=pitch::analyze(source->channels[0],rate);
        std::vector<pitch::Frame> truth;for(int i=0;i<300;++i){double t=i*.01;truth.push_back({t,57+.4*std::sin(2*M_PI*frequency*t),.99,true});}
        double baseline=0,baselineMean=0;
        for(int mode=0;mode<3;++mode){
            pitch::Note note{0,0,3,57,0,-6,mode==0?1.:0.};
            pitch::AuditionRuntime runtime(source,note,mode==2?detected.frames:truth);
            std::vector<float> out((std::size_t)(rate*3.5)),right(out.size());
            for(std::size_t i=0;i<out.size();i+=127)runtime.render(out.data()+i,right.data()+i,std::min<std::size_t>(127,out.size()-i));
            double mean=0;double amount=depth(out,rate,.5,2.5,frequency,mean);
            for(std::size_t i=0;i<out.size();++i)require(std::isfinite(out[i])&&out[i]==right[i],"audition invalid/stereo mismatch");
            if(mode==0){baseline=amount;baselineMean=mean;}else {require(amount<baseline*.75,"rendered vibrato not reduced sufficiently");require(std::abs(mean-baselineMean)<.05,"rendered pitch center moved");}
            std::cout<<rate<<" frequency="<<frequency<<" mode="<<mode<<" output vibrato="<<amount<<" semitones\n";
            note.gainDb=0;runtime.publish(note,truth);runtime.render(out.data(),right.data(),127);
        }
    }
    for(double rate:{44100.,48000.}){
        auto source=std::make_shared<pitch::AudioAsset>();source->sampleRate=rate;source->channels.resize(1);source->channels[0].resize((std::size_t)(3*rate));
        double phase=0;for(std::size_t i=0;i<source->frames();++i){double t=i/rate;phase+=2*M_PI*220*std::exp2((.4*(t-1.5)+.3*std::sin(2*M_PI*6*t))/12)/rate;source->channels[0][i]=.1*std::sin(phase);}
        std::vector<pitch::Frame> frames;for(int i=0;i<300;++i){double t=i*.01;frames.push_back({t,57+.4*(t-1.5)+.3*std::sin(2*M_PI*6*t),.99,true});}
        for(bool correct:{false,true}){
            pitch::Note note{0,0,3,57,0,0,1,correct?60.:0.,correct?-60.:0.};pitch::AuditionRuntime runtime(source,note,frames);
            std::vector<float> out((std::size_t)(rate*3.2)),right(out.size());
            for(std::size_t i=0;i<out.size();i+=127)runtime.render(out.data()+i,right.data()+i,std::min<std::size_t>(127,out.size()-i));
            double early=0,late=0,mean=0;depth(out,rate,.6,1.1,6,early);depth(out,rate,2.1,2.6,6,late);
            double vibrato=depth(out,rate,.6,2.6,6,mean);
            require(correct?std::abs(late-early)<.15:late-early>.45,"rendered drift slope");
            require(vibrato>.22&&vibrato<.38,"drift flattened or amplified vibrato");
            std::cout<<rate<<" drift corrected="<<correct<<" late-early="<<late-early<<" vibrato="<<vibrato<<"\n";
        }
    }
    std::cout<<"PASS: shared audition/playback DSP reduces measured vibrato using oracle and detected curves\n";
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
