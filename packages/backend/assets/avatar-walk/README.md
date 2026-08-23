# Avatar walk motion sources

These animation-only assets are loaded by the avatar walk atlas baker. The
user's VRM stays in the browser; only these static motion files are fetched
from the Misskey server.

## `kaykit-medium-simulation.glb`

- Source: KayKit Character Animations by Kay Lousberg
  - https://kaylousberg.itch.io/kaykit-character-animations
- Browser-ready conversion:
  - https://github.com/sketchpunklabs/kaykit_char/blob/main/res/anim/Med_Simulation.glb
- License: CC0 1.0
- Used clips: `Sit_Chair_Down`, `Waving`, and `Cheering`

## `cmu-113-02-bow.bvh`

- Source: Carnegie Mellon University Graphics Lab Motion Capture Database,
  subject 113, motion 02 (`Bow`)
  - https://mocap.cs.cmu.edu/
- BVH conversion:
  - https://github.com/una-dinosauria/cmu-mocap/blob/master/data/113/113_02.bvh
- Usage: CMU places no restrictions on use of the original dataset, and the
  BVH converter places no additional restrictions on the conversion.

The data used in this project was obtained from mocap.cs.cmu.edu. The database
was created with funding from NSF EIA-0196217.
