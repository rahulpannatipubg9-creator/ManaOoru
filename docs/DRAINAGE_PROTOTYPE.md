# Drainage prototype

A standalone synthetic layout demonstrates an open channel, a covered box crossing beneath a road, and raised cutaway examples of small open and covered drains. It is not a representation of Godavarikhani. All dimensions are illustrative. No TGRAC data, geographic routes, inferred drainage, or external assets were used.

Run from the project root:

```sh
godot --path . scenes/tests/drainage_demo.tscn
```

Drag left mouse to orbit and use the wheel to zoom. This is an orbit-camera demonstration, not a player-controlled city level. The main scene and city generation remain unchanged.

`drainage_channel.gd` builds simple concrete beds, side walls, optional covers and a static water surface from supplied 3D points and explicit dimensions. Concrete has box collision; water does not. Segment ends are independent, so curved alignments need joint treatment before production use. This component does not excavate terrain, load GeoJSON, infer connections, assign flow direction or simulate hydraulics. The demo uses a straight channel with separate ground strips to expose its interior. It is a small prototype, not an optimized city-wide rendering system.

Verified with Godot 4.7.2:

- Headless demo startup: passed without script errors.
- Rendered on Apple M1 OpenGL compatibility renderer; preview captured and inspected.
- `godot --headless --path . --script tests/drainage_regression.gd`: passed open-bed, non-solid water, road crossing and covered-lid collision checks.

Full movement/vehicle regression was not run: no existing gameplay, movement, camera or city-world code was changed. Future integration into gameplay must run required movement regression and validate collision/camera behavior.

Preview: `outputs/drainage_demo/preview.png`.

Future city placement requires verified independently licensed route geometry. The current OSM query returned no drainage objects in the target area. Synthetic test points must never be exported as real geographic records or inserted into the city as surveyed drainage.
