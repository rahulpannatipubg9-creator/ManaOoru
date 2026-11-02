# Vehicle entry, Bullet and finish corrections

Cars visibly open and close a driver door, with normal, scissor or butterfly motion. The visible character bends through a doorway waypoint, sits at the configured controls and reverses the sequence when exiting. Bikes use an animated leg-over mount/dismount, keep door sounds disabled, and set feet on the footrests.

The Bullet now has its own assisted motorcycle controller: rear drive, five forward ratios, primary/final reduction, braking without powered reverse, bank assistance, rotating visible wheels, steering forks/handlebars, a parked stand and release on entry. It uses an original clean Bullet-style mesh at metric scale; the problematic scanned source remains untouched. The clean visual is a game model, not a factory CAD replica. Torque/mass targets use the Royal Enfield Bullet 350 technical sheet, with game-tuned suspension and balance assistance.

Reference: https://www.royalenfield.com/content/dam/royal-enfield/bullet/eu-bullet/specifications/royal-enfield-bullet-350-technical-specifications-english.pdf

Exterior color assignments are stored in data/vehicles/vehicle_finishes.json. Driver fits were adjusted for Mercedes sedan, Supra, XC40, Mach 40 and Can-Am after both-side rendered review. Neon placeholder wheel colors are replaced with graphite without changing brake/caliper textures.

Door panels on merged source models are fitted by geometric region, not individually authored factory door meshes. Exact door seams, interior door trim and some source materials still need model-by-model art refinement. Runtime door construction is cached on each vehicle after first use.

Validation evidence is in outputs/vehicle_rigs. Render entry/exit using tools/capture_vehicle_entry_animation.gd; append -- bullet to inspect only the motorcycle. Build the clean model with tools/vehicle_rigging/build_clean_bullet.py, then pack its approved GLB with tools/vehicle_rigging/pack_bullet.gd.

## Final verification

- Bullet motorcycle regression: PASS (accelerates, translates, tire contact, balance and parked audio).
- Visible car and bike entry regression: PASS on Porsche 911, BMW i8 and Bullet. Checks actual moving door geometry, open/close phases, visible bend, seat/exit completion and bike leg swing without door sounds. Rider wrists measured at approximately 1.2cm and 2.8cm from the grips; the test requires under 5cm.
- Movement regression: PASS after adding simulation-space passenger attachment for slow render frames and stand parking for the Bullet.
- Character stance/reactions: 15 checks, zero failures. Character model/walk-cycle and arm-hang regressions: PASS.
- Weapon-switch regression: PASS after rerunning without competing world tests.
- Clean motorcycle geometry QA: all four assemblies pass, 37,236 triangles total. Accepted warnings are planar cylinder-cap n-gons and non-grounded assembly origins; the wheel meshes are intentionally centred on their axles, and all final geometry is assembled at the correct ground position. Solid PBR materials do not require UV textures. The original source fleet's previously documented mesh defects remain separate.

The clean motorcycle is an original Bullet-style game model rather than the scanned source or factory CAD. Its editable source is work/vehicle_rigs/bullet_clean.blend; the runtime resource is assets/models/vehicles/royal_enfield_bullet/bullet_motorcycle.scn. The source scan remains untouched.
