#!/usr/bin/env python3
import pathlib,subprocess,plistlib,os,secrets,uuid,zipfile,hashlib
ROOT=pathlib.Path(__file__).resolve().parent
BUILD=ROOT/'build';APP=BUILD/'Payload/WLOC.app';EXT=APP/'PlugIns/WLOCTunnel.appex';KEYS=pathlib.Path(os.environ.get('WLOC_KEYS_DIR', str(ROOT/'build-private')))
for p in [APP,EXT,KEYS]:p.mkdir(parents=True,exist_ok=True)
os.chmod(KEYS,0o700)
def run(*args):subprocess.run(list(map(str,args)),check=True,cwd=ROOT)
def plist(path,data):path.write_bytes(plistlib.dumps(data))
sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
openssl='/opt/homebrew/opt/openssl@3/bin/openssl'
if not pathlib.Path(openssl).exists():openssl='/usr/bin/openssl'
if not (KEYS/'ca.pem').exists():
 run(openssl,'req','-x509','-newkey','rsa:2048','-nodes','-keyout',KEYS/'ca.key','-out',KEYS/'ca.pem','-days','365','-subj','/CN=WLOC Local '+secrets.token_hex(4),'-addext','basicConstraints=critical,CA:TRUE','-addext','keyUsage=critical,keyCertSign,cRLSign')
 run(openssl,'req','-newkey','rsa:2048','-nodes','-keyout',KEYS/'server.key','-out',KEYS/'server.csr','-subj','/CN=gs-loc.apple.com')
 (KEYS/'server.ext').write_text('basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:gs-loc.apple.com,DNS:gs-loc-cn.apple.com,DNS:gsp-ssl.ls.apple.com,DNS:bluedot.is.autonavi.com,DNS:bluedot.is.autonavi.com.gds.alibabadns.com\n')
 run(openssl,'x509','-req','-in',KEYS/'server.csr','-CA',KEYS/'ca.pem','-CAkey',KEYS/'ca.key','-CAcreateserial','-out',KEYS/'server.pem','-days','180','-extfile',KEYS/'server.ext')
 (KEYS/'password').write_text(secrets.token_hex(24))
for p in KEYS.iterdir():os.chmod(p,0o600)
password=(KEYS/'password').read_text();(EXT/'p12-password.txt').write_text(password)
run(openssl,'pkcs12','-export','-legacy','-inkey',KEYS/'server.key','-in',KEYS/'server.pem','-out',EXT/'server.p12','-passout','file:'+str(KEYS/'password'))
run(openssl,'x509','-in',KEYS/'ca.pem','-outform','DER','-out',KEYS/'ca.der')
plist(APP/'WLOC-Local.mobileconfig',{'PayloadType':'Configuration','PayloadVersion':1,'PayloadIdentifier':'local.wloc.certificate','PayloadUUID':str(uuid.uuid4()),'PayloadDisplayName':'WLOC 本机定位证书','PayloadDescription':'仅用于本机 WLOC 定位域名代理。移除 App 后可在设置中移除此描述文件。','PayloadContent':[{'PayloadType':'com.apple.security.root','PayloadVersion':1,'PayloadIdentifier':'local.wloc.certificate.root','PayloadUUID':str(uuid.uuid4()),'PayloadDisplayName':'WLOC Local','PayloadContent':(KEYS/'ca.der').read_bytes()}]})
base={'CFBundleVersion':'2','CFBundleShortVersionString':'0.1.1','CFBundleDevelopmentRegion':'zh_CN','MinimumOSVersion':'15.0','CFBundleSupportedPlatforms':['iPhoneOS'],'UIDeviceFamily':[1],'LSRequiresIPhoneOS':True}
plist(APP/'Info.plist',dict(base,CFBundleIdentifier='local.wloc.standalone',CFBundleName='WLOC',CFBundleDisplayName='WLOC 定位',CFBundleExecutable='WLOC',CFBundlePackageType='APPL',UILaunchScreen={},UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait']))
plist(EXT/'Info.plist',dict(base,CFBundleIdentifier='local.wloc.standalone.tunnel',CFBundleName='WLOCTunnel',CFBundleExecutable='WLOCTunnel',CFBundlePackageType='XPC!',NSExtension={'NSExtensionPointIdentifier':'com.apple.networkextension.packet-tunnel','NSExtensionPrincipalClass':'Tunnel'}))
common=['xcrun','--sdk','iphoneos','clang','-target','arm64-apple-ios15.0','-isysroot',sdk,'-fobjc-arc','-fblocks','-O2','-I'+str(ROOT/'Vendor'),'-Wno-deprecated-declarations','-Wno-incompatible-pointer-types-discards-qualifiers']
run(*common,ROOT/'Sources/App.m',ROOT/'Sources/RulesBridge.m',ROOT/'Vendor/rules.c','-framework','UIKit','-framework','MapKit','-framework','NetworkExtension','-framework','Security','-lsqlite3','-o',APP/'WLOC')
run(*common,ROOT/'Sources/Tunnel.m',ROOT/'Sources/Proxy.m','-fapplication-extension','-framework','Foundation','-framework','NetworkExtension','-framework','Security','-framework','JavaScriptCore','-framework','CFNetwork','-e','_NSExtensionMain','-o',EXT/'WLOCTunnel')
(EXT/'wloc.js').write_bytes((ROOT/'Vendor/wloc.js').read_bytes())
for directory in [APP,EXT]:
 ent={'application-identifier':'local.wloc.standalone'+('.tunnel' if directory==EXT else ''),'com.apple.developer.networking.networkextension':['packet-tunnel-provider']}
 if directory==APP:ent.update({'com.apple.private.persona-mgmt':True,'com.apple.private.security.no-container':True,'com.apple.private.security.no-sandbox':True,'com.apple.private.security.storage.trustd':True,'com.apple.security.exception.files.absolute-path.read-write':['/private/var/protected/trustd/'],'platform-application':True})
 plist(BUILD/(directory.stem+'.entitlements.plist'),ent)
for directory in [EXT,APP]:run('codesign','--force','--sign','-','--generate-entitlement-der','--entitlements',BUILD/(directory.stem+'.entitlements.plist'),directory)
run('codesign','--verify','--deep','--strict',APP)
out=ROOT/'WLOCStandalone-0.1.1.tipa'
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
 for p in (BUILD/'Payload').rglob('*'):
  if p.is_file():z.write(p,p.relative_to(BUILD))
print(out);print('SHA256',hashlib.sha256(out.read_bytes()).hexdigest())
