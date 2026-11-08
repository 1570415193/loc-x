const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.join(__dirname,'../Resources/Map');let active,marker,current,click;const posts=[],timers=[];
const state={lat:31.2304,lng:121.4737,zoom:12};
const map={attributionControl:{setPrefix(){}},setView(p,z){state.lat=p[0];state.lng=p[1];state.zoom=z;return this},getCenter(){return{lat:state.lat,lng:state.lng}},getZoom(){return state.zoom},setMaxZoom(){},removeLayer(){},on(event,fn){if(event==='click')click=fn},project(){return{unscaleBy(){return{floor(){return{x:1,y:2}}}}}}};
function layer(url,options){return{url,options,_tileZoom:12,_tiles:new Proxy({},{get(){return{loaded:1,el:{naturalWidth:256}}}}),getTileSize(){return{x:256,y:256}},handlers:{},on(e,fn){this.handlers[e]=fn;return this},addTo(){active=this;return this}}}
const context=vm.createContext({console,Number,Math,Set,setTimeout:(f)=>timers.push(f),window:{webkit:{messageHandlers:{map:{postMessage:v=>posts.push(v)}}}},L:{map:()=>map,tileLayer:layer,divIcon:x=>x,marker:(p)=>({point:p,addTo(){marker=this;return this}}),circleMarker:(p)=>({point:p,addTo(){current=this;return this}})}});
context.webkit=context.window.webkit;context.window=context;
for(const file of ['sources.js','gcj.js','map.js'])vm.runInContext(fs.readFileSync(path.join(root,file),'utf8'),context,{filename:file});
const evaluate=s=>vm.runInContext(s,context);
const sources=JSON.parse(fs.readFileSync(path.join(root,'sources.json'),'utf8'));
assert.equal(sources.length,1,'street maps only');assert.equal(sources[0].id,'amap');assert(sources[0].url.includes('style=7&'),'street tile style');assert.equal(sources[0].gcj,true);assert.equal(evaluate('source'),0);assert(active.url.includes('amap'));
assert.deepEqual(JSON.parse(JSON.stringify(evaluate('MAP_SOURCES'))),sources);
for(const [lat,lon] of [[31.2304,121.4737],[22.544577,113.94114],[39.916527,116.397128],[-33.86,151.2],[40.7,-74],[0,0]]){const w=evaluate(`gcj02ToWgs84(...Object.values(wgs84ToGcj02(${lat},${lon})))`);assert(Math.abs(w.lat-lat)<1e-8&&Math.abs(w.lon-lon)<1e-8)}
evaluate('setPoint(31.2304,121.4737,true)');const display=evaluate('wgs84ToGcj02(31.2304,121.4737)');assert(Math.abs(marker.point[0]-display.lat)<1e-9&&Math.abs(marker.point[1]-display.lon)<1e-9);
active.handlers.tileload();click({latlng:{lat:display.lat,lng:display.lon}});const pick=posts.filter(x=>x.type==='pick').at(-1);assert(Math.abs(pick.latitude-31.2304)<1e-8&&Math.abs(pick.longitude-121.4737)<1e-8);
const before=posts.filter(x=>x.type==='pick').length,target=JSON.stringify(evaluate('selectedWGS'));
evaluate('showCurrentLocation(39.916527,116.397128,25)');const actual=evaluate('wgs84ToGcj02(39.916527,116.397128)');assert(Math.abs(current.point[0]-actual.lat)<1e-9&&Math.abs(current.point[1]-actual.lon)<1e-9,'system WGS fix displayed in GCJ street coordinates');assert.equal(state.zoom,16);assert.equal(JSON.stringify(evaluate('selectedWGS')),target,'current position does not replace target');assert.equal(posts.filter(x=>x.type==='pick').length,before,'current position never applies selection');
const centered=JSON.stringify(state);evaluate('showCurrentLocation(91,116,20)');assert.equal(JSON.stringify(state),centered,'invalid current location ignored');
evaluate('retryMap()');assert(Math.abs(current.point[0]-actual.lat)<1e-9,'current dot survives map reload');assert.equal(JSON.stringify(evaluate('selectedWGS')),target);
active.handlers.tileload();active._tiles={};click({latlng:{lat:display.lat,lng:display.lon}});assert.equal(posts.filter(x=>x.type==='pick').length,before,'unloaded tile cannot pick');
evaluate('retryMap()');const stale=active;evaluate('retryMap()');stale.handlers.tileerror();assert.equal(evaluate('errors'),0);active.handlers.tileerror();active.handlers.tileerror();assert.equal(evaluate('source'),0);assert(posts.at(-1).message.includes('高德街道图'),'error never switches to satellite');
console.log('PASS real map script: AMap street-only, WGS/GCJ pick, current-location dot/center without changing target, invalid fixes, retry and stale errors');
