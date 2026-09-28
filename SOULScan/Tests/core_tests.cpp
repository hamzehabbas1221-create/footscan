#include "../Core/SoulCore.h"
#include <cassert>
#include <cmath>
#include <iostream>
#include <limits>
#include <random>
#include <vector>
SoulPoint transform(SoulPoint p,float theta,SoulPoint t){return {std::cos(theta)*p.x-std::sin(theta)*p.y+t.x,std::sin(theta)*p.x+std::cos(theta)*p.y+t.y,p.z+t.z};}
SoulPoint apply(SoulPose m,SoulPoint p){return {m.r[0]*p.x+m.r[1]*p.y+m.r[2]*p.z+m.t[0],m.r[3]*p.x+m.r[4]*p.y+m.r[5]*p.z+m.t[1],m.r[6]*p.x+m.r[7]*p.y+m.r[8]*p.z+m.t[2]};}
float distance(SoulPoint a,SoulPoint b){return std::sqrt(std::pow(a.x-b.x,2)+std::pow(a.y-b.y,2)+std::pow(a.z-b.z,2));}
int main(){
 std::mt19937 rng(42);std::uniform_real_distribution<float>u(-1,1);std::vector<SoulPoint>a,b;
 for(int i=0;i<7500;++i){float x=u(rng)*.13f,y=u(rng)*.06f;float z=-.35f+.012f*std::sin(x*80)+.012f*std::cos(y*50)+.007f*std::sin(x*25+y*75);a.push_back({x,y,z});b.push_back(transform(a.back(),.025f,{.004f,-.003f,.002f}));}
 SoulPose pose{};assert(soul_fit_rigid(a.data(),b.data(),int(a.size()),&pose));double error=0;for(size_t i=0;i<a.size();++i)error+=distance(apply(pose,a[i]),b[i]);assert(error/a.size()<.00001);std::cout<<"PASS known rigid transform (mean error "<<error/a.size()*1000<<" mm)\n";
 std::vector<SoulPoint>line(10);for(int i=0;i<10;++i)line[i]={float(i)*.01f,0,-.3f};assert(!soul_fit_rigid(line.data(),line.data(),10,&pose));std::cout<<"PASS collinear geometry rejected\n";
 SoulHandle h=soul_create();auto first=soul_add_frame(h,a.data(),int(a.size()));assert(first.status==1&&first.point_count>500);int count=first.point_count;
 auto stationary=soul_add_frame(h,a.data(),int(a.size()));assert(stationary.status==2);assert(soul_point_count(h)==count);std::cout<<"PASS stationary frames do not inflate model\n";
 auto second=soul_add_frame(h,b.data(),int(b.size()));assert(second.status==1);assert(second.rms_metres<.001);error=0;for(size_t i=0;i<a.size();++i)error+=distance(apply(second.pose,b[i]),a[i]);assert(error/a.size()<.001);std::cout<<"PASS ICP recovers shifted/rotated frame (mean error "<<error/a.size()*1000<<" mm)\n";
 count=soul_point_count(h);auto bad=b;for(auto&p:bad)p.z-=.4f;auto rejected=soul_add_frame(h,bad.data(),int(bad.size()));assert(rejected.status==0&&soul_point_count(h)==count);std::cout<<"PASS unrelated frame rejected without corrupting model\n";
 auto invalid=a;for(auto&p:invalid)p.x=std::numeric_limits<float>::quiet_NaN();assert(soul_add_frame(h,invalid.data(),int(invalid.size())).status==0);assert(soul_add_frame(h,nullptr,1000).status==0);std::cout<<"PASS invalid depth and null input rejected\n";
 std::vector<SoulPoint>copy(23);assert(soul_copy_points(h,copy.data(),23)==23);for(auto p:copy)assert(std::isfinite(p.z));assert(soul_copy_points(h,nullptr,23)==0);soul_reset(h);assert(soul_point_count(h)==0);assert(soul_add_frame(h,a.data(),int(a.size())).accepted_frames==1);std::cout<<"PASS bounded export and reset\n";
 std::normal_distribution<float>noise(0,.0007f);auto noisy=b;for(size_t i=0;i<noisy.size();++i){noisy[i].x+=noise(rng)*.2f;noisy[i].y+=noise(rng)*.2f;noisy[i].z+=noise(rng);if(i%10==0)noisy[i].z-=.09f;}
 auto robust=soul_add_frame(h,noisy.data(),int(noisy.size()));assert(robust.status==1);assert(robust.rms_metres<.002);error=0;for(size_t i=0;i<a.size();++i)error+=distance(apply(robust.pose,b[i]),a[i]);assert(error/a.size()<.002);soul_destroy(h);std::cout<<"PASS noisy alignment with 10 percent non-overlapping outliers\n";
}
