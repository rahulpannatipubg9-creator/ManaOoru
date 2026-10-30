import pathlib, hashlib, json, subprocess, time, os
ROOT=pathlib.Path(__file__).resolve().parents[2]
STATE=ROOT/'data/asset_sync'; STATE.mkdir(exist_ok=True)
manifest_path=STATE/'manifest.json'
manifest=json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
source_root=pathlib.Path('/Users/rahulpannati/Documents/New project')
sources=list(source_root.glob('*/*.blend'))+list(pathlib.Path('/Users/rahulpannati/Downloads').glob('*.blend'))
changed=[]
for source in sorted(sources):
 digest=hashlib.sha256(source.read_bytes()).hexdigest(); key=str(source)
 old=manifest.get(key,{})
 if old.get('sha256')==digest and old.get('status') in ('exported_review','license_review'): continue
 entry={'sha256':digest,'source':key,'checked_at':time.time()}
 if source.parent.parent!=source_root or 'character' in source.parent.name.lower():
  entry.update(status='license_review',note='Downloaded asset: verify provenance and existing integration before automated reuse.')
  manifest[key]=entry; continue
 slug=source.stem.lower(); out=ROOT/'assets/models/city_buildings'/slug; out.mkdir(parents=True,exist_ok=True)
 glb=out/(slug+'.glb'); meta=out/'metadata.json'
 cmd=['/Applications/Blender.app/Contents/MacOS/Blender','--background','--factory-startup','--disable-autoexec',str(source),'--python',str(ROOT/'tools/asset_sync/export_building.py'),'--',str(glb),str(meta)]
 log=STATE/(slug+'.log')
 with log.open('w') as f: result=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,timeout=180)
 if result.returncode or not glb.exists(): entry.update(status='failed',log=str(log))
 else:
  entry.update(status='exported_review',output=str(glb),provenance='User-created building model; photographic reference rights not independently verified',metadata=json.loads(meta.read_text()))
  changed.append(slug)
 manifest[key]=entry
 manifest_path.write_text(json.dumps(manifest,indent=2))
# Standalone Godot review scene: no invented city placements or gameplay modifications.
entries=[v for v in manifest.values() if v.get('status')=='exported_review']
lines=['[gd_scene load_steps='+str(len(entries)+1)+' format=3]','']
for i,e in enumerate(entries): lines.append('[ext_resource type="PackedScene" path="res://'+str(pathlib.Path(e['output']).relative_to(ROOT))+'" id="'+str(i+1)+'"]')
lines+=['','[node name="ImportedBuildingsReview" type="Node3D"]']
for i,e in enumerate(entries):
 lines+=['','[node name="'+pathlib.Path(e['output']).stem+'" parent="." instance=ExtResource("'+str(i+1)+'")]','position = Vector3('+str((i%3)*90)+', 0, '+str((i//3)*100)+')']
review=ROOT/'scenes/world/imported_buildings_review.tscn'; review.write_text('\n'.join(lines)+'\n')
report={'changed':changed,'review_scene':str(review),'exports':len(entries),'license_review':[k for k,v in manifest.items() if v.get('status')=='license_review'],'failures':[k for k,v in manifest.items() if v.get('status')=='failed'],'not_tested':['real-world placement','collision','mobile frame rate','texture fidelity against photos']}
(STATE/'report.json').write_text(json.dumps(report,indent=2)); print(json.dumps(report,indent=2))
