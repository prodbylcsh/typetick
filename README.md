# Typetick

An offline, native macOS notes app where every note is typed on a mechanical typewriter.

The window shows a fixed, seated view of the machine on a desk. As you type on the Mac keyboard the matching key goes down, its typebar swings up and strikes the sheet through the ribbon, the paper shivers from the blow and the carriage escapes one tooth. Everything that moves has its own sound, synthesized live from the parts actually fitted to the machine.

## What is on the machine

| Mechanism | What it does in the app |
| --- | --- |
| Keys + typebars | One key lever and one typebar per character (45 + function keys). Typebars fan out on a segment and swing to a single printing point. |
| Escapement + carriage | Each strike moves the carriage one tooth (pica or elite, set by the carriage variant). Backspace, space, tab and return move it with their own motion and sound. |
| Platen + knobs | Line feed, half-line rolls (⌥↑/⌥↓) and free rolling with ratchet detents. The sheet wraps around the platen and follows it. |
| Paper bail + release lever | Lift and drop when a sheet is fed or ejected. |
| Return lever | Line space then carriage return, with a 1 / 1½ / 2 line selector (some variants: 1 / 2 / 3, or an electric power return). |
| Margin rack | Left/right margin stops and tab stops that you can set from the keyboard or the HUD. |
| Bell | Rings a few columns before the right margin (offset and sound set by the bell variant). |
| Ribbon | Spools, the visible ribbon band and the vibrator that lifts it for each strike. Two-color ribbons switch with ⌥⌘R. |
| Correction tape | Delete backs up one column and strikes the same character again through cover-up (or lift-off) tape. The patch is a slightly different white than the paper. |
| Recorder | The mechanical clipboard bolted to the right side (see below). |

### The mechanical clipboard (Recorder)

There is no RECORD switch: the recorder's **journal tape is endless and always punching**. Every keystroke is punched as UTF-8 frames on 8 data tracks plus a sprocket track.

* **Select** with a drag on the sheet, double click (word), triple click (line) or ⇧ + arrows. The selection shows as a tinted celluloid strip laid on the paper.
* **Copy** (⌃C or ⌘C): the reader sled rewinds the journal to the selection while a duplicating punch copies those frames onto a short **clip loop**. The text also goes to the macOS pasteboard.
* **Paste** (⌃V or ⌘V): a spring motor pulls the clip loop over the sensing needles. Each needle that falls through a hole trips the latch of a typebar, which strikes and escapes the carriage, at the recorder's own speed. The spring is wound by throwing the carriage on every return; if it runs down mid-paste, the winding key turns and the paste continues. Text copied in another app arrives "over the teleprinter line" and is punched onto the clip loop first.
* **Cut** (⌃X or ⌘X): Copy, then the carriage and platen walk back over every selected character and the machine strikes it again through the correction tape. Typed text never reflows: it's paper.

Esc or ⌘. stops the recorder.

## Customizing (Workshop, ⇧⌘K)

* **Machine**: 12 component kinds × 8 variants each (96 distinct models). Each variant is its own geometry, materials, sound profile, animation timing and mechanics, for example:
  * carriage shift vs. segment shift
  * pica vs. elite pitch
  * an electric return motor
  * a 14-inch ledger carriage
  * knob ratchets from 1 to 8 detents per line
  * lift-off vs. cover-up correction
  * bell partials, from a classic dome or two-tone gong to a cowbell, a singing bowl or a coil gong
  * recorders that store on paper tape, a pinned drum, a cam bank, Jacquard cards, a chronograph loop, a pneumatic tube or a music box that plucks a comb while it pastes

  The preview is a turntable 3D viewer.
* **Paper**: 10 color families × 5 shades (white to black), 10 finishes (matte, vellum, laid, linen, cotton, glossy, onionskin, recycled, watercolor, parchment), sizes, and hardness, tooth, fibers, wrinkles, age and weight. Hardness changes how deep the type bites and how much ink spreads. New sheets use the new paper; sheets already typed keep theirs.
* **Ink & ribbon**:
  * kinds: fabric, carbon, pearlescent, metallic foil, glitter flakes, iridescent, fluorescent and chalk
  * settings: color and second color, bleed, density, unevenness, ribbon wear, halo and sheen
  * metallic and pearl inks are written into roughness and metalness maps, so they catch the lamp in 3D
* **Typeface**: system typewriter and monospaced faces, sized to the escapement pitch, with baseline and tilt wander.
* **Desk**: 13 procedurally textured surfaces (walnut, oak, cherry, ebony, pine, marble, slate, leather, felt, linoleum, steel, concrete, glass) with tint, grain, gloss and wear.
* **Lighting**: time of day, window light, 7 lamp types, color temperature or neon color, brightness, ambient, shadows. Image-based lighting is generated from the same settings.

