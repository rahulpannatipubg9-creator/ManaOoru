# Godavarikhani Godavari River Bridge 3D Digital Twin

**A high-fidelity, real-world metric 3D model of the Godavari River Bridge at Godavarikhani, Telangana, India.**

Procedurally engineered, textured, lit, rendered, and exported in Blender 5.2.3 LTS for simulation, architectural visualization, and real-time game engine integration (Godot 4.x, Unity, Unreal Engine 5).

---

## 1. Geographic & Engineering Overview

* **Location**: Godavari River, between Ramagundam and Godavarikhani (Peddapalli District, Telangana, India).
* **Coordinates**: ~18.75° N, 79.51° E (Northern Telangana Coal Belt / NTPC Ramagundam Super Thermal Power Station corridor).
* **Bridge Typology**: Multi-span prestressed concrete (PSC) I-girder dual-carriageway highway bridge with reinforced cantilever hammerhead pier caps and twin circular pier columns.
* **Total Structure Length**: **1,100.0 meters** (1.1 km).
* **Number of Spans**: **31 spans** of **35.48 meters** center-to-center.
* **Substructure Bents**: **32 pier bents** (30 river bents + 2 abutments).

```
[Ramagundam Abutment] ==== Span 1 ==== [Pier Bent 1] ==== ... ==== [Pier Bent 31] ==== Span 31 ==== [Godavarikhani Abutment]
<------------------------------------------------- 1,100 Meters ------------------------------------------------->
```

---

## 2. Technical Architectural Specifications

| Component | Dimensions / Metric Parameter | Real-World Engineering Details |
| :--- | :--- | :--- |
| **Total Bridge Length** | 1,100.0 m | Spans the seasonal floodplain of the Godavari River. |
| **Carriageway Configuration** | Dual 2-lane carriageways | 2 distinct parallel structures separated by an open central median gap. |
| **Carriageway Width** | 8.50 m per side | Standard 2 lanes + shoulder clearance (IRC:SP:84 specifications). |
| **Central Median Gap** | 3.00 m open space | Continuous open gap between North and South decks with structural cross-struts. |
| **Total Deck Width** | 20.00 m | 8.5m North + 3.0m Gap + 8.5m South. |
| **Deck Clearance Above Water** | 12.00 m | High flood level (HFL) vertical clearance for seasonal monsoon surges. |
| **Deck Thickness** | 0.35 m (350 mm) | Cast-in-place reinforced concrete slab with 2.5% transverse drainage camber. |
| **Asphalt Wearing Course** | 0.08 m (80 mm) | Dense bituminous macadam (DBM) with micro-aggregate roughness and procedural bump. |
| **Girders per Carriageway** | 4 I-girders (8 per span) | Prestressed post-tensioned concrete I-girders (1.80m height, 0.65m top flange, 0.70m bottom bulb). |
| **Transverse Diaphragms** | 3 per span per carriageway | End diaphragm cross-beams over bearings and mid-span stabilizing diaphragms. |
| **Bearings** | 8 per bent | Elastomeric neoprene laminated bearing pads (0.6m x 0.5m x 0.15m) absorbing thermal and seismic expansion. |
| **Pier Columns** | Twin circular shafts | 2.20 m diameter solid cast reinforced concrete columns chamfered at base, 9.0 m tall. |
| **Column Spacing** | 11.50 m center-to-center | Aligned beneath the structural centroid of each respective carriageway. |
| **Tie Beam (Cross-Strut)** | 0.80 m x 1.20 m | Heavy horizontal concrete strut linking twin columns at mid-height (z = 5.0m) for seismic stability. |
| **Pier Cap (Hammerhead)** | 1.40 m depth, cantilevered | Tapered cantilever hammerhead pier cap spanning 20.0m with flared support brackets. |
| **Foundation Footing** | Stepped rectangular footing | 6.0m x 4.0m x 2.0m stepped well cap embedded in the Godavari sandy riverbed. |
| **Expansion Joints** | 30 mm finger plate gaps | Transverse joint plates placed at every pier bent between adjacent spans. |
| **Crash Barrier Parapets** | 0.90 m height | IRC Type-F concrete crash barriers with 0.10m diameter galvanized tubular steel safety rails. |
| **Streetlight Network** | Staggered curved masts | 9.0m tubular steel curved poles with LED luminaire cobra-head fixtures placed at ~35.5m intervals. |
| **Road Markings** | IRC standard | Continuous 0.18m solid white edge lines, 3.0m dash / 6.0m gap centerline dividers. |

---

## 3. Directory Layout & Deliverables

