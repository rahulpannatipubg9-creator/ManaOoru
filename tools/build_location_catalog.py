#!/usr/bin/env python3
"""Build offline, source-attributed Phase1 locations; never geocode candidate names."""
import json,math,re,hashlib,argparse
from pathlib import Path
from collections import Counter,defaultdict
P=Path(__file__).resolve().parents[1]
projection=(P/'scripts/map/geo_projection.gd').read_text()
def constant(name):return float(re.search(r'const '+name+r' := ([0-9.]+)',projection)[1])
ORIGIN_LON=constant('ORIGIN_LON');ORIGIN_LAT=constant('ORIGIN_LAT');METERS=constant('METERS_PER_DEGREE_LAT');RADIUS=constant('PLAYABLE_RADIUS_METERS')
def read(path):return json.loads((P/path).read_text())
def norm(s):return re.sub(r'[^\w]+',' ',s.casefold()).strip()
def stable(s):return hashlib.sha256(s.encode()).hexdigest()[:16]
def xy(lon,lat):return ((lon-ORIGIN_LON)*METERS*math.cos(math.radians(ORIGIN_LAT)),-(lat-ORIGIN_LAT)*METERS)
def kind(tags):
 if 'highway' in tags:return ('road' if tags['highway'] not in ['bus_stop','traffic_signals','crossing','street_lamp'] else 'transport',tags['highway'])
 if 'place' in tags:return ('locality',tags['place'])
 if tags.get('entrance'):return ('entrance',tags['entrance'])
 if tags.get('shop'):return ('shop',tags['shop'])
 if tags.get('amenity') in ['restaurant','cafe','fast_food','food_court']:return ('food',tags['amenity'])
 if tags.get('amenity') in ['bus_station','taxi','fuel','parking']:return ('transport',tags['amenity'])
 if 'amenity' in tags:return ('amenity',tags['amenity'])
 for key in ['tourism','leisure','historic','man_made','landuse','building','natural']:
  if key in tags:return ('landmark',tags[key])
 return ('other','unclassified')
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--brief',type=Path);args=parser.parse_args()
 out=P/'data/locations';out.mkdir(exist_ok=True);records={};elements={};sources={};timestamps={}
 for file in ['data/osm/godavarikhani_core.json','data/osm/godavarikhani_features.json','data/local/user_shop_overpass.json']:
  doc=read(file);timestamps[file]=doc.get('osm3s',{}).get('timestamp_osm_base')
  for e in doc['elements']:
   key=(e['type'],e['id'])
   if key not in elements or len(e.get('tags',{}))>len(elements[key].get('tags',{})):elements[key]=e;sources[key]=file
 nodes={i:(e['lon'],e['lat']) for (t,i),e in elements.items() if t=='node'}
 def add(ident,name,cat,sub,lat,lon,status,source,aliases=None,locality=None,street=None,confidence=None,**extra):
  x,z=xy(lon,lat);records[ident]={'id':ident,'name':name,'aliases':aliases or [],'category':cat,'subcategory':sub,'locality':locality,'street':street,'latitude':lat,'longitude':lon,'coordinateStatus':status,'verificationStatus':'mapped_not_field_verified','sources':source,'confidence':confidence,'insidePlayableArea':math.hypot(x,z)<=RADIUS,'modelAssetId':None,'interactionCapabilities':[],'importance':'normal',**extra}
 for (typ,i),e in elements.items():
  tags=e.get('tags',{});name=tags.get('name') or tags.get('name:en') or tags.get('name:te')
  if not name or typ=='relation':continue
  coords=[]
  if typ=='node':coords=[(e['lon'],e['lat'])]
  elif typ=='way':coords=[(p['lon'],p['lat']) for p in e.get('geometry',[])] or [nodes[n] for n in e.get('nodes',[]) if n in nodes]
  if not coords:continue
  if len(coords)>1 and coords[0]==coords[-1]:coords=coords[:-1]
  lon=sum(p[0] for p in coords)/len(coords);lat=sum(p[1] for p in coords)/len(coords)
  cat,sub=kind(tags);aliases=[]
  for key in ['name:en','name:te','alt_name','loc_name','old_name','short_name']:
   aliases.extend(v.strip() for v in tags.get(key,'').split(';') if v.strip() and v.strip()!=name)
  add(f'osm/{typ}/{i}',name,cat,sub,lat,lon,'source_point' if typ=='node' else 'source_geometry_representative',
   [{'dataset':'OpenStreetMap','recordId':f'{typ}/{i}','file':sources[(typ,i)],'license':'ODbL-1.0','snapshot':timestamps[sources[(typ,i)]]}],aliases,tags.get('addr:suburb'),tags.get('addr:street'),geometryReference=f'osm/{typ}/{i}',reviewFlags=[tags['fixme']] if tags.get('fixme') else [],rawClassification={k:v for k,v in tags.items() if k in ['place','highway','amenity','shop','tourism','entrance','man_made','office','healthcare']})
  if tags.get('fixme'):records[f'osm/{typ}/{i}']['verificationStatus']='needs_review'
 # Preserve attributed place evidence, never silently treat confidence as survey accuracy.
 for row in read('data/places/godavarikhani_places.json')['places']:
  lon,lat=row['lon'],row['lat'];name=row['name'];category=row.get('category','');source=row.get('source','')
  # Do not duplicate an existing OSM-derived label at the same location.
  if any(norm(r['name'])==norm(name) and math.dist(xy(lon,lat),xy(r['longitude'],r['latitude']))<25 for r in records.values()):continue
  if '=' in category:cat,sub=kind(dict([category.split('=',1)]))
  elif category in ['restaurant','cafe','fast_food_restaurant']:cat,sub='food',category
  elif category.endswith('_store') or category in ['shopping','telecommunications_service']:cat,sub='shop',category
  elif category in ['bus_station','bus_stop','gas_station']:cat,sub='transport',category
  else:cat,sub='amenity',category
  ident='catalog/place/'+stable('|'.join([source,name,str(lat),str(lon)]))
  add(ident,name,cat,sub,lat,lon,'source_catalog_point',[{'dataset':source,'file':'data/places/godavarikhani_places.json','recordId':None,'license':row.get('license'),'note':'Upstream ID absent in existing derived catalog; identity not independently confirmed'}],confidence=row.get('confidence'))
 # Explicit local pins retain their source but aren't called field verified.
 for row in read('data/local/chowrasta_exact_pins.json')['pins']:
  if any(norm(r['name'])==norm(row['name']) and math.dist(xy(row['lon'],row['lat']),xy(r['longitude'],r['latitude']))<25 for r in records.values()):continue
  cat,sub=kind(dict([row.get('category','amenity=theatre').split('=',1)])) if '=' in row.get('category','') else ('landmark',row.get('category','other'))
  add('local/pin/'+stable(row['name']),row['name'],cat,sub,row['lat'],row['lon'],'local_source_assertion',[{'dataset':row.get('source'),'file':'data/local/chowrasta_exact_pins.json','license':'ODbL-1.0','recordId':None}])
 candidate_path=out/'candidate_locations.json'
 if args.brief:
  text=args.brief.read_text();specs=[('junction','### Priority junctions','Some names may'),('locality','### Central Godavarikhani','### Singareni and surrounding areas'),('locality','### Singareni and surrounding areas','Keep separate administrative'),('road','# 6. IMPORTANT ROAD NETWORK','These are candidate road names'),('shop','### Candidate recognizable shop names','Also research recognizable'),('food','# 8. TIFFIN CENTERS','Implement appropriate environment'),('landmark','# 9. IMPORTANT LANDMARKS','# 10. MAP AND MINIMAP')]
  candidates=[]
  for cat,start,end in specs:
   part=text.split(start,1)[1].split(end,1)[0]
   for name in re.findall(r'^(?:- |\d+\. )(.+)$',part,re.M):
    if name.startswith(('Other verified','Schools and','Post offices','Police stations','Banks','Public parks','Major auto','Important bus')):continue
    candidates.append({'id':'candidate/'+cat+'/'+stable(norm(name)),'name':name,'category':cat,'locality':None,'latitude':None,'longitude':None,'coordinateStatus':'unverified','verificationStatus':'unverified','source':'User master development brief; candidate name only','modelAssetId':None,'interactionCapabilities':[],'importance':'high' if cat=='junction' else 'normal'})
  candidate_path.write_text(json.dumps({'note':'Candidates are a research backlog, not located map features. No coordinates inferred.','locations':candidates},ensure_ascii=False,indent=2))
 candidates=json.loads(candidate_path.read_text())['locations']
 for c in candidates:c['possibleSourceMatches']=[r['id'] for r in records.values() if norm(c['name']) in [norm(r['name'])]+[norm(a) for a in r['aliases']]]
 candidate_path.write_text(json.dumps({'note':'Exact-name source matches are review leads only; coordinates remain null until identity is reviewed.','locations':candidates},ensure_ascii=False,indent=2))
 # Topology inventory: shared OSM node connectivity, never proximity connections.
 neighbors=defaultdict(set);ways=defaultdict(set);road_names=defaultdict(set)
 for (typ,i),e in elements.items():
  if typ!='way' or not e.get('tags',{}).get('highway'):continue
  ids=e.get('nodes',[])
  for a,b in zip(ids,ids[1:]):
   if a in nodes and b in nodes:
    neighbors[a].add(b);neighbors[b].add(a);ways[a].add(i);ways[b].add(i)
    for n in [a,b]:
     if e.get('tags',{}).get('name'):road_names[n].add(e['tags']['name'])
 junctions=[]
 for i,adj in sorted(neighbors.items()):
  lon,lat=nodes[i]
  if len(adj)<3 or math.hypot(*xy(lon,lat))>RADIUS:continue
  tags=elements.get(('node',i),{}).get('tags',{})
  junctions.append({'id':f'osm/junction-node/{i}','name':tags.get('name'),'latitude':lat,'longitude':lon,'branchCount':len(adj),'neighborNodeIds':sorted(adj),'roadWayIds':sorted(ways[i]),'roadNames':sorted(road_names[i]),'mappedTrafficSignal':tags.get('highway')=='traffic_signals','verificationStatus':'source_topology_not_field_verified'})
 (out/'junction_topology.json').write_text(json.dumps({'source':'OpenStreetMap bundled extracts; ODbL-1.0','note':'Degree of shared road nodes, not surveyed lane count or official named junctions. No geometric crossing is connected without a shared node.','junctions':junctions},ensure_ascii=False,indent=2))
 output={'schemaVersion':1,'origin':{'latitude':ORIGIN_LAT,'longitude':ORIGIN_LON,'radiusMeters':RADIUS},'note':'Mapped source evidence is not independent field verification. Representative coordinates are not entrances. Candidate names never create map coordinates.','inputHashes':{p:hashlib.sha256((P/p).read_bytes()).hexdigest() for p in timestamps},'locations':sorted(records.values(),key=lambda r:r['id'])}
 (out/'source_locations.json').write_text(json.dumps(output,ensure_ascii=False,indent=2))
 summary={'sourceLocations':len(records),'insidePlayable':sum(r['insidePlayableArea'] for r in records.values()),'candidates':len(candidates),'candidatesWithExactNameLeads':sum(bool(c['possibleSourceMatches']) for c in candidates),'junctionNodes':len(junctions),'categories':dict(Counter(r['category'] for r in records.values()))}
 (P/'outputs/phase1/location_inventory.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
if __name__=='__main__':main()
