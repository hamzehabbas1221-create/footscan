#include "SoulCore.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <numeric>
#include <unordered_map>
#include <vector>

namespace {
using P = SoulPoint;
P operator+(P a,P b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
P operator-(P a,P b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
P operator*(P a,float s){return {a.x*s,a.y*s,a.z*s};}
float dot(P a,P b){return a.x*b.x+a.y*b.y+a.z*b.z;}
float norm(P a){return std::sqrt(dot(a,a));}
bool finite(P p){return std::isfinite(p.x)&&std::isfinite(p.y)&&std::isfinite(p.z);}
float component(P p,int a){return a==0?p.x:(a==1?p.y:p.z);}
SoulPose identity(){return {{1,0,0,0,1,0,0,0,1},{0,0,0}};}
P rotate(const SoulPose&m,P p){return {m.r[0]*p.x+m.r[1]*p.y+m.r[2]*p.z,m.r[3]*p.x+m.r[4]*p.y+m.r[5]*p.z,m.r[6]*p.x+m.r[7]*p.y+m.r[8]*p.z};}
P apply(const SoulPose&m,P p){return rotate(m,p)+P{m.t[0],m.t[1],m.t[2]};}
SoulPose compose(const SoulPose&a,const SoulPose&b){SoulPose c{};for(int i=0;i<3;++i)for(int j=0;j<3;++j)for(int k=0;k<3;++k)c.r[i*3+j]+=a.r[i*3+k]*b.r[k*3+j];P t=apply(a,{b.t[0],b.t[1],b.t[2]});c.t[0]=t.x;c.t[1]=t.y;c.t[2]=t.z;return c;}
float angle(const SoulPose&a,const SoulPose&b){float tr=0;for(int i=0;i<9;++i)tr+=a.r[i]*b.r[i];return std::acos(std::clamp((tr-1)*.5f,-1.f,1.f));}

// Horn absolute orientation, with a Jacobi eigensolver (not power iteration,
// which can converge to the wrong eigenvalue for nearly planar surfaces).
bool fit(const std::vector<P>&a,const std::vector<P>&b,SoulPose&out){
    if(a.size()!=b.size()||a.size()<6)return false;
    P ca{},cb{};for(size_t i=0;i<a.size();++i){if(!finite(a[i])||!finite(b[i]))return false;ca=ca+a[i];cb=cb+b[i];}ca=ca*(1.f/a.size());cb=cb*(1.f/b.size());
    double s[3][3]{};double spread=0,secondArea=0;P seed{};float maxLength=0;
    for(size_t i=0;i<a.size();++i){P x=a[i]-ca,y=b[i]-cb;spread+=dot(x,x);if(dot(x,x)>maxLength){seed=x;maxLength=dot(x,x);}for(int r=0;r<3;++r)for(int c=0;c<3;++c)s[r][c]+=component(x,r)*component(y,c);}
    for(auto p:a){P x=p-ca;P cross{seed.y*x.z-seed.z*x.y,seed.z*x.x-seed.x*x.z,seed.x*x.y-seed.y*x.x};secondArea+=dot(cross,cross);}
    if(spread<1e-8||secondArea<1e-12)return false;
    double n[4][4]{};double trace=s[0][0]+s[1][1]+s[2][2];
    n[0][0]=trace;n[0][1]=n[1][0]=s[1][2]-s[2][1];n[0][2]=n[2][0]=s[2][0]-s[0][2];n[0][3]=n[3][0]=s[0][1]-s[1][0];
    n[1][1]=s[0][0]-s[1][1]-s[2][2];n[2][2]=-s[0][0]+s[1][1]-s[2][2];n[3][3]=-s[0][0]-s[1][1]+s[2][2];
    n[1][2]=n[2][1]=s[0][1]+s[1][0];n[1][3]=n[3][1]=s[0][2]+s[2][0];n[2][3]=n[3][2]=s[1][2]+s[2][1];
    double v[4][4]{};for(int i=0;i<4;++i)v[i][i]=1;
    for(int it=0;it<64;++it){int p=0,q=1;for(int i=0;i<4;++i)for(int j=i+1;j<4;++j)if(std::abs(n[i][j])>std::abs(n[p][q])){p=i;q=j;}if(std::abs(n[p][q])<1e-13)break;
        double theta=.5*std::atan2(2*n[p][q],n[q][q]-n[p][p]),c=std::cos(theta),ss=std::sin(theta);
        double np=n[p][p],nq=n[q][q],npq=n[p][q];n[p][p]=c*c*np-2*ss*c*npq+ss*ss*nq;n[q][q]=ss*ss*np+2*ss*c*npq+c*c*nq;n[p][q]=n[q][p]=0;
        for(int k=0;k<4;++k)if(k!=p&&k!=q){double kp=n[k][p],kq=n[k][q];n[k][p]=n[p][k]=c*kp-ss*kq;n[k][q]=n[q][k]=ss*kp+c*kq;}
        for(int k=0;k<4;++k){double kp=v[k][p],kq=v[k][q];v[k][p]=c*kp-ss*kq;v[k][q]=ss*kp+c*kq;}
    }
    int k=0;for(int i=1;i<4;++i)if(n[i][i]>n[k][k])k=i;
    double w=v[0][k],x=v[1][k],y=v[2][k],z=v[3][k];
    out={{float(1-2*(y*y+z*z)),float(2*(x*y-z*w)),float(2*(x*z+y*w)),float(2*(x*y+z*w)),float(1-2*(x*x+z*z)),float(2*(y*z-x*w)),float(2*(x*z-y*w)),float(2*(y*z+x*w)),float(1-2*(x*x+y*y))},{0,0,0}};
    P t=cb-rotate(out,ca);out.t[0]=t.x;out.t[1]=t.y;out.t[2]=t.z;return true;
}
struct KDNode{int point,left=-1,right=-1,axis=0;};
class KDTree{
    const std::vector<P>&points;std::vector<int>ids;std::vector<KDNode>nodes;int root=-1;
    int build(int lo,int hi,int depth){if(lo>=hi)return -1;int mid=(lo+hi)/2,axis=depth%3;std::nth_element(ids.begin()+lo,ids.begin()+mid,ids.begin()+hi,[&](int a,int b){return component(points[a],axis)<component(points[b],axis);});int node=int(nodes.size());nodes.push_back({ids[mid],-1,-1,axis});int left=build(lo,mid,depth+1),right=build(mid+1,hi,depth+1);nodes[node].left=left;nodes[node].right=right;return node;}
    void search(int i,P p,int&best,float&distance)const{if(i<0)return;const auto&n=nodes[i];float d=dot(points[n.point]-p,points[n.point]-p);if(d<distance){distance=d;best=n.point;}float delta=component(p,n.axis)-component(points[n.point],n.axis);search(delta<0?n.left:n.right,p,best,distance);if(delta*delta<distance)search(delta<0?n.right:n.left,p,best,distance);}
public:explicit KDTree(const std::vector<P>&p):points(p){ids.resize(p.size());std::iota(ids.begin(),ids.end(),0);nodes.reserve(p.size());root=build(0,int(p.size()),0);}int nearest(P p,float&distance)const{int best=-1;search(root,p,best,distance);return best;}
};
struct Key{int x,y,z;bool operator==(const Key&o)const{return x==o.x&&y==o.y&&z==o.z;}};
struct Hash{size_t operator()(const Key&k)const{return size_t(uint32_t(k.x)*73856093u)^size_t(uint32_t(k.y)*19349663u)^size_t(uint32_t(k.z)*83492791u);}};
struct Cell{P sum{};uint32_t n=0;};
struct Scanner{
    std::unordered_map<Key,Cell,Hash>cells;SoulPose last=identity();int accepted=0,rejected=0;std::array<bool,24>views{};P center{};static constexpr size_t budget=100000;
    std::vector<P>points()const{std::vector<P>p;p.reserve(cells.size());for(const auto&c:cells)p.push_back(c.second.sum*(1.f/c.second.n));return p;}
    void merge(const std::vector<P>&p,const SoulPose&pose){for(P raw:p){P v=apply(pose,raw);Key k{int(std::floor(v.x/.0015f)),int(std::floor(v.y/.0015f)),int(std::floor(v.z/.0015f))};auto it=cells.find(k);if(it==cells.end()){if(cells.size()>=budget)continue;cells.emplace(k,Cell{v,1});}else if(it->second.n<128){it->second.sum=it->second.sum+v;++it->second.n;}}}
    SoulResult result(int status,float rms=0,float ratio=0)const{SoulResult r{};r.status=status;r.point_count=int32_t(cells.size());r.accepted_frames=accepted;r.rejected_frames=rejected;r.rms_metres=rms;r.inlier_ratio=ratio;r.pose=last;r.view_bins=int32_t(std::count(views.begin(),views.end(),true));return r;}
    SoulResult add(const P*input,int count){
        if(!input||count<500){++rejected;return result(0);}
        std::vector<P>p;size_t step=std::max(1,count/9000);for(int i=0;i<count;i+=int(step)){P v=input[i];if(finite(v)&&norm(v)>.10f&&norm(v)<1.0f)p.push_back(v);}
        if(p.size()<500){++rejected;return result(0);}
        if(cells.empty()){for(P v:p)center=center+v;center=center*(1.f/p.size());merge(p,last);accepted=1;views[12]=true;return result(1,0,1);}
        if(cells.size()>=budget)return result(3);
        auto target=points();if(target.size()>14000){std::vector<P>small;float stride=float(target.size())/14000.f;for(int i=0;i<14000;++i)small.push_back(target[size_t(i*stride)]);target=std::move(small);}
        KDTree tree(target);std::vector<P>sample;float stride=std::max(1.f,float(p.size())/1800.f);for(float i=0;i<p.size();i+=stride)sample.push_back(p[size_t(i)]);
        SoulPose pose=last;float rms=1,ratio=0;
        for(int iteration=0;iteration<18;++iteration){struct Pair{P a,b;float d;};std::vector<Pair>pairs;pairs.reserve(sample.size());
            for(P raw:sample){P q=apply(pose,raw);float d=.022f*.022f;int index=tree.nearest(q,d);if(index>=0)pairs.push_back({q,target[index],d});}
            ratio=float(pairs.size())/sample.size();if(pairs.size()<300||ratio<.65f){++rejected;return result(0,rms,ratio);}
            std::sort(pairs.begin(),pairs.end(),[](const Pair&a,const Pair&b){return a.d<b.d;});pairs.resize(size_t(pairs.size()*.85));std::vector<P>a,b;float squared=0;
            for(const auto&pair:pairs){a.push_back(pair.a);b.push_back(pair.b);squared+=pair.d;}rms=std::sqrt(squared/pairs.size());SoulPose delta;
            if(!fit(a,b,delta)){++rejected;return result(0,rms,ratio);}pose=compose(delta,pose);
            if(norm({delta.t[0],delta.t[1],delta.t[2]})<.00003f&&angle(delta,identity())<.0005f)break;
        }
        // Re-evaluate residuals at the FINAL pose; do not trust the pre-update score.
        std::vector<float>residuals;for(P raw:sample){float d=.022f*.022f;if(tree.nearest(apply(pose,raw),d)>=0)residuals.push_back(d);}ratio=float(residuals.size())/sample.size();std::sort(residuals.begin(),residuals.end());if(residuals.size()<300){++rejected;return result(0,1,ratio);}residuals.resize(size_t(residuals.size()*.85));double sum=0;for(float d:residuals)sum+=d;rms=float(std::sqrt(sum/residuals.size()));
        const float motion=norm(P{pose.t[0]-last.t[0],pose.t[1]-last.t[1],pose.t[2]-last.t[2]});const float rotation=angle(pose,last);
        if(rms>.0035f||ratio<.65f||motion>.04f||rotation>.26f){++rejected;return result(0,rms,ratio);}
        if(motion<.001f&&rotation<.0087f)return result(2,rms,ratio);
        last=pose;merge(p,pose);++accepted;P direction=P{pose.t[0],pose.t[1],pose.t[2]}-center;float az=std::atan2(direction.x,direction.z);int bin=std::clamp(int((az+3.14159265f)/(2*3.14159265f)*24),0,23);views[bin]=true;return result(1,rms,ratio);
    }
};
}
extern "C" {
SoulHandle soul_create(){return new Scanner();}
void soul_destroy(SoulHandle h){delete static_cast<Scanner*>(h);}
void soul_reset(SoulHandle h){if(h)*static_cast<Scanner*>(h)=Scanner();}
SoulResult soul_add_frame(SoulHandle h,const SoulPoint*p,int32_t n){return h?static_cast<Scanner*>(h)->add(p,n):SoulResult{};}
int32_t soul_point_count(SoulHandle h){return h?int32_t(static_cast<Scanner*>(h)->cells.size()):0;}
int32_t soul_copy_points(SoulHandle h,SoulPoint*out,int32_t capacity){if(!h||!out||capacity<=0)return 0;auto p=static_cast<Scanner*>(h)->points();int n=std::min(int(p.size()),capacity);std::copy_n(p.data(),n,out);return n;}
int32_t soul_fit_rigid(const SoulPoint*a,const SoulPoint*b,int32_t n,SoulPose*out){if(!a||!b||!out||n<6)return 0;return fit(std::vector<P>(a,a+n),std::vector<P>(b,b+n),*out)?1:0;}
}
