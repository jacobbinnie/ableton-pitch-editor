#pragma once
#include "pitch_core.hpp"
#include <algorithm>
#include <cmath>

namespace pitch {
struct ExpressionPoint { double time=0, correction=0; };
using ExpressionCurve=std::vector<ExpressionPoint>;
// Compile on the control thread, never in an audio callback. Local linear
// regression separates the slow trend from faster variation. This is a
// conservative variation reducer, not a semantic vibrato detector.
inline ExpressionCurve expressionCurve(const std::vector<Frame>& frames,const std::vector<Note>& notes) {
    if(std::none_of(notes.begin(),notes.end(),[](const Note& n){return n.vibrato!=1||n.driftStart!=0||n.driftEnd!=0;}))return {};
    ExpressionCurve curve;curve.reserve(frames.size());
    for(const auto& f:frames)curve.push_back({f.time,0});
    for(const auto& note:notes){
        if(note.vibrato==1&&note.driftStart==0&&note.driftEnd==0)continue;
        auto first=std::lower_bound(frames.begin(),frames.end(),note.start,[](const Frame& f,double t){return f.time<t;});
        std::size_t start=first-frames.begin();
        while(start<frames.size()&&frames[start].time<note.end){
            const auto reliable=[](const Frame& f){return f.voiced&&f.confidence>=.85&&std::isfinite(f.midi);};
            if(!reliable(frames[start])){++start;continue;}
            std::size_t end=start+1;
            while(end<frames.size()&&frames[end].time<note.end&&reliable(frames[end])&&frames[end].time-frames[end-1].time<=.025&&std::abs(frames[end].midi-frames[end-1].midi)<.7)++end;
            // Short fragments cannot establish a reliable vibrato/trend split.
            if(frames[end-1].time-frames[start].time>=.3){
                std::vector<double> residual(end-start),weight(end-start);
                double sum=0,total=0;
                for(std::size_t i=start;i<end;++i){
                    double sw=0,sx=0,sy=0,sxx=0,sxy=0;
                    auto lo=std::lower_bound(frames.begin()+start,frames.begin()+end,frames[i].time-.125,[](const Frame& f,double t){return f.time<t;});
                    for(auto j=lo;j!=frames.begin()+end&&j->time<=frames[i].time+.125;++j){
                        double x=j->time-frames[i].time,w=1-std::abs(x)/.125;
                        sw+=w;sx+=w*x;sy+=w*j->midi;sxx+=w*x*x;sxy+=w*x*j->midi;
                    }
                    double determinant=sw*sxx-sx*sx;
                    double trend=determinant>1e-12?(sy*sxx-sx*sxy)/determinant:frames[i].midi;
                    double r=frames[i].midi-trend;
                    double w=std::clamp(std::min(frames[i].time-frames[start].time,frames[end-1].time-frames[i].time)/.04,0.,1.);
                    w=w*w*(3-2*w);if(std::abs(r)>1)w=0;
                    residual[i-start]=r;weight[i-start]=w;sum+=r*w;total+=w;
                }
                double mean=total>0?sum/total:0;
                for(std::size_t i=start;i<end;++i){
                    double u=std::clamp((frames[i].time-note.start)/(note.end-note.start),0.,1.);
                    double drift=(note.driftStart*std::max(0.,1-2*u)+note.driftEnd*std::max(0.,2*u-1))/100.;
                    curve[i].correction=((note.vibrato-1)*(residual[i-start]-mean)+drift)*weight[i-start];
                }
            }
            start=end;
        }
    }
    if(std::all_of(curve.begin(),curve.end(),[](const ExpressionPoint& p){return std::abs(p.correction)<1e-9;}))return {};
    return curve;
}
inline double expressionAt(const ExpressionCurve& curve,double time) {
    if(curve.empty()||time<curve.front().time||time>curve.back().time)return 0;
    auto right=std::lower_bound(curve.begin(),curve.end(),time,[](const ExpressionPoint& p,double t){return p.time<t;});
    if(right==curve.begin())return right->correction;
    auto left=right-1;double span=right->time-left->time;
    if(span<=0||span>.025)return 0;
    double w=(time-left->time)/span;return left->correction+(right->correction-left->correction)*w;
}
}
