# JavaFX 21 — Framework Notes

Desktop app patterns and version quirks. Packaging/fat-JAR concerns live in
`javafx-21-fat-jar-packaging.md`.

## Version quirks / bugs

### FXML `KeyCodeCombination` is broken in JavaFX 21

Accelerators declared in FXML do not fire. Set them programmatically in `initialize()`:

```java
menuSave.setAccelerator(new KeyCodeCombination(KeyCode.S, KeyCombination.SHORTCUT_DOWN));
```

`SHORTCUT_DOWN` maps to Cmd on macOS, Ctrl elsewhere — always prefer it over `CONTROL_DOWN`.

### Scene event filters accumulate — remove before re-adding

`scene.addEventFilter()` **appends**; it does not replace. Re-running your wiring
method (e.g. after the user changes a shortcut in Settings) silently stacks a second
set of handlers, and each keypress then fires the action N times. There is no
dedup on re-add.

Keep each handler in a field and remove it before re-adding:

```java
private EventHandler<KeyEvent> copyFilter;   // one field per filter

private void applyShortcuts() {
    var scene = stage.getScene();
    if (scene == null) return;
    if (copyFilter != null) scene.removeEventFilter(KeyEvent.KEY_PRESSED, copyFilter);
    var combo = KeyCombination.valueOf(settings.getShortcutCopy());  // e.g. "SHORTCUT+SHIFT+C"
    copyFilter = e -> {
        if (!combo.match(e)) return;
        doCopy();
        e.consume();
    };
    scene.addEventFilter(KeyEvent.KEY_PRESSED, copyFilter);
}
```

Contrast with the `setOnXxx` property setters (`setOnKeyPressed`, `setOnMouseMoved`):
those **replace** the previous handler, so they are idempotent and need no removal.
Mixing the two is the trap — `addEventFilter` looks equivalent but leaks handlers.

### `KeyCombination.valueOf(String)` — user-configurable shortcuts

Parses a canonical string into a matchable combination, so shortcuts can live in a
properties file or settings UI rather than being compiled in:

```java
KeyCombination combo = KeyCombination.valueOf("SHORTCUT+SHIFT+C");
if (combo.match(keyEvent)) { ... }
```

Round-trips with `KeyCombination.getName()`. Accepts `SHORTCUT`, `SHIFT`, `ALT`,
`CONTROL`, `META` — so one stored string stays correct across platforms.

### `showAndWait()` inside an animation callback throws

`IllegalStateException` when called from `PauseTransition.setOnFinished()` (or any
animation callback). Wrap in `Platform.runLater()`:

```java
timer.setOnFinished(e -> Platform.runLater(this::showDialog));  // runLater REQUIRED
```

### `PauseTransition.setDuration()` on a running transition has no effect

Recreate the transition instead of mutating it when the configured duration changes.

## FXMLLoader wiring

### `initialize()` runs before setter injection

`FXMLLoader.load()` calls `initialize()` during load — before the caller can inject
collaborators via setters. Two consequences:

- Null-guard injected fields in `initialize()`.
- Anything needing a collaborator goes in the setter, not `initialize()`.

```java
var loader = new FXMLLoader(getClass().getResource("main.fxml"));
Parent root = loader.load();              // 1. initialize() runs here
var ctrl = (MainController) loader.getController();
ctrl.setService(new Service());           // 2. collaborators arrive after
ctrl.setPrimaryStage(stage);
```

### Controller-less FXML + `lookup()` — reusing one FXML with different wiring

Omit `fx:controller`, load the root node raw, find children by id. Lets a single FXML
serve several dialogs with different behaviour each time:

```java
var loader = new FXMLLoader(getClass().getResource("password-dialog.fxml"));
var content = (VBox) loader.load();
var promptLabel   = (Label)         content.lookup("#promptLabel");
var passwordField = (PasswordField) content.lookup("#passwordField");
var errLabel      = (Label)         content.lookup("#errorLabel");
```

`lookup()` uses `#id` selector syntax and searches the scene graph below the node.

## Common control patterns

### Password show/hide toggle

`PasswordField` cannot reveal its text. Overlay two controls and swap them:

```java
// PasswordField fieldPassword       — visible by default
// TextField     fieldPasswordVisible — visible=false, managed=false initially
private void handleShowHide() {
    boolean revealing = !fieldPasswordVisible.isVisible();
    if (revealing) fieldPasswordVisible.setText(fieldPassword.getText());
    else           fieldPassword.setText(fieldPasswordVisible.getText());
    fieldPasswordVisible.setVisible(revealing);
    fieldPasswordVisible.setManaged(revealing);
    fieldPassword.setVisible(!revealing);
    fieldPassword.setManaged(!revealing);
}
```

