# FXTrayIcon 4.2.3

- `Builder.menuItem(label, handler)` builds its own internal `javafx.scene.control.MenuItem`
  and converts it to AWT internally — it does **not** use any `MenuItem` instance you
  construct yourself. If you want a live handle to enable/disable a built item later, you
  cannot pass your own `MenuItem` in; you must fetch it after `.build()`.
- `FXTrayIcon.getMenuItem(int index)` returns the **AWT** `java.awt.MenuItem` (not the
  JavaFX one) for the item at that build-order index — index 0 is whichever `.menuItem(...)`
  call came first in the builder chain, etc. Javadoc explicitly says to call this (and any
  subsequent mutation like `setEnabled()`) via `EventQueue.invokeLater()`.
- Build order is tracked in a **static, class-level counter** (`BuildOrderUtil.index`), not
  per-`Builder`-instance — safe for a single tray icon built once per app run, but do not
  build more than one `FXTrayIcon` in the same JVM without accounting for this shared state.
- Pattern for a settable-later menu item: hold an `AtomicReference<java.awt.MenuItem>`
  seeded with a placeholder, swap in the real item via `EventQueue.invokeLater(() ->
  ref.set(trayIcon.getMenuItem(idx)))` right after `.build()`, and have all consumers read
  through `ref.get()` rather than capturing the field by value before the swap happens.
