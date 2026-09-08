#include "pitch_stream.hpp"
#include <iostream>
#include <stdexcept>
static void require(bool ok,const char* m){if(!ok)throw std::runtime_error(m);}
static double hz(const std::vector<double>& v,double rate,double t){
    std::size_t start=(std::size_t)(rate*t);double best=-1;int result=1;
    for(int lag=(int)(rate/300);lag<(int)(rate/180);++lag){double a=0,b=0,c=0;for(int i=0;i<1024;++i){double x=v[start+i],y=v[start+i+lag];a+=x*y;b+=x*x;c+=y*y;}double value=a/std::sqrt(b*c);if(value>best){best=value;result=lag;}}
    return rate/result;
}
int main(){try{
    pitch::StreamState state;state.enabled=true;state.start=4;state.end=8;state.marker=1;state.warp={{0,0},{8,4}};state.notes={{0,.5,1.5,57,2}};
    require(state.shiftAt(3)==0&&state.shiftAt(8)==0,"clip bounds");require(std::abs(state.shiftAt(4.5)-2)<1e-9,"crop/warp mapping");state.loop=true;state.loopStart=1;state.loopEnd=3;require(state.shiftAt(6.5)==2,"loop mapping");
    auto splitState=state;splitState.notes={{0,.5,1,57,2},{1,1,1.5,58,2}};
    for(int i=0;i<9000;++i)require(std::abs(state.shiftAt(i*.001)-splitState.shiftAt(i*.001))<1e-12,"split changes pitch curve");
    auto removed=state;removed.notes.clear();require(removed.shiftAt(4.5)==0,"removed region still corrected");
    auto shortened=state;shortened.notes[0].end=.7;require(shortened.shiftAt(4.5)==0,"shrunken region still corrected");
    auto gained=state;gained.notes[0].gainDb=-6;
    require(std::abs(gained.gainAt(4.5)-std::pow(10.,-.3))<1e-12,"gain warp mapping");
    auto gainSplit=gained;gainSplit.notes={{0,.5,1,57,2,-6},{1,1,1.5,58,2,-6}};
    for(int i=0;i<9000;++i)require(std::abs(gained.gainAt(i*.001)-gainSplit.gainAt(i*.001))<1e-12,"split changes gain envelope");
    require(gained.gainAt(3)==1,"gain outside clip");
    pitch::Analysis model;model.duration=1;model.notes={{0,0,1,60,0}};pitch::Document doc(model);
    require(!doc.setGain(0,NAN)&&!doc.setGain(0,13)&&!doc.setGain(0,-25)&&!doc.setGain(99,1),"invalid gain accepted");
    require(doc.setGain(0,-6)&&doc.split(0,.5)&&doc.analysis().notes[1].gainDb==-6,"split lost gain");
    require(doc.setGain(doc.analysis().notes[1].id,3)&&!doc.canJoinNext(0),"join overwrites gain");
    require(doc.undo()&&doc.canJoinNext(0)&&doc.undo()&&doc.undo()&&doc.analysis().notes[0].gainDb==0&&doc.redo()&&doc.analysis().notes[0].gainDb==-6,"gain history");
    for(double rate:{44100.,48000.}){
        pitch::StreamShifter gainEngine(rate);std::size_t count=(std::size_t)rate+gainEngine.delay;
        std::vector<double> input(count,.1),out(count),right(count);
        for(std::size_t i=0;i<count;i+=64)gainEngine.process(input.data()+i,input.data()+i,out.data()+i,right.data()+i,std::min<std::size_t>(64,count-i),0,i<rate*.5?.5:2);
        require(std::abs(out[gainEngine.delay+(std::size_t)(rate*.3)]-.05)<1e-7,"gain attenuation");
        require(std::abs(out[gainEngine.delay+(std::size_t)(rate*.8)]-.2)<1e-7,"gain boost");
        for(std::size_t i=gainEngine.delay+1;i<count;++i){require(out[i]==right[i],"gain stereo mismatch");require(std::abs(out[i]-out[i-1])<.001,"gain discontinuity");}
    }
    for(double rate:{44100.,48000.})for(double target:{2.,.5,-.35}){
        pitch::StreamShifter engine(rate);std::size_t count=(std::size_t)(rate*2.5)+engine.delay;
        std::vector<double> input(count),output(count),right(count);
        for(std::size_t i=0;i<count;++i)input[i]=.15*std::sin(2*M_PI*220*i/rate);
        for(std::size_t i=0;i<count;i+=64){double t=i/rate;double shift=t>=.5&&t<1.5?target:0;engine.process(input.data()+i,input.data()+i,output.data()+i,right.data()+i,std::min<std::size_t>(64,count-i),shift);}
        output.erase(output.begin(),output.begin()+engine.delay);
        for(double t:{.35,.7,1.25,1.75}){double shift=12*std::log2(hz(output,rate,t)/220);std::cout<<rate<<" t="<<t<<" shift="<<shift<<"\n";require(std::abs(shift-(t>.5&&t<1.5?target:0))<.12,"stream pitch");}
        pitch::StreamShifter bypass(rate);std::vector<double> dry(count);
        for(std::size_t i=0;i<count;i+=64)bypass.process(input.data()+i,input.data()+i,dry.data()+i,right.data()+i,std::min<std::size_t>(64,count-i),0);
        for(std::size_t i=engine.delay;i<count;++i)require(std::abs(dry[i]-input[i-engine.delay])<1e-7,"delay matched bypass");
    }
    std::cout<<"PASS: stream mapping, pitch shift, fixed latency and bypass\n";
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
