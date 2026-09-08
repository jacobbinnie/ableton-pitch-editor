#pragma once
#include <algorithm>
#include <cmath>
#include <optional>
#include <vector>
namespace pitch {
struct WarpPoint { double beat, seconds; };
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
