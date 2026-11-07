"""Run the real Home controller in a simulator; no root helper or rules writes.
Example: python3 Tests/test_layout.py --device <booted-simulator-UDID>
"""
import argparse,json,pathlib,plistlib,subprocess,tempfile,time
root=pathlib.Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--device',required=True);device=a.parse_args().device
bundle='local.wloc.layouttest'
def run(*args,**kw):return subprocess.run(list(map(str,args)),check=True,**kw)
def capture(*args):return subprocess.check_output(list(map(str,args)),text=True).strip()
with tempfile.TemporaryDirectory(prefix='wloc-layout-') as tmp:
 app=pathlib.Path(tmp)/'WLOC.app';app.mkdir()
 info={'CFBundleIdentifier':bundle,'CFBundleName':'WLOC layout test','CFBundleExecutable':'WLOC','CFBundleVersion':'1','CFBundlePackageType':'APPL','MinimumOSVersion':'15.0','CFBundleSupportedPlatforms':['iPhoneSimulator'],'UIDeviceFamily':[1],'UILaunchScreen':{}}
 (app/'Info.plist').write_bytes(plistlib.dumps(info))
 sdk=capture('xcrun','--sdk','iphonesimulator','--show-sdk-path')
 run('xcrun','--sdk','iphonesimulator','clang','-target','arm64-apple-ios15.0-simulator','-isysroot',sdk,'-fobjc-arc','-fblocks','-I'+str(root/'Vendor'),root/'Sources/App.m',root/'Tests/LayoutProbe.m','-framework','UIKit','-framework','MapKit','-framework','NetworkExtension','-framework','Security','-o',app/'WLOC')
 subprocess.run(['xcrun','simctl','terminate',device,bundle],capture_output=True)
 run('xcrun','simctl','install',device,app)
 container=pathlib.Path(capture('xcrun','simctl','get_app_container',device,bundle,'data'))
 report=container/'Documents/layout.json';report.unlink(missing_ok=True)
 run('xcrun','simctl','launch',device,bundle)
 deadline=time.monotonic()+15
 while not report.exists() and time.monotonic()<deadline:time.sleep(.2)
 views=json.loads(report.read_text())
 buttons=[v for v in views if v['kind']=='button'];maps=[v for v in views if v['kind']=='map']
 expected={'应用位置','恢复真实定位（停止代理）','导出本机定位证书','检查规则（只读）','备份并应用 WLOC 规则修改','恢复原始证书规则'}
 assert {v['title'] for v in buttons}==expected,buttons
 assert all(v['height']>=44 and v['width']>=300 for v in buttons),buttons
 assert len(maps)==1 and maps[0]['width']>=300 and maps[0]['height']>=180,maps
 assert 0<maps[0]['latitudeSpan']<2 and 0<maps[0]['longitudeSpan']<2,maps
 print('PASS actual UIKit screen: all 6 buttons have visible titles/44pt targets; map has usable initial viewport')
 print(json.dumps(views,ensure_ascii=False))
