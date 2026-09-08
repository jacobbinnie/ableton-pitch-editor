#pragma once
#include <algorithm>
#include <cmath>

namespace pitch {
// Coarse drag targets absolute equal-tempered pitch rows. Fine drag preserves
// the gesture's starting offset and adjusts it by cents per screen point.
inline double dragPitchOffset(double detected,double initial,double upwardPoints,double rowHeight,bool fine,bool snap=true){
    if(!std::isfinite(detected)||!std::isfinite(initial)||!std::isfinite(upwardPoints)||!std::isfinite(rowHeight)||rowHeight<=0)return initial;
    if(fine)return std::clamp(initial+std::round(upwardPoints)/100.,-24.,24.);
    if(!snap)return std::clamp(initial+upwardPoints/rowHeight,-24.,24.);
    double target=std::round(detected+initial+upwardPoints/rowHeight);
    // Keep the destination on a grid row even at the supported shift limits.
    target=std::clamp(target,std::ceil(detected-24),std::floor(detected+24));
    return target-detected;
}
}