```
Godavarikhani_Bridge_3D/
├── Godavarikhani_Bridge.blend     # Master Blender 5.2.3 project (1.1 km full bridge, lighting, materials, cameras)
├── Godavarikhani_Bridge.glb       # Optimized binary glTF 2.0 asset (615 KB) with PBR materials and collision nodes
├── bridge_config.json             # Master engineering dimension schema
├── generate_bridge.py             # Fully reproducible procedural generation script
├── README.md                      # Comprehensive technical documentation & engine integration guide
└── renders/                       # 8 production 1920x1080 cinematic renders
    ├── Cam_01_Aerial_TopDown.png             # Orthographic-style high aerial view of full 1.1 km river crossing
    ├── Cam_02_Aerial_FrontAlongBridge.png    # Front alignment aerial view (Ramagundam -> Godavarikhani)
    ├── Cam_03_Aerial_Reverse.png             # Reverse alignment aerial view (Godavarikhani -> Ramagundam)
    ├── Cam_04_Drone_Diagonal.png             # 3/4 aerial drone view of piers, caps, and water reflections
    ├── Cam_05_RoadLevel_Driving.png          # First-person driver's eye perspective on North carriageway
    ├── Cam_06_SideElevation_Pillars.png      # Orthogonal side elevation showing pier rhythmic repetition
    ├── Cam_07_UnderDeck_Structural.png       # Under-deck view showing girders, diaphragms, bearings, and pier caps
    └── Cam_08_River_Cinematic.png            # Dramatic riverbank view with granite boulders and sandbars
```

---

## 4. Materials & Shaders (PBR Workflow)

All materials use Blender Principled BSDF nodes engineered to export cleanly to standard glTF PBR metallic-roughness pipelines:

1. **`Concrete_Pier`**: Weathered hydraulic concrete with procedural voronoi/noise watermarks, high-water flood staining, base color `RGB(0.72, 0.70, 0.67)`, roughness 0.78.
2. **`Concrete_Deck`**: Reinforced structural concrete with light mineral aggregate variation, base color `RGB(0.68, 0.67, 0.65)`, roughness 0.72.
3. **`Road_Asphalt`**: Fine bituminous asphalt wearing course with procedural aggregate micro-bump, base color `RGB(0.12, 0.12, 0.13)`, roughness 0.82.
4. **`Road_Marking_White`**: High-contrast retroreflective thermoplastic road paint, base color `RGB(0.95, 0.95, 0.95)`, roughness 0.35.
5. **`Galvanized_Steel`**: Hot-dip galvanized zinc-coated steel for safety rails, base color `RGB(0.78, 0.80, 0.82)`, metallic 0.95, roughness 0.28.
6. **`Streetlight_Paint`**: Weather-resistant protective grey enamel paint, base color `RGB(0.35, 0.37, 0.40)`, metallic 0.40, roughness 0.45.
7. **`LED_Emissive`**: 5500K neutral daylight white luminaire fixture, emission strength 18.0.
8. **`Neoprene_Bearing`**: High-density synthetic elastomer pad, base color `RGB(0.08, 0.08, 0.08)`, roughness 0.90.
9. **`Godavari_Water`**: Tropical freshwater river shader with dual-layer noise waves, subtle sediment turbidity, IOR 1.333, transmission 0.95, base color `RGB(0.08, 0.22, 0.28)`.
10. **`River_Sandbank`**: Dry alluvial silica river sand, base color `RGB(0.82, 0.74, 0.58)`, roughness 0.92.
11. **`Granite_Rock`**: Deccan basalt/granite riverbed boulders, base color `RGB(0.36, 0.34, 0.32)`, roughness 0.85.

---

## 5. Photographic Render Catalog

| Camera ID | Focal Length | Perspective & Description |
| :--- | :--- | :--- |
| **`Cam_01_Aerial_TopDown`** | 32 mm | High-altitude vertical overview (950m elevation) capturing the complete 1.1 km bridge bisecting the Godavari River, sandy shoals, and granite rock formations. |
| **`Cam_02_Aerial_FrontAlongBridge`** | 38 mm | Telephoto front perspective looking directly along the longitudinal axis towards Godavarikhani, highlighting the 3.0m open central gap and mirror-like water reflections. |
| **`Cam_03_Aerial_Reverse`** | 38 mm | Reverse longitudinal alignment looking from the Godavarikhani bank back towards Ramagundam. |
| **`Cam_04_Drone_Diagonal`** | 35 mm | Cinematic 3/4 drone aerial framing the rhythmic pier bents, cantilever hammerhead caps, road deck, and river landscape. |
| **`Cam_05_RoadLevel_Driving`** | 48 mm | First-person driver's eye view (1.25m height) positioned in the travel lane, showcasing asphalt aggregate texture, retroreflective lane striping, crash barriers, and streetlights vanishing into the horizon. |
| **`Cam_06_SideElevation_Pillars`** | 55 mm | Crisp orthogonal profile highlighting the structural clearance, pier columns, tie beams, and substructure rhythm against the water line. |
| **`Cam_07_UnderDeck_Structural`** | 26 mm | Low-angle under-deck structural view looking upward from river level at the 4 prestressed I-girders, transverse diaphragm cross-beams, elastomeric bearings, and cantilever hammerhead bracket. |
| **`Cam_08_River_Cinematic`** | 28 mm | Wide cinematic riverbank composition with Deccan granite boulders in the foreground, rippling water surface, and the full 1,100 m bridge spanning across the background. |

