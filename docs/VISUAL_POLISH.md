# Visual consistency pass

Implemented by three parallel agents, then integrated in the existing project.

## Changes

- Main daylight: reduced exposure (.85 to .78), neutralized fill/sun, softened sunlight and reduced clear fog. Dynamic CityEnvironment has matching restrained day/rain settings and preserved night exposure. The main scene currently declares CityLife but does not initialize it; this pass does not enable it.
- Buildings: deterministic paint pigment and window bay/proportion variation, clearer cement base band, bounded texture brightness to remove overbright peeling paint. Existing batching, mapped heights, footprints and storefront allocation remain intact. No new assets or draw calls added for facade variety.
- Ambient pedestrians: lowest animated capsule sole follows the rendered support surface. Samplers now assigned in the normal world and local-activity spawn paths, independently of optional CityCommunity. Roads use the road collision surface, bare terrain the visible DEM−0.20 surface, with shoulder/storefront/platform support.
- Ambient traffic: terrain sampled at the current lane point instead of interpolating sparse route endpoint heights. Vehicles remain upright; this does not add suspension or wheel-by-wheel slope alignment.

## Verification

Passed required movement regression after the final sampler wiring, camera first/third-person regression, chase-camera regression, ambient contact regression, traffic movement/signal checks, storefront allocation and deterministic facade checks. Agents also performed lighting state assertions and an isolated actual OpenGL shader render. Chase-camera and traffic-signal tests reported shutdown resource-leak warnings despite passing assertions; not counted as clean exits.

Actual Apple M1 OpenGL city renders inspected: daylight streets/facades, evening and final normal-scene street. Final screenshot: `outputs/visual_polish/final_street.png`. Reproduce from project root:

```sh
godot --path . --script tools/capture_visual_polish.gd -- --no-drainage --city-life-no-save
```

The separate CityEnvironment preview harness explicitly instantiated that otherwise dormant controller. Day and evening captures completed. Night/rain state assertions passed, but full-city night/rain image capture stalled and was stopped; these views are not visually approved. No controlled same-view pre-change baseline was captured, so images are current previews, not a quantified before/after benchmark. No FPS/mobile-device benchmark was performed. Another game instance was running during capture, so capture duration is not a performance result.

## Limits

This is a visual consistency pass, not a complete city art overhaul. Large empty parcels were not filled with invented buildings or businesses. Unique authored storefront meshes, parcel detail, full character redesign, precise car wheel support on slopes, distant terrain transitions and broader city optimization remain separate work. Drainage was not changed or reintroduced; capture disabled existing procedural drainage. Restart the currently running game to load these source changes.
