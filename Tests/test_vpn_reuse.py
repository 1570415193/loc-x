"""Run the real Home controller in a simulator; no root helper or rules writes.
Example: python3 Tests/test_layout.py --device <booted-simulator-UDID>
"""
import argparse,json,pathlib,plistlib,subprocess,tempfile,time,shutil
root=pathlib.Path(__file__).resolve().parents[1]
a=argparse.ArgumentParser();a.add_argument('--device',required=True);device=a.parse_args().device
bundle='local.wloc.vpnreusetest'
def run(*args,**kw):return subprocess.run(list(map(str,args)),check=True,**kw)
def capture(*args):return subprocess.check_output(list(map(str,args)),text=True).strip()
with tempfile.TemporaryDirectory(prefix='wloc-layout-') as tmp:
 app=pathlib.Path(tmp)/'WLOC.app';app.mkdir()
 info={'CFBundleIdentifier':bundle,'CFBundleName':'WLOC layout test','CFBundleExecutable':'WLOC','CFBundleVersion':'1','CFBundlePackageType':'APPL','MinimumOSVersion':'15.0','CFBundleSupportedPlatforms':['iPhoneSimulator'],'UIDeviceFamily':[1],'UILaunchScreen':{},'NSLocationWhenInUseUsageDescription':'测试当前位置按钮的前台定位授权'}
 (app/'Info.plist').write_bytes(plistlib.dumps(info))
 sdk=capture('xcrun','--sdk','iphonesimulator','--show-sdk-path')
 run('xcrun','--sdk','iphonesimulator','clang','-target','arm64-apple-ios15.0-simulator','-isysroot',sdk,'-fobjc-arc','-fblocks','-I'+str(root/'Vendor'),'-I'+str(root/'Sources'),root/'Sources/App.m',root/'Sources/LocalControl.m',root/'Sources/MapPanel.m',root/'Tests/VPNReuseProbe.m','-framework','UIKit','-framework','WebKit','-framework','MapKit','-framework','CoreGraphics','-framework','CoreLocation','-framework','NetworkExtension','-framework','Security','-o',app/'WLOC')
 shutil.copytree(root/'Resources/Map',app/'Map')
 shutil.copyfile(root/'build/Payload/WLOC.app/server.der',app/'server.der')
 subprocess.run(['xcrun','simctl','terminate',device,bundle],capture_output=True)
 run('xcrun','simctl','install',device,app)
 container=pathlib.Path(capture('xcrun','simctl','get_app_container',device,bundle,'data'))
 report=container/'Documents/layout.json';report.unlink(missing_ok=True)
 run('xcrun','simctl','launch',device,bundle)
 deadline=time.monotonic()+15
 while not report.exists() and time.monotonic()<deadline:time.sleep(.2)
 results=json.loads(report.read_text())
 assert results and all(results.values()),results
 print('PASS actual Home VPN configuration reuse:',json.dumps(results,ensure_ascii=False))
