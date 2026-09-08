#include "pitch_gestures.hpp"
#include <cassert>
int main(){
    using pitch::dragPitchOffset;
    for(double detected:{40.13,57.923,69.42})for(double initial:{0.,1.78,-.16})for(double dy:{-900.,-25.,-1.,1.,25.,900.}){
        double shift=dragPitchOffset(detected,initial,dy,12,false);
        assert(std::abs(detected+shift-std::round(detected+shift))<1e-10);
        assert(shift>=-24&&shift<=24);
    }
    assert(std::abs(dragPitchOffset(57.923,0,24,12,false)-(60-57.923))<1e-10);
    assert(std::abs(dragPitchOffset(57.923,1.78,7,12,true)-1.85)<1e-10);
    assert(dragPitchOffset(60,.37,0,12,true)==.37);
    assert(std::abs(dragPitchOffset(57.923,.22,3,12,false,false)-.47)<1e-10);
    assert(dragPitchOffset(60,.37,0,12,false,false)==.37);
    assert(std::abs(dragPitchOffset(57.923,.22,3,12,true,false)-.25)<1e-10);
}
