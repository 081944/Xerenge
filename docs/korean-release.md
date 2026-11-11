# Korean retail release (En, Zh, Ko)

This checkout adds a separate Korean build. It recompiles the Korean disc's
own `default.xex` and keeps all of that disc's files intact. It does not use
the USA executable or rename Chinese resources over English resources.

## Disc identification

- Disc SHA-256: `94ecd97fe1478e099e747a72e00da1e84cc829b7ae80a815283134884ee49849`
- Disc size: 7,834,892,288 bytes; 956 extracted files.
- Executable SHA-256: `a847b760d87c5a5403f1db2913383de1c84537ca70e2714c04024c835ef3fcd1`
- Executable entry: `0x825BC660`.

`bootstrap.sh` and the desktop/Android extractors recognise this disc. The
desktop payload uses `bin/burnout_kr` (`.exe` on Windows); Android uses
`libmain_kr.so`. Installers reject this disc if their payload lacks that build.

## Building

Use the existing setup and build scripts with the Korean disc:

```sh
./scripts/bootstrap.sh /path/to/korean-disc.iso game_kr
```

For an already-extracted disc:

```sh
./scripts/build.sh --game game_kr
```

The manifest patcher hashes `default.xex` and selects `functions_kr.toml`.
CMake selects the corresponding host-source address variant. Python 3 is
required for Korean builds. `korea-addresses.json` holds address metadata;
`prepare-korea-sources.py` creates build-local source copies with translated
address and function tokens. Comments, strings and the original EU/USA sources
are not rewritten. An unmapped hook symbol fails configuration.

The shader cache is invalidated when the executable hash changes. Korean
shaders are rebuilt from the Korean disc. CI creates a Korean payload when its
private build inputs include `game_kr/default.xex` and the required graphics
templates; without them it warns and packages no Korean executable.

## Languages

The Korean game's Settings > LANGUAGE has three native choices:

| Choice | Configuration | Disc resources |
| --- | --- | --- |
| English | `language = 1` | `MainUS.bin`, normal fonts |
| Traditional Chinese | `language = 8` | `MainTc.bin`, `Chinese_Traditional` fonts |
| Korean | `language = 7` | `MainKo.bin`, `Korean` fonts |

The first start defaults to Traditional Chinese. A saved English, Chinese or
Korean choice is respected on subsequent starts. There is no separate language
selection screen added by this change.

Changing the native language saves the choice and, on desktop, offers a restart. Restarting
lets the original game reload its own text and fonts together. The launcher
also accepts the same `language` values in `xerenge.conf`. Original disc files
are not overwritten. Localisation mods, when installed, retain their existing
separate mechanism.

On Android, close and reopen the game after changing the native language so
that the fonts are reloaded. Automatic on-screen controls require a joystick
with axes or a gamepad with at least two face buttons; phone sensors that
advertise the gamepad source (such as `gf_input`) do not hide the controls.

Drivers that accept BC textures but do not advertise the full Vulkan BC
feature use ETC2 (or RGBA8 when ETC2 is unavailable) for BC2/DXT3 textures.
The Korean disc's Chinese and Korean fonts use BC2; their text was invisible
with native BC2 on the tested Adreno 650. Other working BC formats stay native.

The Korean SKU queries the console's `XGetLanguage` import for CJK font and
text selection. Its host supplies that import from the existing language
setting; the shared SDK's English-only default is left unchanged. Android
binds the override locally in `libmain_kr.so`, even when the SDK is loaded first.

On Windows, an Android build can be packaged with
`scripts/build-android-apk.ps1 -Debuggable` after compiling
`rexglue/build-android-kr` with NDK r30. The script also supports a Korean-only
payload and requires JDK 17 or newer plus the Android SDK build tools.

## Validation status

Korean code generation completed with no unresolved calls. The disc rebuilt
119 static and 69 runtime shaders with no failed recipes. Source-generation
token tests and workflow/shell syntax checks have been run.

The native Korean Windows build has shown English, Traditional Chinese and
Korean title screens, Traditional Chinese main menus, Korean Settings, and
profile creation/loading. Its existing LANGUAGE setting saves all three
native choices. Tests used a muted 640x360 background window.

Android ARM64 was built with NDK r30 and installed on an IN2010 (Android 11,
Adreno 650). Testing reproduced and diagnosed hidden touch controls and
invisible CJK text. The final APK was verified with no debug environment
overrides and no saved language: automatic touch controls remained visible,
the BC2 fallback restored Traditional Chinese, and the on-screen START and A
buttons navigated through the sign-in prompt into the Traditional Chinese
main menu. The original disc resources were unchanged.

Full races and end-to-end gameplay have not been established. EU/USA runtime
regressions, Qt installer compilation, UWP, Linux and macOS builds have not
been verified locally.
