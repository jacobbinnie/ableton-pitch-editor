#pragma once
#include <algorithm>
#include <cmath>
namespace pitch {
struct Viewport {
    double duration=1, start=0, span=1, top=84, rows=37;
    void clamp() {
        duration=std::max(.001,duration);
        span=std::clamp(span,std::min(.05,duration),duration);
        start=std::clamp(start,0.0,duration-span);
        rows=std::clamp(rows,4.0,128.0);
        top=std::clamp(top,rows-1,127.0);
    }
    void fit(double seconds,double low,double high) {
        duration=seconds;start=0;span=seconds;rows=high-low+1;top=high;clamp();
    }
    void zoom(double factor,double anchor,bool vertical=false) {
        if(!std::isfinite(factor)||factor<=0)return;
        anchor=std::clamp(anchor,0.0,1.0);
        if(vertical){double pitch=top-anchor*rows;rows=std::clamp(rows/factor,4.0,128.0);top=pitch+anchor*rows;}
        else {double time=start+anchor*span;span=std::clamp(span/factor,std::min(.05,duration),duration);start=time-anchor*span;}
        clamp();
    }
    void pan(double time,double semitones){start+=time;top+=semitones;clamp();}
};
}
