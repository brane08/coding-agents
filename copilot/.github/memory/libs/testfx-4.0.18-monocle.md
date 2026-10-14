# TestFX 4.0.18 + Monocle — headless JavaFX UI testing

Stack: `org.testfx:testfx-core:4.0.18` + `org.testfx:testfx-junit5:4.0.18` +
`org.testfx:openjfx-monocle` for headless UI tests under `mvn test` (no display needed).

## Monocle version: use 21.0.2, not jdk-12.0.1+2

The obvious/commonly-referenced coordinate `org.testfx:openjfx-monocle:jdk-12.0.1+2` is a
2019 build against JavaFX 12. Under JavaFX 21+ (confirmed on JavaFX 25.0.1) it throws:

```
AbstractMethodError: MonocleWindow does not implement _updateViewSize(long)
```

This is a real upstream ABI break, tracked as JDK-8308345. Monocle's `MonocleWindow` /
`MonocleView` subclass JavaFX's internal `com.sun.glass.ui.Window` / `View` classes, and
that internal ABI changed between JavaFX 12 and JavaFX 21+. An old Monocle build simply
doesn't implement the newer abstract methods.

**Fix:** depend on `org.testfx:openjfx-monocle:21.0.2` instead — the newest Monocle
actually published against a released JavaFX line.

Verified by decompressing both jars: `javafx-graphics-25.0.1.jar` ships zero
`com/sun/glass/ui/monocle/` classes, and `openjfx-monocle-21.0.2.jar` ships only that
package. No split-package shadowing — safe to add as a plain test-scope dependency
alongside a newer javafx-graphics.

**Warning:** any future JavaFX version bump risks resurrecting the exact same
`AbstractMethodError` if Monocle's glass ABI has drifted further since 21. Check Monocle
compatibility before bumping `javafx.version`, or re-run the UI test suite immediately
after bumping and treat any `AbstractMethodError` in Monocle classes as this issue.

**Forward note:** JavaFX 26 (not yet released as of writing) is expected to ship a
built-in "Headless Platform" that replaces the need for Monocle entirely — a
system-property based mechanism, no extra JAR. When a project upgrades to JavaFX 26+,
Monocle can likely be dropped in favor of that.

## Required surefire system properties

```xml
<systemPropertyVariables>
    <testfx.robot>glass</testfx.robot>
    <testfx.headless>true</testfx.headless>
    <glass.platform>Monocle</glass.platform>
    <monocle.platform>Headless</monocle.platform>
    <prism.order>sw</prism.order>
</systemPropertyVariables>
```

(`prism.text=t2k` is NOT needed/valid on modern JavaFX — the T2K rasterizer was removed
from OpenJFX since version 13; Prism silently falls back to the native rasterizer, so the
property is just dead/misleading.)

## Required JPMS `--add-opens` (Monocle 21.0.2 on JavaFX 21.0.9)

Beyond the commonly-documented `com.sun.glass.ui`/`com.sun.javafx.application`/
`com.sun.glass.ui.monocle` opens, Monocle 21.0.2 additionally needs these to
`ALL-UNNAMED` (discovered one `IllegalAccessError` at a time — not documented anywhere
found):

```
--add-opens=javafx.base/com.sun.javafx=ALL-UNNAMED
--add-opens=javafx.graphics/com.sun.javafx.util=ALL-UNNAMED
--add-opens=javafx.base/com.sun.javafx.logging=ALL-UNNAMED
```

## `reuseForks=false` when mixing with a homegrown `Platform.startup()` helper

If the same Maven module also has non-TestFX tests that call `Platform.startup()`
directly (e.g. a hand-rolled `FxHelper.startOnce()` for `Stage.show()`-less headless
tests), running them in the same JVM fork as a TestFX `ApplicationExtension` test throws
`IllegalStateException: Toolkit already initialized` — each style initializes the FX
toolkit independently and only one can win per fork. Fix: set
`<reuseForks>false</reuseForks>` on maven-surefire-plugin so each test class gets its own
fork.

## `java.awt.headless=true` side effect

Monocle headless mode is typically paired with `-Djava.awt.headless=true`. This means any
test that constructs a real `java.awt.Robot` will throw `AWTException` /
`HeadlessException` under the test JVM — not a bug in the class under test, just AWT
refusing to create a Robot with no display. Confusing if hit blind without knowing the
test JVM is headless.
