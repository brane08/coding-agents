# JNativeHook 2.2.2 (com.github.kwhat:jnativehook)

## Modifier masks are left/right bitflags — never compare with `==`

`NativeInputEvent` constants (verified via `javap -constants`):

| Field | Value |
|---|---|
| SHIFT_L_MASK / SHIFT_R_MASK / SHIFT_MASK | 1 / 16 / 17 |
| CTRL_L_MASK / CTRL_R_MASK / CTRL_MASK | 2 / 32 / 34 |
| META_L_MASK / META_R_MASK / META_MASK | 4 / 64 / 68 |
| ALT_L_MASK / ALT_R_MASK / ALT_MASK | 8 / 128 / 136 |
| NUM_LOCK_MASK / CAPS_LOCK_MASK / SCROLL_LOCK_MASK | 8192 / 16384 / 32768 |

`getModifiers()` is a raw field getter; the native layer sets only the side actually held
(left Ctrl → 2, not 34) and ORs in lock-key state. So
`e.getModifiers() == (CTRL_MASK | ALT_MASK)` is never true for a real key press.

Correct hotkey match:

```java
static boolean matches(int mods, int requiredMask) {
    int relevant = mods & (SHIFT_MASK | CTRL_MASK | META_MASK | ALT_MASK); // drop lock bits
    for (int m : new int[]{SHIFT_MASK, CTRL_MASK, META_MASK, ALT_MASK}) {
        boolean want = (requiredMask & m) != 0;
        boolean have = (relevant & m) != 0;
        if (want != have) return false;
    }
    return true;
}
```

## Logger

`GlobalScreen` creates `Logger.getLogger("com.github.kwhat.jnativehook")` in its **static
initializer**. `GlobalScreen.class.getPackage()` does not initialize the class, so
`LogManager.getLogManager().getLogger(pkg)` before the first `registerNativeHook()` returns
`null`. Silence it with `Logger.getLogger("com.github.kwhat.jnativehook").setLevel(Level.WARNING)`
(creates the logger; keep a static reference so it is not GC'd).

## Threading

`NativeKeyListener` callbacks run on JNativeHook's dispatch thread, not the FX/AWT thread.
Hand off with `Platform.runLater` / `SwingUtilities.invokeLater`.
