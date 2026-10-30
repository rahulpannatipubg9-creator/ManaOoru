import duckdb,json,time,argparse
from pathlib import Path
parser=argparse.ArgumentParser();parser.add_argument("--out-dir",type=Path,required=True);args=parser.parse_args()
D=args.out_dir.resolve();D.mkdir(parents=True,exist_ok=True)
con=duckdb.connect()
con.execute("INSTALL httpfs; LOAD httpfs; INSTALL spatial; LOAD spatial; SET s3_region='us-west-2'; SET threads=2; SET memory_limit='512MB';")
base='s3://overturemaps-us-west-2/release/2026-10-21.0/theme=buildings/type='
for typ in ['building','building_part']:
 print('Querying',typ,flush=True)
 q=f"""SELECT id, ST_AsGeoJSON(geometry), to_json(sources), height, num_floors, names
 FROM read_parquet('{base}{typ}/*',hive_partitioning=1)
 WHERE bbox.xmin <= 79.5221 AND bbox.xmax >= 79.5106 AND bbox.ymin <= 18.7604 AND bbox.ymax >= 18.7495"""
 try:
  rows=con.execute(q).fetchall()
 except Exception as e:
  (D/(typ+'_error.txt')).write_text(str(e));print(str(e),flush=True);continue
 features=[{'type':'Feature','geometry':json.loads(g),'properties':{'id':i,'sources':json.loads(src) if src else [],'height':h,'num_floors':floors,'names':names}} for i,g,src,h,floors,names in rows]
 out={'type':'FeatureCollection','metadata':{'source':'Overture Maps','release':'2026-10-21.0','license':'ODbL-1.0','bbox':[79.5106,18.7495,79.5221,18.7604]},'features':features}
 (D/('vidya_nagar_2_overture_'+typ+'.geojson')).write_text(json.dumps(out,ensure_ascii=False,indent=2))
 print('Saved',len(features),typ,flush=True)
