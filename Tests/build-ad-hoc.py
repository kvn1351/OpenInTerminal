#!/usr/bin/env python3
"""Build and package the full app with ad hoc signatures, never a personal identity."""
import argparse
import hashlib
import json
import plistlib
import shutil
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--deployment-target', help='Optional build-only target override')
args = parser.parse_args()
out = Path(tempfile.mkdtemp(prefix='oit-ad-hoc-', dir='/private/tmp'))
# Keep developer home paths out of compiler-generated strings in public binaries.
source = out/'source'
for raw in subprocess.check_output(['git','ls-files','-z'],cwd=root).split(b'\0'):
    if not raw:
        continue
    relative=Path(raw.decode())
    if (root/relative).is_file():
        target=source/relative
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(root/relative,target)
build = ['xcodebuild', '-workspace', 'OpenInTerminal.xcworkspace', '-scheme', 'OpenInTerminal',
         '-configuration', 'Release', '-derivedDataPath', str(out/'build'),
         '-destination', 'generic/platform=macOS', 'CODE_SIGNING_ALLOWED=NO']
if args.deployment_target:
    build.append('MACOSX_DEPLOYMENT_TARGET='+args.deployment_target)
print(f'Output: {out}', flush=True)
with (out/'build.log').open('w') as log:
    subprocess.run(build+['build'], cwd=source, stdout=log, stderr=subprocess.STDOUT, check=True)
products=out/'build/Build/Products/Release'
with (products/'OpenInTerminal.app/Contents/Info.plist').open('rb') as info:
    version=plistlib.load(info)['CFBundleShortVersionString']
package=out/f'OpenInTerminal-{version}'
package.mkdir()
app=package/'OpenInTerminal.app'
def run(*command):
    subprocess.run(command, check=True)
run('ditto','--norsrc','--noextattr',str(products/app.name),str(app))
run('ditto','--norsrc','--noextattr',str(products/'OpenInTerminalHelper.app'),str(app/'Contents/Library/LoginItems/OpenInTerminalHelper.app'))
for pattern in ('*.dylib','*.framework','*.appex','*.app'):
    for path in sorted(app.rglob(pattern), key=lambda p:len(p.parts), reverse=True):
        ent=[]
        if path.suffix=='.appex':
            ent=['--entitlements',str(root/'OpenInTerminalFinderExtension/OpenInTerminalFinderExtension.entitlements')]
        run('codesign','--force','--sign','-',*ent,str(path))
run('codesign','--force','--sign','-','--entitlements',str(root/'OpenInTerminal/OpenInTerminal.entitlements'),str(app))
run('codesign','--verify','--deep','--strict',str(app))
# Check all nested code, not just the top-level signature.
for path in [app,*app.rglob('*.appex'),*app.rglob('*.app'),*app.rglob('*.framework'),*app.rglob('*.dylib')]:
    details=subprocess.run(['codesign','-dv','--verbose=4',str(path)],capture_output=True,text=True,check=True).stderr
    if 'Signature=adhoc' not in details or 'TeamIdentifier=not set' not in details:
        raise RuntimeError(f'Unexpected non-ad-hoc signature: {path}')
shutil.copy2(root/'docs/ad-hoc-build.md', package/'READ-ME-FIRST.md')
evidence={'version':version,
          'revision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
          'signing':'ad hoc; no Apple Developer Team ID or personal certificate',
          'notarization':'not performed','deployment_target_override':args.deployment_target,
          'architectures':subprocess.check_output(['lipo','-archs',str(app/'Contents/MacOS/OpenInTerminal')],text=True).strip(),
          'xcode':subprocess.check_output(['xcodebuild','-version'],text=True).strip(),
          'macos_sdk':subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-version'],text=True).strip(),
          'finder_shared_preferences':'file-based bridge via the Finder extension Application Scripts directory'}
(package/'build-info.json').write_text(json.dumps(evidence,indent=2)+'\n')
archive=out/f'{package.name}.zip'
run('ditto','-c','-k','--norsrc','--noextattr','--keepParent',str(package),str(archive))
run('ditto','-x','-k',str(archive),str(out/'extracted'))
run('codesign','--verify','--deep','--strict',str(out/'extracted'/package.name/app.name))
digest=hashlib.sha256(archive.read_bytes()).hexdigest()
(out/'SHA256SUMS').write_text(digest+'  '+archive.name+'\n')
print(json.dumps({'archive':str(archive),'sha256':digest,**evidence},indent=2))
