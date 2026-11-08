"""Run real authenticated loopback control + TLS proxy startup. No remote traffic or VPN configuration."""
import pathlib,plistlib,subprocess,tempfile,shutil
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wloc-control-') as tmp:
 app=pathlib.Path(tmp)/'ControlTest.app/Contents';(app/'MacOS').mkdir(parents=True);resources=app/'Resources';resources.mkdir()
 (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'test','CFBundleIdentifier':'local.wloc.controltest','CFBundlePackageType':'APPL'}))
 for name in ['server.p12','p12-password.txt']:
  shutil.copyfile(root/'build/Payload/WLOC.app/PlugIns/WLOCTunnel.appex'/name,resources/name)
 executable=app/'MacOS/test'
 subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-O1','-Wno-deprecated-declarations','-I'+str(root/'Sources'),root/'Tests/ControlIntegrationTest.m',root/'Sources/Proxy.m',root/'Sources/LocalControl.m','-framework','Foundation','-framework','Security','-framework','JavaScriptCore','-framework','CFNetwork','-o',executable],check=True)
 subprocess.run([executable],check=True,timeout=30)
