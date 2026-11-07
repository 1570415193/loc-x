"""Exercise the embedded upstream script through the actual JavaScriptCore bridge."""
import pathlib,tempfile,plistlib,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wloc-jsc-') as tmp:
 app=pathlib.Path(tmp)/'RewriteTests.app/Contents'
 (app/'MacOS').mkdir(parents=True);(app/'Resources').mkdir()
 (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'test','CFBundleIdentifier':'local.wloc.tests','CFBundlePackageType':'APPL'}))
 (app/'Resources/wloc.js').write_bytes((root/'Vendor/wloc.js').read_bytes())
 binary=app/'MacOS/test'
 subprocess.run(['xcrun','clang','-fobjc-arc','-fblocks','-O1','-Wno-deprecated-declarations','-I'+str(root/'Sources'),str(root/'Tests/RewriteTest.m'),str(root/'Sources/Proxy.m'),'-framework','Foundation','-framework','Security','-framework','JavaScriptCore','-framework','CFNetwork','-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True)
