# Nano app icon — Blink Compact

`Nano.icon` is the editable Icon Composer document. Open it in the Icon Composer
bundled with Xcode. It contains two SVG layers, Cursor and Dot, on a solid
background, with explicit light, dark, and tinted mark appearances. The mark has no glass,
specular highlight, translucency, or shadow; the system supplies the enclosure.

The artwork enlarges the original Paper E1 Compact mark to twice its size,
centered on the 1024-unit canvas for better visibility across macOS:

- Cursor: x 564, y 256, width 80, height 512, corner radius 40.
- Dot: center 420, 728; radius 40.
- Horizontal gap between the dot and caret: 104 units.
- Caret: a subtle top-to-bottom purple gradient, `#D552E6` to `#BF2ED7`
  in light mode and `#E45CF4` to `#CE35E9` in dark mode.
- Dot: a tonal gradient, `#505050` to `#383838` in light mode and `#FAFAFA`
  to `#DDDDDD` in dark mode. Background: paper `#FAFAFA` or graphite `#383838`.
- Gradients are editable layer fills in `icon.json`; SVGs provide the shapes.
- The app defaults to dynamic AppKit systemPurple; saved accent choices take priority.
- Tinted: a white mark preserves contrast against the system-tinted background.

Paper source: https://app.paper.design/file/01K5P0VC43EHE1GQDWXCF4ZPFJ/01K5P0VC44Y0PX2ZCHDVT9WJK4

`script/package.sh` requires full Xcode with Icon Composer support (Xcode 26 or
newer). Apple's `actool` compiles this document into `Assets.car` and `Nano.icns`
in the app's Resources folder. It also generates the icon Info.plist keys, which
the packaging script merges before signing. The deployment target stays macOS 14.

Generated icons belong in `dist/`, not in source control. Rebuild with
`./script/package.sh` after editing the document. Inspect the result in Finder
and the Dock; the enlarged mark also improves legibility at small sizes.
