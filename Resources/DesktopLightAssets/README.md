# Desktop Light Assets

These production textures were generated with the built-in image generation
tool using the approved App Icon-style mock as the visual reference.

- `housing-horizontal.png`: compact capsule-shaped satin graphite housing with
  semicircular end caps, a thin bevel, and a smoked matte inset surface.
- `housing-vertical.png`: independently lit vertical housing with the same
  geometry and materials, preserving the macOS-style upper-left light source
  instead of rotating the horizontal lighting and shadow.
- `lamp-neutral.png`: softly frosted grayscale lens with thin charcoal and
  near-black rings, matching the approved App Icon mock.

Both sources were generated on a flat green chroma-key background, processed
with the imagegen skill's `remove_chroma_key.py` helper, cropped to the visible
alpha bounds, and resized with Lanczos sampling. Runtime code supplies lamp
colors, state animation, glow, orientation switching, and proportional scaling.
