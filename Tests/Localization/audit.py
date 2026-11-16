"""Check catalogue coverage and macOS terminology using installed Apple resources."""
from pathlib import Path
import collections, json, plistlib, re, subprocess
repo=Path(__file__).resolve().parents[2]
def catalog(language):
    return json.loads(subprocess.check_output(['plutil','-convert','json','-o','-',str(repo/'Resources'/f'{language}.lproj/Localizable.strings')]))
en,zh=catalog('en'),catalog('zh-Hans')
assert en.keys()==zh.keys(), 'Languages must have identical key sets'
for key in en:
    assert zh[key].strip(), f'Empty translation: {key}'
    assert collections.Counter(re.findall(r'%(?:\d+\$)?[@dflus]',en[key]))==collections.Counter(re.findall(r'%(?:\d+\$)?[@dflus]',zh[key])), key
for source in (repo/'Sources/Agent').glob('*.swift'):
    for key in re.findall(r'L10n\.(?:text|format)\("([^"\\]*)"',source.read_text()):
        if key.endswith('.') or key=='':continue # Dynamic category keys.
        assert key in en, f'{source.name}: missing catalogue entry {key}'
dock=plistlib.loads(Path('/System/Library/CoreServices/Dock.app/Contents/Resources/zh_CN.lproj/DockMenus.strings').read_bytes())
for app_key,system_key in {'Options':'OPTIONS','Show in Finder':'SHOW_IN_FINDER','Open':'OPEN','Quit':'QUIT','Force Quit':'FORCE_QUIT','Hide':'HIDE','Show':'SHOW','Show All Windows':'SHOW_ALL_WINDOWS','Open at login':'OPEN_AT_LOGIN','Show in Dock':'KEEP_IN_DOCK'}.items():
    assert zh[app_key]==dock[system_key], (app_key,zh[app_key],dock[system_key])
r=Path('/System/Library/Frameworks/AppKit.framework/Resources')
for table,keys in {'Common':['Cancel','Delete','OK'],'SavePanel':['Save'],'MenuCommands':['Cut','Copy','Paste','Select All'],'FunctionKeyNames':['Undo','Redo'],'InputManager':['Edit']}.items():
    official=plistlib.loads((r/f'{table}.loctable').read_bytes())['zh_CN']
    for key in keys: assert zh[key]==official[key], (key,zh[key],official[key])
privacy=Path('/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/Resources/Localizable.loctable')
if privacy.exists():
    official=plistlib.loads(privacy.read_bytes())['zh_CN']
    assert zh['App Management']==official['APPLICATION_BUNDLES']
print(f'PASS: {len(en)} bilingual entries, app string coverage, format placeholders and Apple Dock/AppKit/privacy terminology')
