# JavaFX 21 — Fat JAR + Platform Packaging (Maven)

Pattern: `mvn package` produces a fat JAR (maven-shade-plugin) + per-platform zips
(maven-assembly-plugin). Platform detected via Maven OS-activation profiles.

## Fat JAR (maven-shade-plugin)

JavaFX no-classifier deps (e.g. `javafx-controls:21`) contain Java bytecode only.
Native `.dylib`/`.so`/`.dll` files live in platform classifier JARs. Platform profiles
add the classifier JARs so shade bundles the right natives for the build platform.

### Platform profiles (pom.xml)

```
mac-aarch64  → classifier mac-aarch64   (Apple Silicon)
mac          → classifier mac           (Intel x86_64)
linux        → classifier linux
win          → classifier win
```

Each profile adds `javafx-base`, `javafx-graphics`, `javafx-controls`, `javafx-fxml`
with the relevant classifier. Activated automatically by `<os>` detection.

### Launcher wrapper class — REQUIRED

Setting `Main-Class` in the manifest directly to a class that extends
`javafx.application.Application` triggers a JVM check requiring `javafx.graphics`
as a named JPMS module. In a fat JAR (where `module-info.class` is excluded) it is
not — the app fails immediately with:

```
Error: JavaFX runtime components are missing, and are required to run this application
```

**Fix:** point `Main-Class` at a plain non-Application wrapper:
```java
public class AppLauncher {
    public static void main(String[] args) { MainApp.main(args); }
}
```
The JVM check is bypassed; JavaFX bootstraps from the classpath when
`Application.launch()` is called inside `MainApp.main()`.

### module-info.class exclusion — REQUIRED

Both the no-classifier bytecode JARs and the platform classifier JARs contain a
`module-info.class` for the same module (e.g. `javafx.controls`). Shade merges all
JARs into one — colliding `module-info.class` files break the build.

```xml
<filter>
    <artifact>*:*</artifact>
    <excludes><exclude>module-info.class</exclude></excludes>
</filter>
```

### Required JVM flags in all launcher scripts

```
--add-opens java.base/java.util=ALL-UNNAMED   # if a dep reflects on UUID fields (e.g. simple-xml)
--add-opens java.base/java.lang=ALL-UNNAMED
--enable-native-access=ALL-UNNAMED            # JavaFX loads natives via System::load;
                                              # warning today, hard error in future JDK
```

### Expected warning (harmless)

```
WARNING: Unsupported JavaFX configuration: classes were loaded from 'unnamed module @...'
```
JavaFX is not on the module path in the fat JAR. Informational only — the app runs normally.

## macOS .app bundle structure

```
MyApp.app/
  Contents/
    Info.plist
    MacOS/
      MyApp                 ← launcher shell script, mode 0755
    Resources/
      app-icon.icns
    Java/
      myapp-fat.jar
```

Key Info.plist values:
- `CFBundleExecutable` = launcher script name, exact match
- `CFBundleIconFile` = icon name WITHOUT `.icns` extension
- `NSHighResolutionCapable` = `true`
- Omit `LSUIElement` for a windowed app (it hides the Dock icon — tray-only apps)

Launcher path math: `$0` is at `Contents/MacOS/<launcher>`; jar at
`Contents/Java/<jar>` → `"$DIR/../Java/<jar>"`.

## Assembly descriptor — per-file permissions

The launcher must be `fileMode=0755`. A single `<fileSet>` cannot mix permissions
per file — split the launcher into a `<file>` element:

```xml
<files>
    <file>  <!-- fat JAR -->
        <source>${project.build.directory}/myapp-fat.jar</source>
        <outputDirectory>MyApp.app/Contents/Java</outputDirectory>
    </file>
    <file>  <!-- launcher, must be 0755 -->
        <source>src/main/assembly/macos/Contents/MacOS/MyApp</source>
        <outputDirectory>MyApp.app/Contents/MacOS</outputDirectory>
        <fileMode>0755</fileMode>
    </file>
    <file>  <!-- icon -->
        <source>path/to/app-icon.icns</source>
        <outputDirectory>MyApp.app/Contents/Resources</outputDirectory>
    </file>
</files>
<fileSets>
    <fileSet>  <!-- Info.plist etc., excluding launcher handled above -->
        <directory>src/main/assembly/macos/Contents</directory>
        <outputDirectory>MyApp.app/Contents</outputDirectory>
        <excludes><exclude>MacOS/MyApp</exclude></excludes>
    </fileSet>
</fileSets>
```

Verify after build: `unzip -Z dist.zip "*.app/Contents/MacOS/<launcher>" | awk '{print $1}'`
should show `-rwxr-xr-x`.

## Plugin declaration order

Both shade and assembly bind to the `package` phase. Maven executes same-phase
plugins in declaration order — **shade must be declared before assembly** in
`<plugins>`, otherwise assembly runs before the fat JAR exists.

## GitHub Actions release pattern

Trigger on `v*` tags. Matrix: `macos-latest` (arm64), `ubuntu-latest`,
`windows-latest` — each runner auto-activates the matching Maven OS profile and
runs `mvn -B package`. Upload platform zips via `actions/upload-artifact@v4`;
a final `release` job downloads all artifacts and attaches them with
`gh release create`.

## macOS icon generation (SVG → PNG → ICNS)

PNG (512×512) from SVG: `qlmanage -t -s 512 -o . app-icon.svg`
ICNS via `sips` + `iconutil` (macOS only, commit the result):

```bash
mkdir -p iconset.iconset
sips -z 16 16   app-icon.png --out iconset.iconset/icon_16x16.png
sips -z 32 32   app-icon.png --out iconset.iconset/icon_16x16@2x.png
sips -z 32 32   app-icon.png --out iconset.iconset/icon_32x32.png
sips -z 64 64   app-icon.png --out iconset.iconset/icon_32x32@2x.png
sips -z 128 128 app-icon.png --out iconset.iconset/icon_128x128.png
sips -z 256 256 app-icon.png --out iconset.iconset/icon_128x128@2x.png
sips -z 256 256 app-icon.png --out iconset.iconset/icon_256x256.png
sips -z 512 512 app-icon.png --out iconset.iconset/icon_256x256@2x.png
sips -z 512 512 app-icon.png --out iconset.iconset/icon_512x512.png
iconutil -c icns iconset.iconset -o app-icon.icns
rm -rf iconset.iconset
```