The writing view never orbits. *Seat* (Close, Seated, Whole Desk) picks one of three fixed camera positions.

## 3D format: why USD

Components are **USD**: `.usdz` in the app bundle, with human-readable `.usda` sources from the generator. USD is the native 3D interchange format on Apple platforms:
* RealityKit loads it directly with physically based materials.
* Reality Composer Pro, Blender, Houdini and Maya can edit it.
* Text `.usda` diffs cleanly in git.
* `.usdz` is a compact single file.

Every component file follows a small contract the app relies on:

* Top-level prims are **parts** (`Key`, `SpaceBar`, `pivot_Platen`, `pivot_Bail`...). Parts named `pivot_*` are animated; their origin is the hinge or axle.
* Mesh names carry their **material role** after a double underscore: `Body__paint`, `Stem__steel`, `Top__keyTop` (key legend, 0..1 UVs), `Medium__medium` (recorder tape/drum, frames along U or V), `Wound__ribbon` (spool winding that grows and shrinks).
* `manifest.json` per kind lists each variant with `mechanics` (anchors, pitch, detents, timings...), `sound` (pitch, body, brightness, decay, ring) and `animation` (speed, overshoot), plus a `palette` of role colors.

### Editing or adding components

* Built-in library: `Sources/TypetickScene/Resources/Components/<kind>/` (`.usdz` + `manifest.json`).
* Generator: `Tools/ModelForge` (Python + `usd-core`). `python3 Tools/ModelForge/build.py [kind ...]` rebuilds the library and writes `.usda` sources to `Tools/ModelForge/out/`.
* Software preview without a GPU:
  * `python3 Tools/ModelForge/preview.py sheet out.png` renders a contact sheet of all 96 variants.
  * `python3 Tools/ModelForge/preview.py machine out.png carriage=wide_ledger keys=hex_brass` renders an assembled machine with the same layout rules as the app.
* Your own components: put a `manifest.json` and model files in `~/Library/Application Support/Typetick/Components/<kind>/` (Workshop → *Custom Components Folder*). A variant with an existing id replaces the built-in one; new ids show up as extra choices. Click *Reload Library* to pick up changes.

## Building

Requirements: macOS 15+, Xcode 16+ (Swift 6 toolchain; the package builds in Swift 5 language mode).

Build and run straight from SwiftPM:

```bash
swift run Typetick
```

Build a proper `Typetick.app` bundle in `build/`:

```bash
Scripts/build-app.sh
```

Or generate an Xcode project with XcodeGen (`brew install xcodegen` first):

```bash
xcodegen
```

Then open the generated `Typetick.xcodeproj`.

Run the tests (mechanics, margins, correction, clipboard, reading text back off the page):

```bash
swift test
```

## Architecture

```
TypetickCore    pure Swift: TypewriterMachine (state machine -> timed MachineEvents),
                Sheet/Strike/Note documents, SheetText (reads text back off the page),
                keyboard layout, styles (paper, ink, typeface, desk, environment)
TypetickAudio   SoundSynth (modal resonators + shaped noise), SoundEngine (AVAudioEngine
                voice pool, stereo carriage panning), SoundDirector (events -> sounds)
TypetickScene   ComponentLibrary (manifests + user overrides), MachineLayout (geometry),
                MachineRig (assembly, Channels, event timeline), PaperRenderer (CoreGraphics
                color/height/roughness/metal layers), DynamicTexture (LowLevelTexture with
                partial uploads + mipmaps), Stage (ARView, desk, lamps, IBL, fixed cameras)
Typetick        SwiftUI app: notes sidebar, stage + HUD, reader, Workshop, settings
```

The sheet is never a text field. What is stored is a list of **strikes** (character, column, baseline, pressure, style, kind). The text you see in search, the reader and copy is read back off the paper by `SheetText`, cell by cell, so overstrikes compose and corrections remove glyphs.

Paper is rendered at 300 dpi by default (200 or 400 in Settings). Only the changed region is uploaded per strike, and mipmaps plus 16× anisotropic filtering keep the type sharp at the platen angle.

## Status

This is the first full implementation. It was written without access to a Mac:
* the Swift sources passed a syntax check but have **not yet been compiled**
* the 3D library was generated and checked with Pixar USD and a software renderer

Expect a first round of compile fixes. The areas most likely to need small adjustments:
* RealityKit API details: `LowLevelTexture`, `TextureResource(from:)`, `ARView.ray(through:)`
* fine tuning of anchor positions

If the sheet renders upside down on your OS build:

```bash
defaults write app.typetick.Typetick TypetickFlipPaperV -bool YES
```
