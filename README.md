# TypeTick

An offline mechanical writing studio with an English interface. The macOS release is a universal native Godot 4.6.3 application for Apple Silicon and Intel.

## Write

Type on the hardware keyboard or click a keycap. Click the paper to position the carriage. Select a passage by dragging on the paper, holding Shift with the arrow keys, or using **Folio → Read & select text**. **Reading lens** enlarges the sheet while keeping the keyboard active.

Every printed character also advances the punched tape. Command and Control both work with C, X and V. Copy locks a selection, cut lifts the selected impressions with the correction ribbon, and paste drives the reader one stroke at a time. External plain text can also enter through the system clipboard. Escape stops playback. Backspace leaves a slightly different coloured patch. The sheet remembers the space under lifted text, so untouched impressions stay in place. Plain-text export contains the surviving text.

Return operates the return lever and advances the platen. Tab moves to the next stop. Adjust the brass margin stops on the carriage by dragging them, or use the numerical controls in Folio. The bell sounds six columns before the right stop. Click a platen knob to move forward one written line and Shift-click to move back. Command-Z rewinds an edit and Shift-Command-Z restores it.

## Sheets and storage

Use **Folio → New sheet** to start a document and the button beside its title to rename it. Select a stored title in Folio to reinsert it. Text, corrections, the continuous tape and machine settings are saved locally. The application keeps one previous save alongside its current save. On macOS the files are in `~/Library/Application Support/Godot/app_userdata/TypeTick/`. **Export plain text…** writes UTF-8 to a location you choose.

## Workshop

Drag the machine to orbit, and scroll to zoom. Pick a design separately for each assembly. There are 16 interchangeable assemblies with eight designs each, including the desk lamp and the two ribbon systems. Each GLB contains named physical meshes. Variants share mounting points and a common mechanism for their assembly, with geometry differences and variation in mechanical sound. Base finishes, paper, ink, desk and lighting can be combined. The paper and ink colour pickers also accept custom shades.

## Edit and build

Open `project.godot` in Godot 4.6.3 and press F6 on `Studio.tscn`, or F5 to run the project. No package installation or network connection is required at runtime. Each design is in `models/<assembly>/<design>.glb`. Edit one in a glTF editor such as Blender, preserve its origin and scale, then export GLB over the same file. Godot reimports it. The standard-library Python generator in `tools/build_models.py` recreates the stock designs and overwrites their GLBs when run.

Install Godot's matching macOS export template to build a universal release. From the project directory run:

```sh
godot --headless --editor --import
godot --headless --export-release macOS /absolute/path/TypeTick-macOS.zip
```

The provided macOS preset uses ad-hoc code signing. Apple Developer ID signing and notarization require a developer account. The project uses native menus and a native export dialog on macOS. The mechanical viewport uses Forward+ with the Metal driver on macOS, four-sample MSAA, real-time soft shadows and screen-space ambient occlusion. HDR reflections, photographed wood grain, finish maps and shader source ship inside the offline resource pack. Windows and controls use Godot with macOS menu integration. Surface asset credits are in `surfaces/CREDITS.txt`.

DejaVu typeface notices are in `fonts/LICENSE.txt`. Runtime license texts are available in the writing guide.
