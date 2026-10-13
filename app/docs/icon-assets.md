# Brand icon sources and regeneration

## Source of truth

`app/assets/icons/rhythm.svg` preserves the artwork of the original reference, `app/docs/icon.svg`, in its original 100 × 100 coordinate system. The reference is not a runtime or export dependency. The canonical SVG retains the transparent outer inset, the rounded green tile at (15, 15), size 70 × 70, radius 19, three top-aligned pale blocks, and the separate white check. It is not the former ascending-bars redesign.

Block rectangles are (29, 28, 12, 16), (46, 28, 12, 28), and (63, 28, 9, 21), all with radius 4. The check is `M29 66 L43 75 L70 51`, width 7, with round caps and joins. The default export colors are `#208D78`, `#D7F9E8`, and `#FFFFFF` respectively.

The in-app `BrandMark` uses this same padded geometry and the active `ColorScheme.primaryContainer` / `onPrimaryContainer` pair. Its blocks and check share the theme's foreground role, rather than forcing the export palette into dark or light UI. The light/dark widget previews remain in `lib/features/brand_mark.dart`.

## Regenerating raster resources

Run from `app/`:

```sh
dart tool/export_icons.dart
```

The dependency-free Dart exporter parses the SVG's two groups, one rounded background rectangle, three rounded foreground rectangles and one three-point M/L check stroke. It uses 4 × 4 coverage sampling with alpha at transparent edges and a separately colored check, and overwrites only the ten generated PNGs:

- Five Android density fallbacks: 48, 72, 96, 144 and 192 px.
- Web favicon: 32 px.
- Ordinary Web icons: 192 and 512 px, retaining the reference's transparent inset and rounded tile.
- Web maskable icons: 192 and 512 px, extending only the green background to the full canvas. Motif coordinates and scale are unchanged; regular and maskable exports are cached separately.

The supported SVG subset is intentionally narrow. Unsupported viewBox or check-path structure produces a format error rather than an approximation. Geometry changes also require synchronizing `BrandMark` and the Android vector layers.

## Android layers

`android/app/src/main/AndroidManifest.xml` uses `@mipmap/ic_launcher` for `icon` and `roundIcon`. The adaptive icon composes the full-bleed background color, transparent foreground vector, and Android 13+ monochrome vector.

Both vectors retain the reference's 100-unit motif inside a uniformly scaled 1.08 group on a 108 × 108 canvas. The motif, including its stroke, stays inside the central 66 × 66 adaptive safe square. The colored foreground keeps pale blocks and a white check; monochrome uses an opaque white silhouette for launcher tinting. Do not add a rounded tile or inset background to adaptive layers: the launcher supplies the mask. API 24–25 use the ordinary PNG fallback.

The notification glyph is independent. Keep `res/drawable/ic_notification.xml` and `res/raw/keep.xml` unchanged; launcher artwork must not replace the notification icon.

## Web and verification boundaries

`web/manifest.json` retains separate `purpose: any` and `purpose: maskable` entries. `web/index.html` uses the generated favicon and the regular 192 px Apple touch icon. The maskable motif remains inside the W3C central safe circle; only its background differs from the ordinary export.

Compare the canonical SVG and generated ordinary PNG with the original reference at the same canvas size, including transparent padding, block proportions and the white check. Inspect adaptive / maskable silhouettes under circular and rounded-square masks as well.

Pixel comparisons, widget tests and APK inspection do not prove launcher behavior. Verify the installed app and launcher on a device. Monochrome tinting additionally requires an Android 13+ launcher with themed icons enabled; do not claim that behavior from the color-icon check alone. Historical screenshots predate this correction and are not evidence for the corrected icon.
