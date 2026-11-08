// Adapted from Yu9191/wloc worker/src/gcj-browser.js (AGPL-3.0).
// https://github.com/Yu9191/wloc/blob/main/worker/src/gcj-browser.js
var GCJ_A=6378245.0, GCJ_EE=0.00669342162296594323;
function gcjOutOfChina(lng,la){return lng<72.004||lng>137.8347||la<0.8293||la>55.8271;}
function gcjDeltaLat(x,y){var r=-100+2*x+3*y+.2*y*y+.1*x*y+.2*Math.sqrt(Math.abs(x));r+=(20*Math.sin(6*x*Math.PI)+20*Math.sin(2*x*Math.PI))*2/3;r+=(20*Math.sin(y*Math.PI)+40*Math.sin(y/3*Math.PI))*2/3;r+=(160*Math.sin(y/12*Math.PI)+320*Math.sin(y*Math.PI/30))*2/3;return r;}
function gcjDeltaLon(x,y){var r=300+x+2*y+.1*x*x+.1*x*y+.1*Math.sqrt(Math.abs(x));r+=(20*Math.sin(6*x*Math.PI)+20*Math.sin(2*x*Math.PI))*2/3;r+=(20*Math.sin(x*Math.PI)+40*Math.sin(x/3*Math.PI))*2/3;r+=(150*Math.sin(x/12*Math.PI)+300*Math.sin(x/30*Math.PI))*2/3;return r;}
function wgs84ToGcj02(lat,lon){if(gcjOutOfChina(lon,lat))return {lat,lon};var dLat=gcjDeltaLat(lon-105,lat-35),dLon=gcjDeltaLon(lon-105,lat-35),rad=lat/180*Math.PI,magic=1-GCJ_EE*Math.sin(rad)**2,root=Math.sqrt(magic);dLat=dLat*180/((GCJ_A*(1-GCJ_EE)/(magic*root))*Math.PI);dLon=dLon*180/(GCJ_A/root*Math.cos(rad)*Math.PI);return {lat:lat+dLat,lon:lon+dLon};}
function gcj02ToWgs84(lat,lon){if(gcjOutOfChina(lon,lat))return {lat,lon};var a=lat,b=lon;for(var i=0;i<6;i++){var g=wgs84ToGcj02(a,b),da=g.lat-lat,db=g.lon-lon;if(Math.abs(da)<1e-9&&Math.abs(db)<1e-9)break;a-=da;b-=db;}return {lat:a,lon:b};}
