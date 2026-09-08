#include "pitch_viewport.hpp"
#include <cassert>
#include <cmath>
int main(){
 pitch::Viewport v;v.fit(10,48,84);
 double t=v.start+.3*v.span;v.zoom(4,.3);assert(std::abs(v.start+.3*v.span-t)<1e-9);
 double p=v.top-.4*v.rows;v.zoom(2,.4,true);assert(std::abs(v.top-.4*v.rows-p)<1e-9);
 v.pan(100,1000);assert(v.start==v.duration-v.span&&v.top==127);
 v.pan(-100,-1000);assert(v.start==0&&v.top==v.rows-1);
 v.zoom(1e9,.5);assert(v.span==.05);v.zoom(1e-9,.5);assert(v.span==10&&v.start==0);
 v.fit(.01,60,70);v.zoom(10,.5);assert(v.span==.01);v.zoom(0,.5);assert(v.span==.01);
 v.fit(10,48,84);assert(v.start==0&&v.span==10&&v.top==84&&v.rows==37);
}
