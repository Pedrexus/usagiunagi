# 兔鰻 · usagiunagi identity

The current icon is an abstract two-character mark. It has no animal face or silhouette. Each kanji is an independent outlined SVG layer inside `UsagiUnagi.icon`; Xcode/Icon Composer supplies the material, edge lighting, shadows and appearance variants. The source artwork contains no baked glass, bitmap texture or embedded font. The neutral background and restrained blue-gray lettering keep the mark legible; dark and tinted modes use brighter foreground overrides.

`Resources/Generators/make-brand-glyphs.swift` creates the outlined lettering from macOS's Hiragino Sans W7. The paths are checked in, so app builds do not depend on running that script or shipping a font. The wide stacked composition is deliberate; each layer remains independently editable in Icon Composer.

`Previews/` contains reference exports from Apple's renderer, not the application's layered source. Default, Dark, TintedDark and Clear appearances were rendered for inspection. Clear mode adapts to the system wallpaper, so its exported neutral canvas is not a final home-screen background.

To export a preview with Xcode 27 from the parent workspace root:

```sh
mainboard run --as-is mainboard proc timeout 60 \
  "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  apps/usagiunagi/Resources/UsagiUnagi.icon --export-image --output-file /tmp/usagiunagi.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1 --design-generation 27
```

The icon is included in the iOS, native macOS and existing watch companion targets. All main/watch app configurations select `UsagiUnagi` explicitly and compile the shared document directly. The two legacy app asset catalogs are retired: their icon backups, artwork, SRS images, custom symbol copies and Paper color had no active callers. Shared screens use SF Symbols and colors defined in Swift; the separate shared-package font preview catalog remains in use. Static default exports and the Mac product's fallback icon confirm the two kanji fit their masks. On-device home-screen, Dock and watch appearance still need acceptance.

## Naming

| Localization | App display name / prepared store name |
| --- | --- |
| Japanese (`ja`) | 兔鰻 |
| Simplified Chinese (`zh-Hans`) | 兔鰻 |
| Traditional Chinese (`zh-Hant`, including Taiwan/Hong Kong users) | 兔鰻 |
| English / fallback | usagiunagi |

The exact characters **兔鰻** are retained in all three localizations as requested. Storefront language fallback is controlled by App Store Connect; country and language are not interchangeable. `InfoPlist.strings` localizes the installed app name, while `Resources/StoreListing/*/name.txt` prepares listing names. This does not claim that the entire interface is translated, nor that any store listing has been published.

The GitHub fork is now `Pedrexus/usagiunagi`. Historical source/module/target names and bundle identifiers remain for data/signing compatibility. The API client creates tokens named `usagiunagi` while continuing to recognize existing `Tsurukame` tokens. Upstream copyright notices and attribution remain intact.

References: [Apple Icon Composer](https://developer.apple.com/icon-composer/) and [Apple's icon creation guide](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).
