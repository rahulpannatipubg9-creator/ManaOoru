# Virat

Source: user supplied Downloads/Virat.glb, 2026-11-01. Source author and redistribution licence are unverified; do not publish the asset until supplied.

The downloaded 58-joint skin is fitted in bind space to the existing Mixamo gameplay skeleton. Keep the original download unchanged. The existing gameplay animations and procedural weapon/vehicle posing remain authoritative.

Validation and captures are recorded in the Virat integration report.

## Colour finish
Natural skin, dark hair, navy top, charcoal trousers and dark shoes were authored locally at the user's request. These are simple vertex colours, not a recovered or photorealistic source texture. Keep COLOR_0 and explicitly enable vertex_color_use_as_albedo on the duplicated Godot material. One material is retained. Normal-map strength is 0.35. Build: tools/virat_character/build_virat.py.

Facial joints have incompatible rest pivots despite shared names in the two rigs. Exclude Jaw, LeftEye and RightEye from body-rig matching and map these and tongue weights through the original Head ancestor for both bind transforms and merged weights. Do not map a jaw transform directly to the head centre, or create duplicate Head.001 weight groups. Facial animation is not enabled by this body rig.

Preserve the original facial topology when reducing the body mesh. Final budget is 29,992 triangles; the face is rigidly head-bound. Material colours are an approximation and do not supply detailed eye/face textures.