Toggle `managed` alongside `visible` — otherwise the hidden field still occupies layout space.

### `ComboBox.setConverter()` — show one thing, store another

`StringConverter` decouples the displayed label from the stored item, so the combo can
hold canonical values while showing friendly text. The selection model still returns
the canonical value — no mapping back needed at read time.

```java
comboShortcut.setConverter(new StringConverter<String>() {
    @Override public String toString(String s) {          // stored -> displayed
        return s == null ? "" : s.replace("SHORTCUT", "Ctrl/Cmd").replace("+", " + ");
    }
    @Override public String fromString(String s) { return s; }   // only needed if editable
});
comboShortcut.setItems(FXCollections.observableArrayList("SHORTCUT+SHIFT+C", "SHORTCUT+ALT+C"));
```

`fromString` only matters for an editable ComboBox; for a read-only one it can return
the input unchanged.

### Custom dialog buttons — order follows argument order

Pass `ButtonType`s to the `Alert` constructor in the order you want them laid out.
`ButtonBar.ButtonData` carries the semantics (default/cancel handling, platform
placement), but the constructor argument order is what determines display order —
not the `ButtonData` enum order.

```java
var saveBtn    = new ButtonType("Save",    ButtonBar.ButtonData.YES);
var discardBtn = new ButtonType("Discard", ButtonBar.ButtonData.NO);
var alert = new Alert(Alert.AlertType.CONFIRMATION,
        "Save changes before closing?",
        saveBtn, discardBtn, ButtonType.CANCEL);
alert.setHeaderText(null);                 // suppress the default header

Optional<ButtonType> result = alert.showAndWait();
if (result.isEmpty() || result.get() == ButtonType.CANCEL) return false;   // isEmpty = dismissed
if (result.get() == saveBtn) { ... }
```

Compare the result by identity against your own `ButtonType` instances. Always handle
`isEmpty()` — the dialog can be dismissed without any button.

### Dialog validation — block close on invalid input

Add an event filter to the OK button and `consume()` the event to keep the dialog open:

```java
Button ok = (Button) dialog.getDialogPane().lookupButton(ButtonType.OK);
ok.addEventFilter(ActionEvent.ACTION, event -> {
    if (!isValid(field.getText())) {
        errLabel.setText("Invalid");
        event.consume();                 // dialog stays open
    }
});
```

### Idle / inactivity timer

```java
timer = new PauseTransition(Duration.seconds(idleSeconds));
timer.setOnFinished(e -> Platform.runLater(this::onIdle));
timer.play();
scene.setOnMouseMoved(e   -> timer.playFromStart());
scene.setOnKeyPressed(e   -> timer.playFromStart());
scene.setOnMouseClicked(e -> timer.playFromStart());
```

Recreate the transition when `idleSeconds` changes (see `setDuration()` quirk above).

### Timed clipboard clear

```java
Clipboard.getSystemClipboard().setContent(Map.of(DataFormat.PLAIN_TEXT, value));
if (clipboardTimer != null) clipboardTimer.stop();   // stop previous before restarting
clipboardTimer = new PauseTransition(Duration.seconds(timeoutSeconds));
clipboardTimer.setOnFinished(e -> Clipboard.getSystemClipboard().clear());
clipboardTimer.play();
```

### TableView search filter

Wrap the backing list in a `FilteredList` and rebind the predicate from the search field:

```java
var filtered = new FilteredList<>(items, p -> true);
searchField.textProperty().addListener((obs, old, val) ->
    filtered.setPredicate(row -> val == null || val.isBlank()
        || row.getTitle().toLowerCase().contains(val.toLowerCase())));
table.setItems(filtered);
```

## JPMS module-info for a JavaFX app

```java
module com.example.app {
    requires javafx.controls;
    requires javafx.fxml;
    opens com.example.app        to javafx.fxml;  // FXMLLoader reflects on controllers
    opens com.example.app.model  to javafx.base;  // PropertyValueFactory reflects on models
    exports com.example.app;
    exports com.example.app.model;
}
```

- `opens … to javafx.fxml` is required for every package containing an FXML controller.
- `opens … to javafx.base` is required for model packages read via `PropertyValueFactory`
  or any property-name reflection.
- Adding a new package with controllers or models means adding a matching `opens`.
