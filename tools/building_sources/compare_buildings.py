import json,math,sys,csv
from pathlib import Path
from collections import Counter
from shapely.geometry import shape,Polygon,LineString,Point,mapping
from shapely.ops import transform
from shapely.strtree import STRtree
import argparse
parser=argparse.ArgumentParser();parser.add_argument('--research-dir',type=Path,required=True);args=parser.parse_args()
D=args.research_dir.resolve();P=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(P/'tools'));import import_ms_buildings as ms
project=lambda g:transform(lambda x,y,z=None:ms.project(x,y),g)
core=json.load(open(P/'data/osm/godavarikhani_core.json'))['elements'];nodes={e['id']:(e['lon'],e['lat']) for e in core if e['type']=='node'}
existing=[];roads=[]
for e in core:
 if e['type']!='way':continue
 coords=[(v['lon'],v['lat']) for v in e.get('geometry',[])] or [nodes[n] for n in e.get('nodes',[]) if n in nodes]
 tags=e.get('tags',{})
 if len(coords)>=4 and tags.get('building'):
  g=project(Polygon(coords))
  if not g.is_valid:g=g.buffer(0)
  if not g.is_empty:existing.append(g)
 if len(coords)>=2 and tags.get('highway'):
  roads.append(project(LineString(coords)).buffer(ms.road_width(tags)*.5+1.0))
for flat in json.load(open(P/'data/buildings/godavarikhani_ms_buildings.json'))['buildings']:
 g=project(Polygon(list(zip(flat[::2],flat[1::2]))))
 if not g.is_valid:g=g.buffer(0)
 if not g.is_empty:existing.append(g)
et=STRtree(existing);rt=STRtree(roads);center=Point(315.6,-334.57)
raw=json.load(open(D/'vidya_nagar_2_overture_building.geojson'))['features'];reasons=Counter();selected=[];local=[];accepted_geoms=[];reviews=[]
raw.sort(key=lambda f:max((v.get('confidence') or 0) for v in f['properties']['sources']),reverse=True)
for f in raw:
 g=project(shape(f['geometry']));props=f['properties'];reason=''
 if g.centroid.distance(center)>450:reason='outside_450m_neighborhood'
 else:
  local.append(f)
  if g.geom_type!='Polygon' or not g.is_valid or len(g.interiors)>0 or g.area<10:reason='unsupported_or_invalid_geometry'
  elif any(g.distance(existing[int(i)])<1.0 for i in et.query(g.buffer(1.0))):reason='existing_building_or_within_1m'
  elif max((v.get('confidence') or 0) for v in props['sources']) < 0.85:reason='below_0.85_ml_confidence'
  elif any(g.intersects(roads[int(i)]) for i in rt.query(g)):reason='road_clearance_conflict'
  elif any(g.distance(a)<1.0 for a in accepted_geoms):reason='overture_candidate_conflict'
  else:reason='accepted_supplement';selected.append(f);accepted_geoms.append(g)
 reasons[reason]+=1
 if reason!='outside_450m_neighborhood':reviews.append({'id':props['id'],'sources':';'.join(s['dataset'] for s in props['sources']),'reason':reason,'area_m2':round(g.area,2),'confidence':max((v.get('confidence') or 0) for v in props['sources']),'height':props['height'],'num_floors':props['num_floors']})
with open(D/'comparison.csv','w') as out:
 w=csv.DictWriter(out,fieldnames=reviews[0].keys());w.writeheader();w.writerows(reviews)
json.dump({'type':'FeatureCollection','metadata':{'source':'Overture Maps','release':'2026-10-21.0','license':'ODbL-1.0','selection':'ML confidence >=0.85; 450m neighborhood; preserve existing buildings with 1m gap; reject roads plus1m; reject internal holes; original geometries'},'features':selected},open(D/'accepted_supplements.geojson','w'),indent=2)
s={'bbox_features':len(raw),'neighborhood_features':len(local),'reasons':dict(reasons),'local_sources':dict(Counter(s['dataset'] for f in local for s in f['properties']['sources'])),'accepted_sources':dict(Counter(s['dataset'] for f in selected for s in f['properties']['sources'])),'height_records':sum(f['properties']['height'] is not None for f in raw),'floor_records':sum(f['properties']['num_floors'] is not None for f in raw),'accepted_count':len(selected),'existing_valid_polygons':len(existing),'selected_area_m2':sum(g.area for g in accepted_geoms)}
json.dump(s,open(D/'comparison_summary.json','w'),indent=2);print(json.dumps(s,indent=2))
