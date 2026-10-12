# Brand icon sources and regeneration

## Source of truth

`app/assets/icons/rhythm.svg` is the editable 108 × 108 unit source. Its `background` and `foreground` groups are separate; the foreground retains the three rounded time blocks and the completion check as independent vector paths. The foreground artwork is within the central 66 × 66 unit adaptive-icon safe square (units 21–87). The check is a rounded, separate stroke below the blocks, so its silhouette remains distinct when monochrome-tinted. The SVG's green and pale foreground are default export colors, not app UI colors. `docs/icon.svg` is the unchanged original design reference.

The in-app `BrandMark` is drawn from the same geometry in `lib/features/brand_mark.dart` and uses `ColorScheme.primaryContainer` / `onPrimaryContainer` at render time. Platform launcher artwork is an exported brand asset and is intentionally not dynamically recolored by the app.

## Regenerating raster resources

Run the repository-owned, dependency-free Dart exporter from `app/`. It uses only `dart:io` and `dart:typed_data` from the Dart SDK bundled with Flutter; no SVG tool, plugin, Pub package, or network access is required. It parses the SVG's background, rounded block rectangles, and check stroke, rasterizes with 4 × 4 coverage sampling, and overwrites only the generated PNGs:

```sh
cd app
dart tool/export_icons.dart
```

The exporter writes the five Android densities, 32 px favicon, and regular/maskable Web icons at 192 and 512 px. Its supported SVG subset is intentional and checked: one 108 × 108 viewBox, a solid background rectangle, exactly three rounded foreground rectangles, and one three-point round-capped check stroke. If artwork structure changes, update the exporter and Android vector drawables to match; the editable SVG remains the source of truth. It exits with a format error instead of silently exporting unsupported geometry.

The Web maskable files use full-bleed background artwork and the motif remains inside the W3C central safe circle: for a 108-unit square, its farthest corner-like points are under 43.2 units (40% of canvas width) from the center. Keep that safe area when changing the SVG; do not export an Android adaptive foreground as a Web maskable icon. Ordinary Web files and maskable files are separate manifest entries, even though they currently share the same full-bleed artwork.

## Android configuration and vector layers

`android/app/src/main/AndroidManifest.xml` uses `@mipmap/ic_launcher` for both `icon` and `roundIcon`. `res/mipmap-anydpi-v26/ic_launcher.xml` composes the adaptive icon from a full-bleed color background and transparent foreground and declares the Android 13+ `monochrome` vector layer. `res/drawable/ic_launcher_foreground.xml` and `ic_launcher_monochrome.xml` are editable Android vector drawables using the same 108-unit motif geometry as the SVG; the foreground uses the default pale brand color, while the monochrome asset is opaque white only so the launcher can tint the silhouette. `res/values/ic_launcher.xml` defines the background color.

Keep the foreground in the central 66 × 66 dp safe square of the 108 × 108 dp adaptive canvas. Android applies circular, squircle, or other launcher masks; do not pre-round or inset the adaptive layers. Android 13+ launchers that support themed icons and have that option enabled can tint `monochrome`; older launchers, unsupported launchers, and disabled themed-icon settings use the color adaptive icon. API 24–25 use the generated density PNG fallback. Whenever the SVG geometry changes, update both Android vector paths to match it; a change in default export colors also requires updating the Android background and foreground vector colors.

The notification icon is independent: keep `res/drawable/ic_notification.xml` and `res/raw/keep.xml` unchanged. Neither the adaptive artwork nor its raster exports substitute for the transparent monochrome notification glyph.

## Web configuration

`web/manifest.json` declares ordinary 192/512 PNGs with `purpose: any` and corresponding 192/512 maskable PNGs with `purpose: maskable`. `web/index.html` points to the generated favicon and carries the brand `theme-color`; the existing Apple touch icon uses the regular 192 PNG. Preserve these paths and dimensions when exporting.

## Preview and limitations

Before release, inspect Android adaptive layers under circular, rounded-square, and other supported masks, and verify that no foreground detail is clipped. Inspect Web maskable output under the W3C safe-zone mask. Raster inspection and static resource review do not prove what a particular Android launcher displays. The monochrome layer only takes effect on a supported Android 13+ launcher when themed icons are enabled; otherwise the expected fallback is the color icon. Actual launcher behavior and system-theme tinting require device validation and must be recorded separately. The app's `BrandMark` responds to the active `ColorScheme` and can be previewed at two brightnesses via Flutter's widget previewer; it does not provide a user-facing theme editor.
