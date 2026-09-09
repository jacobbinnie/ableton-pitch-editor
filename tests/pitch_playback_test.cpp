#include "pitch_playback.hpp"
#include <cassert>
#include <cmath>
int main(){
 using namespace pitch;
 std::vector<WarpPoint> p={{0,1},{4,3},{8,7}};
 assert(*sourceTime(2,true,p)==2);assert(*sourceTime(6,true,p)==5);
 assert(*sourceTime(-2,true,p)==0);assert(*sourceTime(10,true,p)==9);
 assert(*sourceTime(4,true,p)==3);assert(*sourceTime(2.5,false,{})==2.5);
 assert(!sourceTime(1,true,{}));assert(!sourceTime(1,true,{{0,0},{0,1}}));
 assert(!sourceTime(NAN,false,{}));
 for(double beat:{-2.,0.,1.,4.,6.,10.})assert(std::abs(*sourceBeat(*sourceTime(beat,true,p),p)-beat)<1e-9);
 assert(!sourceBeat(2,{{0,0},{4,3},{8,2}}));assert(!sourceBeat(NAN,p));
 assert(*seekBeat(2,p,10,18,1,false,0,0,10)==11);
 assert(*seekBeat(0,p,10,18,1,false,0,0,10)==10);
 assert(*seekBeat(0,p,0,8,1,false,0,0,4)==0);
 assert(*seekBeat(0,p,10,18,1,true,2,4,12)==10); // cropped intro, not a repeated loop position
 assert(*seekBeat(1.75,p,10,18,1,false,0,0,10)==10.5); // valid silence remains seekable
 assert(!seekBeat(20,p,10,18,1,false,0,0,10)); // end is still exclusive
 assert(!seekBeat(NAN,p,10,18,1,false,0,0,10));
 assert(*seekBeat(2,p,10,24,1,true,0,4,20)==19);
 assert(*seekBeat(1,p,10,24,1,true,0,4,10)==13);
 assert(!seekBeat(4,p,10,24,1,true,0,4,10));
 assert(!seekBeat(2,p,10,10,1,false,0,0,10));
}
