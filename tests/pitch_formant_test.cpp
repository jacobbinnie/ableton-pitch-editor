#include "pitch_audition.hpp"
#include <iostream>
#include <stdexcept>
static void require(bool ok,const char* message){if(!ok)throw std::runtime_error(message);}
static double envelopeCenter(const std::vector<float>& audio,double rate,double fundamental){
    std::size_t begin=(std::size_t)rate,count=8192;double sum=0,weighted=0;
    for(double hz=fundamental;hz<2200;hz+=fundamental){
        if(hz<400)continue;double re=0,im=0;
        for(std::size_t i=0;i<count;++i){double phase=2*M_PI*hz*i/rate,w=.5-.5*std::cos(2*M_PI*i/(count-1));re+=audio[begin+i]*w*std::cos(phase);im+=audio[begin+i]*w*std::sin(phase);}
        double power=re*re+im*im;sum+=power;weighted+=hz*power;
    }
    require(sum>1e-6,"formant output silent");return weighted/sum;
}
static void checkPeriod(const std::vector<float>& audio,double rate,double fundamental){
    double best=0;int center=(int)std::round(rate/fundamental);
    for(int lag=center-2;lag<=center+2;++lag){double xy=0,xx=0,yy=0;
        for(int i=(int)rate;i<(int)rate+8192;++i){double x=audio[i],y=audio[i+lag];xy+=x*y;xx+=x*x;yy+=y*y;}
        best=std::max(best,xy/std::sqrt(xx*yy));
    }
    require(best>.98,"formant control changed fundamental period");
}
int main(){try{
    pitch::Analysis a;a.duration=2;a.notes={{0,0,2,60,0}};pitch::Document doc(a);
    require(!doc.setFormant(0,NAN)&&!doc.setFormant(0,6.1)&&!doc.setFormant(99,1),"invalid formant");
    require(doc.setFormant(0,3)&&doc.split(0,1)&&doc.analysis().notes[1].formant==3&&doc.canJoinNext(0),"split lost formant");
    require(doc.setFormant(doc.analysis().notes[1].id,-2)&&!doc.canJoinNext(0)&&doc.undo()&&doc.joinNext(0),"join overwrites formant");
    require(doc.undo()&&doc.undo()&&doc.undo()&&doc.analysis().notes[0].formant==0&&doc.redo(),"formant history");
    pitch::StreamState state;state.enabled=true;state.start=4;state.end=8;state.marker=1;state.warp={{0,0},{8,4}};state.notes={{0,.5,1.5,60,0,0,1,0,0,3}};
    require(state.formantAt(3)==0&&state.formantAt(4.5)==3,"formant clip mapping");
    auto split=state;split.notes[0].end=1;auto right=state.notes[0];right.id=1;right.start=1;split.notes.push_back(right);
    for(int i=0;i<9000;++i)require(std::abs(state.formantAt(i*.001)-split.formantAt(i*.001))<1e-12,"split changes tone envelope");
    for(double rate:{44100.,48000.})for(double pitch:{0.,3.}){
        auto source=std::make_shared<pitch::AudioAsset>();source->sampleRate=rate;source->channels.resize(1);source->channels[0].resize((std::size_t)(3*rate));
        for(std::size_t i=0;i<source->frames();++i){double t=i/rate,v=.002*std::sin(2*M_PI*100*t);for(int h=1;h<=40;++h){double hz=100*h;v+=.02*std::exp(-.5*std::pow((hz-1000)/160,2))*std::sin(2*M_PI*hz*t);}source->channels[0][i]=v;}
        double centers[3];int k=0;
        for(double formant:{-3.,0.,3.}){
            pitch::Note note{0,0,3,43,pitch,0,1,0,0,formant};pitch::AuditionRuntime runtime(source,note,{});
            std::vector<float> out(source->frames()),rightAudio(out.size());
            for(std::size_t i=0;i<out.size();i+=127)runtime.render(out.data()+i,rightAudio.data()+i,std::min<std::size_t>(127,out.size()-i));
            for(std::size_t i=0;i<out.size();++i)require(std::isfinite(out[i])&&out[i]==rightAudio[i],"invalid or unlinked stereo output");
            double fundamental=100*std::exp2(pitch/12);checkPeriod(out,rate,fundamental);
            centers[k++]=envelopeCenter(out,rate,fundamental);
            std::cout<<rate<<" pitch="<<pitch<<" formant="<<formant<<" envelope="<<centers[k-1]<<" Hz\n";
        }
        require(std::abs(centers[1]-1000)<120,"neutral formant fails pitch compensation");
        require(centers[0]<centers[1]*.93&&centers[2]>centers[1]*1.07,"formant shift direction or amount wrong");
    }
    std::cout<<"PASS: formant envelope moves independently of pitch, stereo, segmentation, validation and history\n";
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
