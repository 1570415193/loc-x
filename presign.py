#!/usr/bin/env python3
"""Pre-apply TrollStore's official CMS signing method, avoiding on-device ldid.
Usage: python3 presign.py /path/to/official/fastPathSign /path/to/WLOCStandalone.tipa
Tool source: https://github.com/opa334/TrollStore/tree/main/Exploits/fastPathSign
"""
import pathlib,sys,subprocess,tempfile,zipfile,plistlib,hashlib
root=pathlib.Path(__file__).resolve().parent
tool=pathlib.Path(sys.argv[1]).resolve(strict=True)
source=pathlib.Path(sys.argv[2]).resolve(strict=True)
out=source.with_name(source.stem+'-presigned.tipa')
def run(*args):subprocess.run(list(map(str,args)),check=True)
with tempfile.TemporaryDirectory(prefix='wloc-presign-') as tmp:
 p=pathlib.Path(tmp)
 with zipfile.ZipFile(source) as z:z.extractall(p)
 app=p/'Payload/WLOC.app';ext=app/'PlugIns/WLOCTunnel.appex'
 for bundle in [ext,app]:
  info=plistlib.loads((bundle/'Info.plist').read_bytes());info['TSPreAppliedExploitType']=2
  (bundle/'Info.plist').write_bytes(plistlib.dumps(info))
  ent=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(bundle)],stderr=subprocess.DEVNULL))
  if bundle==ext:ent['com.apple.private.security.container-required']=info['CFBundleIdentifier']
  path=p/(bundle.stem+'.plist');path.write_bytes(plistlib.dumps(ent))
  run('codesign','--force','--sign','-','--generate-entitlement-der','--entitlements',path,bundle)
 run('codesign','--verify','--deep','--strict',app)
 for bundle in [ext,app]:
  info=plistlib.loads((bundle/'Info.plist').read_bytes())
  run(tool,'--entitlements',p/(bundle.stem+'.plist'),bundle/info['CFBundleExecutable'])
  actual=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(bundle)],stderr=subprocess.DEVNULL))
  expected=plistlib.loads((p/(bundle.stem+'.plist')).read_bytes());assert actual==expected,'Entitlements changed'
 with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
  for file in (p/'Payload').rglob('*'):
   if file.is_file():z.write(file,file.relative_to(p))
with zipfile.ZipFile(out) as z:assert z.testzip() is None
print(out);print('SHA256',hashlib.sha256(out.read_bytes()).hexdigest())
