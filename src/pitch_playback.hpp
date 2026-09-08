#pragma once
#include <algorithm>
#include <cmath>
#include <optional>
#include <vector>
namespace pitch {
struct WarpPoint { double beat, seconds; };
inline std::optional<double> sourceBeat(double seconds,const std::vector<WarpPoint>& points){
 if(!std::isfinite(seconds)||points.size()<2)return {};
 for(std::size_t i=0;i<points.size();++i){const auto& p=points[i];if(!std::isfinite(p.beat)||!std::isfinite(p.seconds)||(i&&(p.beat<=points[i-1].beat||p.seconds<=points[i-1].seconds)))return {};}
 auto hi=std::upper_bound(points.begin(),points.end(),seconds,[](double t,const WarpPoint& p){return t<p.seconds;});
 std::size_t i=hi==points.begin()?0:hi==points.end()?points.size()-2:std::size_t(hi-points.begin()-1);
 const auto& a=points[i];const auto& b=points[i+1];
 return a.beat+(seconds-a.seconds)/(b.seconds-a.seconds)*(b.beat-a.beat);
}
inline std::optional<double> seekBeat(double seconds,const std::vector<WarpPoint>& points,double start,double end,double marker,bool loop,double loopStart,double loopEnd,double current){
 auto beat=sourceBeat(seconds,points);if(!beat||!std::isfinite(start)||!std::isfinite(end)||!std::isfinite(marker)||!std::isfinite(current)||end<=start)return {};
 double target=start+*beat-marker;
 if(loop){
  if(!std::isfinite(loopStart)||!std::isfinite(loopEnd)||loopEnd<=loopStart)return {};
  if(*beat>=loopStart&&*beat<loopEnd){
   double length=loopEnd-loopStart;
   double first=std::max(0.,std::ceil((start-target)/length));
   double last=std::ceil((end-target)/length)-1;
   if(last<first)return {};
   target+=std::clamp(std::round((current-target)/length),first,last)*length;
  }else if(*beat>=loopEnd)return {};
 }
 if(target<start||target>=end||target<0)return {};
 return target;
}
inline std::optional<double> sourceTime(double position,bool warped,const std::vector<WarpPoint>& points){
 if(!std::isfinite(position))return {};
 if(!warped)return position;
 if(points.size()<2)return {};
 auto hi=std::upper_bound(points.begin(),points.end(),position,[](double b,const WarpPoint& p){return b<p.beat;});
 size_t i=hi==points.begin()?0:hi==points.end()?points.size()-2:size_t(hi-points.begin()-1);
 const auto &a=points[i],&b=points[i+1];
 if(!std::isfinite(a.beat)||!std::isfinite(b.beat)||!std::isfinite(a.seconds)||!std::isfinite(b.seconds)||b.beat<=a.beat||b.seconds<=a.seconds)return {};
 return a.seconds+(position-a.beat)/(b.beat-a.beat)*(b.seconds-a.seconds);
}
}
