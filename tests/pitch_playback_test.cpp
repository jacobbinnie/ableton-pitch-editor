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
}
