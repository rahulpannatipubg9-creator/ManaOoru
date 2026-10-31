---
name: Mana Ooru Settings
description: Landscape mobile and tablet settings surface
colors:
  background: "#101e29"
  control: "#1c3341"
  hover: "#294957"
  selected: "#d3ae62"
  text: "#e1eceb"
  secondary: "#abc4ce"
typography:
  headline:
    fontFamily: Godot default sans
    fontSize: 28px
  body:
    fontFamily: Godot default sans
    fontSize: 18px
rounded:
  control: 6px
spacing:
  small: 8px
  medium: 16px
  large: 24px
---
# Settings design system

## Overview
Scope: the Settings menu only. A quiet, opaque blue-teal work surface separates configuration from the running game. Amber indicates selected navigation and slider progress.

## Colors
Background #101e29; controls #1c3341; hover #294957; selection #d3ae62; body #e1eceb; footer #abc4ce. Selected controls use dark text.

## Typography
Godot's workhorse sans. Category title 28px, application header 24px, body 18px; body becomes 16px below 1050 logical pixels.

## Layout
Persistent category rail and independently scrolling content. Rail 205px, compact 168px. Category buttons 64px, compact 54px. Slider values align right. Save & Return remains outside the scroller. The game is designed for landscape; portrait is not validated.

## Elevation & Depth
Tonal surfaces; no blur or decorative glow. Keyboard focus uses a 2px amber outline.

## Shapes
Six-pixel rounded controls and flat background. Slider handles are authored 26px circles.

## Components
Native Godot buttons, options, sliders and check controls retain their semantics. Popup item separation is 32px. Save errors remain visible in the persistent footer. Navigation only closes the screen after successful saving. Live matches continue but local gameplay input is blocked while Settings is visible.

## Do's and Don'ts
Keep values and units visible. Preserve all existing preference keys and map/activity callbacks. Keep gameplay controls out of this surface. Do not claim FPS targets are guarantees.
