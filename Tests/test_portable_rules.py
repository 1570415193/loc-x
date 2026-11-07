"""Run upstream database tests on macOS against disposable databases only.
Root-only entry gate is disabled in a temporary test copy; ownership checks remain.
The production helper still requires root. Device permissions are not simulated.
"""
import pathlib,tempfile,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='wloc-portable-') as tmp:
 p=pathlib.Path(tmp)
 source=(root/'Vendor/rules.c').read_text().replace('if (geteuid() != 0)', 'if (geteuid() == (uid_t)-1)')
 (p/'rules.c').write_text(source);(p/'rules.h').write_bytes((root/'Vendor/rules.h').read_bytes())
 test=(root/'Tests/test_rules.py').read_text().replace("if os.geteuid() != 0:","if False:").replace("'-l:libsqlite3.so.0'","'-lsqlite3'").replace("temp = Path(directory)","temp = Path(directory).resolve()")
 (p/'test_rules.py').write_text(test)
 subprocess.run(['python3',str(p/'test_rules.py')],check=True)
