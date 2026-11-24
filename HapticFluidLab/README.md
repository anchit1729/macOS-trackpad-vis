# Haptic Fluid Lab

A macOS PIC–FLIP fluid study with 2D and 3D views. Move the pointer over water to feel motion or pressure through the trackpad.

## Run

1. Install Xcode and XcodeGen.
2. Run `xcodegen generate` in this directory.
3. Open `HapticFluidLab.xcodeproj` in Xcode.
4. Build the **Release** configuration for the intended 30 fps experience.
5. Turn on **Trackpad haptics** in the app.

Command-line build:

```sh
xcodegen generate
xcodebuild -project HapticFluidLab.xcodeproj -scheme HapticFluidLab \
  -configuration Release -derivedDataPath /tmp/haptic-fluid-derived \
  build CODE_SIGNING_ALLOWED=NO
open /tmp/haptic-fluid-derived/Build/Products/Release/HapticFluidLab.app
```

## Scenes

- **Dam break:** A column falls and spreads along the floor.
- **Colliding streams:** Two moving blocks meet.
- **Vortex:** A rotating pool settles into a current.

Select **2D** or **3D**. Pause, reset, or change the PIC–FLIP blend. The 2D view lets you drag to stir the water. A linked-cell spacing pass keeps its grains evenly separated after advection. It can show the grid and flow vectors. In 3D, drag to orbit, scroll or pinch to zoom, and use two fingers to pan. **Reset camera** restores the raised starting view. The 3D scene has a black background and no skybox.

The footer shows completed simulation frames per second. In 3D, it also shows the surface triangle count.

## How each frame works

1. Place particles on a staggered velocity grid. The 2D grid is 48 × 36. The 3D grid is 24 × 16 × 16.
2. Apply gravity to vertical grid velocity.
3. Fill nearby empty grid faces and set wall velocity to zero.
4. Solve pressure with 40 red-black SOR passes. Subtract the pressure gradient.
5. Sample the projected grid. PIC takes grid velocity. FLIP adds the grid velocity change to each particle.
6. Blend PIC and FLIP. Move particles and keep them inside the tank.

Each solver runs in a Swift actor. The main thread draws immutable frame snapshots. This keeps pointer input and drawing responsive. The small grids do not benefit from per-row dispatch work. APIC would add affine particle state and transfer cost; the PIC–FLIP blend meets the frame target.

## 3D surface and shader

Particles contribute smooth, compact kernels to a display grid finer than the solver grid. A three-axis blur smooths the density. The tank boundary becomes an air layer so the mesh closes. Marching tetrahedra extract the surface; density gradients give smooth normals. SceneKit draws the mesh with two lights, a dark blue water material, and a Fresnel rim shader. A dark floor and thin tank edges give depth cues.

## Haptic mapping

Select **Motion** or **Pressure** in the **Feel** control. Motion uses a distance-weighted mean of `½ × speed²` near the pointer. Pressure uses the absolute gauge pressure from nearby fluid cells. In 3D, the pointer ray hits the visible water surface; the sample moves slightly inward to reach the fluid.

A square-root curve maps the selected value to motor strength. Each 12 ms frame has three frequency layers. Motion has a 125–270 Hz body, a 440–800 Hz moving voice, and a 1,250–2,200 Hz spray accent. Pressure has a 90–180 Hz body, a 250–360 Hz compression voice, and a short 850–1,450 Hz crest. Their swells, rates, and accents differ, so the two modes feel distinct. The strength control caps motor level at 0.55. A pointer outside the water stops output.

The waveform bridge uses Apple's private `MultitouchSupport` interface. It follows the MIT-licensed [nospeaker example](https://github.com/os6/nospeaker); see [NOSPEAKER-LICENSE.txt](NOSPEAKER-LICENSE.txt). This interface may change with macOS updates. If it cannot open, the app uses occasional public AppKit taps. It does not replace system trackpad behaviour.

## Performance and checks

On the development MacBook Air with macOS 27.0.1, both Release views showed **30 fps** in visual checks. A 30-frame 3D solver-plus-mesher benchmark took about 207–218 ms total, or about 6.9–7.3 ms per frame. Actual speed depends on the machine, other open apps, and window size. The app skips a simulation tick if the previous tick is still running; it does not queue old frames.

Run tests with:

```sh
xcodebuild -project HapticFluidLab.xcodeproj -scheme HapticFluidLab \
  -configuration Debug -derivedDataPath /tmp/haptic-fluid-derived \
  test CODE_SIGNING_ALLOWED=NO
```

The tests check both solvers, pressure projection, particle bounds and spacing, surface meshing, haptic modes, and actor frame handoff.

## References

- Bridson, *Fluid Simulation for Computer Graphics*: https://www.cs.ubc.ca/~rbridson/fluidsimulation/
- Boyd and Bridson, *MultiFLIP for Energetic Two-Phase Fluid Simulation*: https://www.cs.ubc.ca/~rbridson/docs/boyd-tog2011-multiflip.pdf
- Apple, *SceneKit geometry*: https://developer.apple.com/documentation/scenekit/scngeometry
- Apple, *SceneKit camera control*: https://developer.apple.com/documentation/scenekit/scnview/allowscameracontrol