---

## 6. Game Engine Integration Guide (Godot 4.x / Unity / Unreal)

### Godot Engine 4.x

1. **Importing the Asset**:
   * Drag `Godavarikhani_Bridge.glb` into your Godot project (e.g. `res://assets/props/Godavarikhani_Bridge.glb`).
   * In the **Import** dock, set **Root Type** to `Node3D`.
2. **Collision Extraction**:
   * The GLB file includes pre-built simplified collision meshes:
     * `COL_Road_North`: Box collision for North carriageway road surface.
     * `COL_Road_South`: Box collision for South carriageway road surface.
     * `COL_Barrier_0` to `COL_Barrier_3`: Box collisions for the inner and outer crash barriers.
   * In Godot, you can automatically convert any node prefixed with `-col` or `COL_` into a `StaticBody3D` with a `CollisionShape3D` using an import script:
     ```gdscript
     @tool
     extends EditorScenePostImport

     func _post_import(scene):
         _setup_collisions(scene)
         return scene

     func _setup_collisions(node: Node):
         for child in node.get_children():
             if child is MeshInstance3D and child.name.begins_with("COL_"):
                 var static_body = StaticBody3D.new()
                 static_body.name = child.name + "_Static"
                 var shape = child.mesh.create_trimesh_shape()
                 var col_shape = CollisionShape3D.new()
                 col_shape.shape = shape
                 static_body.add_child(col_shape)
                 child.replace_by(static_body)
                 child.free()
             else:
                 _setup_collisions(child)
     ```
3. **Lighting & Water**:
   * Add a `WorldEnvironment` with Godot 4's Physical Sky (`SkyMaterial`) matching sun angle: Pitch 52°, Yaw -48°.
   * Replace the simple plane water mesh with your engine's dynamic river water shader with screen-space reflections (SSR) and depth fading.

### Unity & Unreal Engine

* **Unity (URP / HDRP)**: Import `Godavarikhani_Bridge.glb`. Add `MeshCollider` components to `COL_Road_*` and `COL_Barrier_*`, uncheck `MeshRenderer`.
* **Unreal Engine 5**: Enable **Nanite** on visual meshes (`Bridge_Pillars`, `Bridge_Girders`, `Bridge_Decks`). For collision meshes (`COL_*`), open Static Mesh editor and set **Collision Complexity** to *Use Complex Collision As Simple*.

---

## 7. Performance & Optimization Metrics

* **Geometry Optimization**: Substructure components (pier columns, hammerhead caps, footings) and superstructure girders utilize linked mesh data blocks, ensuring zero memory duplication for the 31 spans.
* **Draw Call Efficiency**: 8 unified PBR materials shared across the entire 1,100 m structure.
* **Apple Silicon M1 (8 GB RAM) Compatibility**:
  * Total memory footprint in Blender: ~180 MB.
  * Blender `.blend` file size: ~450 KB.
  * Binary `.glb` asset size: **615 KB (0.60 MB)**.
  * EEVEE Next raytraced 1080p render time: ~7 to 15 seconds per frame.

## In the ManaOoru world (2026-10-29)

`scripts/world/godavari_bridge_builder.gd` places the bridge at the end of the two OSM trunk carriageways
(ways 817699107 / 1320685007), which `MapData` now keeps whole past the 3 km playable radius. The model's
+X (Godavarikhani) abutment faces the city and the deck pitches about 0.06° so both ends meet the ground.
The model's own river terrain, water, bank trees and rock islands are not used in the world: they buried
the north of the city. The builder makes the valley instead: land from the terrain edge to the abutment,
banks, the river at the model's water level, a north landing with a turnaround loop and a barrier at its
far edge. The decks and the turnaround are in the road network, so the map and GPS route across.
Test: `tests/godavari_bridge_connection_regression.gd`.
