#include "pitch_expression.hpp"
#include <iostream>
#include <stdexcept>
static void require(bool ok,const char* message){if(!ok)throw std::runtime_error(message);}
int main(){try{
    std::vector<pitch::Frame> frames;
    for(int i=0;i<=300;++i){double t=i*.01;frames.push_back({t,60+.2*t+.4*std::sin(2*M_PI*6*t),.99,true});}
    std::vector<pitch::Note> notes={{0,0,3.01,60,0,0,1}};
    require(pitch::expressionCurve(frames,notes).empty(),"neutral changes contour");
    notes[0].vibrato=0;auto reduced=pitch::expressionCurve(frames,notes);double sum=0,originalPower=0,reducedPower=0;
    for(std::size_t i=0;i<frames.size();++i){sum+=reduced[i].correction;double t=frames[i].time;if(t>.3&&t<2.7){double r=frames[i].midi-60-.2*t;originalPower+=r*r;reducedPower+=std::pow(r+reduced[i].correction,2);}}
    require(std::abs(sum)<1e-9,"variation reduction moves mean pitch");require(reducedPower<originalPower*.08,"vibrato not reduced");
    notes[0].vibrato=.5;auto half=pitch::expressionCurve(frames,notes);
    for(std::size_t i=0;i<frames.size();++i)require(std::abs(half[i].correction-.5*reduced[i].correction)<1e-9,"amount not proportional");
    for(auto& f:frames)f.midi=60+.8*f.time;
    require(pitch::expressionCurve(frames,notes).empty(),"linear drift changed");
    for(auto& f:frames){f.voiced=false;f.midi=NAN;}
    require(pitch::expressionCurve(frames,notes).empty(),"unvoiced changed");
    for(auto& f:frames){f.voiced=true;f.midi=60+.4*std::sin(2*M_PI*6*f.time);f.confidence=.4;}
    require(pitch::expressionCurve(frames,notes).empty(),"uncertain pitch changed");
    for(auto& f:frames)f.confidence=.99;
    notes[0].end=.2;require(pitch::expressionCurve(frames,notes).empty(),"short note changed");notes[0].end=3.01;
    for(auto& f:frames)if(f.time>=1&&f.time<=1.1)f.voiced=false;
    auto gaps=pitch::expressionCurve(frames,notes);
    require(pitch::expressionAt(gaps,1.05)==0,"voicing gap bridged");
    require(pitch::expressionAt(gaps,-1)==0&&pitch::expressionAt(gaps,4)==0,"outside curve changed");
    pitch::Analysis analysis;analysis.duration=3.01;analysis.notes=notes;pitch::Document doc(analysis);
    require(!doc.setVibrato(0,NAN)&&!doc.setVibrato(0,-.1)&&!doc.setVibrato(0,1.1)&&!doc.setVibrato(9,.5),"invalid amount");
    require(doc.setVibrato(0,.2)&&doc.split(0,1.5)&&doc.analysis().notes[1].vibrato==.2,"split lost vibrato");
    require(doc.setVibrato(doc.analysis().notes[1].id,.8)&&!doc.canJoinNext(0),"join overwrites vibrato");
    require(doc.undo()&&doc.canJoinNext(0)&&doc.undo()&&doc.undo()&&doc.analysis().notes[0].vibrato==.5&&doc.redo(),"vibrato history");
    std::vector<pitch::Frame> drifting;
    for(int i=0;i<=300;++i){double t=i*.01;drifting.push_back({t,60+.4*(t-1.5)+.3*std::sin(2*M_PI*6*t),.99,true});}
    std::vector<pitch::Note> driftNotes={{0,0,3,60,0,0,1,60,-60}};
    auto corrected=pitch::expressionCurve(drifting,driftNotes);
    for(int i=10;i<290;++i)require(std::abs(drifting[i].midi+pitch::expressionAt(corrected,i*.01)-(60+.3*std::sin(2*M_PI*6*i*.01)))<1e-9,"drift correction alters vibrato");
    driftNotes[0].driftEnd=0;auto beginning=pitch::expressionCurve(drifting,driftNotes);
    require(pitch::expressionAt(beginning,2)==0&&pitch::expressionAt(beginning,.5)>.3,"start drift affects wrong half");
    require(pitch::expressionAt(beginning,1.5)==0,"drift moved midpoint");
    driftNotes[0].vibrato=0;auto combined=pitch::expressionCurve(drifting,driftNotes);
    driftNotes[0].driftStart=0;auto vibratoOnly=pitch::expressionCurve(drifting,driftNotes);
    for(int i=0;i<300;++i)require(std::abs(pitch::expressionAt(combined,i*.01)-pitch::expressionAt(beginning,i*.01)-pitch::expressionAt(vibratoOnly,i*.01))<1e-9,"drift/vibrato composition");
    pitch::Analysis d;d.duration=3;d.notes={{9,0,3,60,0}};pitch::Document driftDoc(d);
    require(!driftDoc.setDrift(9,NAN,0)&&!driftDoc.setDrift(9,0,201)&&!driftDoc.setDrift(8,10,10),"invalid drift accepted");
    require(driftDoc.setDrift(9,60,-60)&&!driftDoc.split(9,1.5),"split silently reinterprets drift");
    require(driftDoc.undo()&&driftDoc.analysis().notes[0].driftStart==0&&driftDoc.redo()&&driftDoc.analysis().notes[0].driftEnd==-60,"drift history");
    std::cout<<"PASS: variation attenuation, mean preservation, linear drift, voicing/confidence/short-note gates, amount and history\n";
}catch(const std::exception& e){std::cerr<<e.what()<<"\n";return 1;}}
