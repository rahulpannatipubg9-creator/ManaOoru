"""Create an isolated debug performance APK from the exact exported baseline.

Assets stay byte-identical. Only the listed current GDScript sources, their remaps,
the test package ID, and the opt-in command line are changed. Sign with apksigner.
The test package deliberately cannot replace the user's differently signed app.
"""
import hashlib
import json
import pathlib
import shutil
import struct
import sys
import zipfile

source, target = map(pathlib.Path, sys.argv[1:3])
original_id = 'com.manaooru.prototype'
test_id = 'com.manaooru.perfcheck'
assert len(original_id) == len(test_id)
scripts = ['scripts/world/tree_builder.gd',
           'scripts/performance/performance_controller.gd',
           'scripts/performance/frame_profile.gd']
replacements = {}
for path in scripts:
    resource = 'res://performance_sources/' + pathlib.Path(path).name
    replacements['assets/' + resource.removeprefix('res://')] = pathlib.Path(path).read_bytes()
    replacements['assets/' + path + '.remap'] = ('[remap]\npath="' + resource + '"\n').encode()

with zipfile.ZipFile(source) as old:
    for name in ['AndroidManifest.xml', 'resources.arsc']:
        data = old.read(name)
        for encoding in ['utf-8', 'utf-16-le']:
            data = data.replace(original_id.encode(encoding), test_id.encode(encoding))
        data = data.replace('MANA OORU'.encode('utf-8'), 'MANA PERF'.encode('utf-8'))
        data = data.replace('MANA OORU'.encode('utf-16-le'), 'MANA PERF'.encode('utf-16-le'))
        replacements[name] = data
    args_data = old.read('assets/_cl_')
    count, = struct.unpack_from('<I', args_data)
    args = []; offset = 4
    for _ in range(count):
        length, = struct.unpack_from('<I', args_data, offset); offset += 4
        args.append(args_data[offset:offset+length]); offset += length
    args += [b'--script', b'res://scripts/performance/frame_profile.gd']
    replacements['assets/_cl_'] = struct.pack('<I', len(args)) + b''.join(struct.pack('<I',len(arg))+arg for arg in args)
    manifest = {'package': test_id, 'source_scripts': {path: hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest() for path in scripts}}
    replacements['assets/performance_build.json'] = json.dumps(manifest, indent=2).encode()
    with zipfile.ZipFile(target, 'w', allowZip64=False) as new:
        for entry in old.infolist():
            if entry.filename in replacements:
                continue
            if entry.filename.startswith('META-INF/') and entry.filename.endswith(('.RSA','.DSA','.EC','.SF','.MF')):
                continue
            with old.open(entry) as src, new.open(entry, 'w') as dst:
                shutil.copyfileobj(src, dst, 1024 * 1024)
        for name, data in replacements.items():
            # Android 11+ rejects a compressed resource table even when the
            # archive passes zipalign. Align/sign the completed APK afterwards.
            compression = zipfile.ZIP_STORED if name == 'resources.arsc' else zipfile.ZIP_DEFLATED
            new.writestr(name, data, compress_type=compression)
print('Created', target, 'package', test_id)
