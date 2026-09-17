# KeePassJava2 2.2.4 — API Notes

## Create / open / save

```java
import org.linguafranca.pwdb.kdbx.KdbxCreds;
import org.linguafranca.pwdb.kdbx.simple.SimpleDatabase;
import org.linguafranca.pwdb.kdbx.simple.SimpleEntry;

// Create empty — NOT createEmpty(), that method does NOT exist in 2.2.4
SimpleDatabase db = new SimpleDatabase();

// Save to disk
KdbxCreds creds = new KdbxCreds(masterPassword.getBytes(StandardCharsets.UTF_8));
db.save(creds, new FileOutputStream(file));

// Open existing (throws Exception on wrong password)
KdbxCreds creds = new KdbxCreds(masterPassword.getBytes(StandardCharsets.UTF_8));
SimpleDatabase db = SimpleDatabase.load(creds, new FileInputStream(file));
```

## KDBX version written — v4 by default, NOT 3.1

2.2.4 supports both KDBX 3.1 and KDBX 4 (`KdbxStreamFormat.Version.{KDBX31,KDBX4}`).
Which one you get is decided by the `streamFormat` field, and the defaults differ by
construction path — verified by decompiling `SimpleDatabase`:

| How the db was made | `streamFormat` | `save(creds, out)` writes |
|---|---|---|
| `new SimpleDatabase()` | `null` (ctor passes `aconst_null`) | **KDBX 4** — `save()` lazily builds `new KdbxStreamFormat(new KdbxHeader(4))` |
| `SimpleDatabase.load(creds, in)` | header read from the file | **the file's own version** (round-trips) |

`new KdbxHeader(int)` picks the crypto suite from the version:
`3 -> V3_AES_SALSA_20`, `4 -> V4_AES_ARGON_CHA_CHA` (Argon2 + ChaCha20).
So a database created from scratch gets Argon2, not AES-KDF.

Beware: the no-arg `new KdbxStreamFormat()` defaults to **version 3**
(`new KdbxHeader(3)`) — the opposite of `SimpleDatabase.save()`'s lazy default. Don't
infer the write version from that constructor.

To pin a version explicitly, use the format-taking overload:

```java
db.save(new KdbxStreamFormat(new KdbxHeader(3)), creds, out);   // force KDBX 3.1
```

Argon2 comes from BouncyCastle (`bcprov`, `Argon2BytesGenerator`) — it must be on the
classpath for v4 to work.

## Re-saving reuses the seeds and IV — pass a fresh header every save

**`SimpleDatabase` caches its `StreamFormat` in a field, and all header randomness is
generated in the `KdbxHeader` constructor.** So calling `db.save(creds, out)` twice on
the same instance rewrites the file with the *same* master seed, transform seed,
encryption IV and inner-random-stream key. Verified empirically: three consecutive
saves of an unchanged db produce **byte-identical files**.

Why it matters: the inner random stream (Salsa20 for v3, ChaCha20 for v4) is what
protects the password fields inside the XML. Reusing `innerRandomStreamKey` means the
same keystream encrypts both versions, so two copies of the file (backup, cloud sync,
git history) XOR to reveal the XOR of their plaintexts — a two-time pad. The KDBX
final key is `SHA256(masterSeed || transformedKey)`, so a stale `masterSeed` also means
a stale encryption key.

`writeKdbxHeader()` only *reads* the seeds; there is no `nextBytes` call anywhere on
the save path. Nothing regenerates them for you.

**Fix — construct a new `KdbxStreamFormat`/`KdbxHeader` per save** (the ctor calls
`SecureRandom.generateSeed` for every seed):

```java
// version: 3 -> KDBX 3.1, 4 -> KDBX 4
db.save(new KdbxStreamFormat(new KdbxHeader(version)), creds, out);
```

Never hand `save()` a header that has already been written. A regression test can assert
that two saves of unchanged data produce different bytes.

Caveat: a fresh `KdbxHeader(4)` resets KDF parameters (Argon2 cost/memory) to library
defaults. To keep a file's custom tuning, copy `getKdfParameters()` across — but then
refresh the Argon2 salt inside that `VariantDictionary` yourself.

## Entry operations

```java
SimpleEntry entry = db.newEntry();            // returns SimpleEntry (not generic Entry)
entry.setTitle("Example");
entry.setUsername("user@example.com");
entry.setPassword("s3cret");
entry.setUrl("https://example.com");
db.getRootGroup().addEntry(entry);

List<SimpleEntry> entries = db.getRootGroup().getEntries();
db.getRootGroup().removeEntry(entry);         // delete by reference
String pwd = entry.getPassword();
String notes = entry.getNotes();              // may return null if never set — null-guard to ""
entry.setNotes("some notes");                 // calls touch() → updatedAt updated automatically
```

## Group operations

```java
import org.linguafranca.pwdb.kdbx.simple.SimpleGroup;

// Create a named group and add to root
SimpleGroup g = db.newGroup("Work");        // AbstractDatabase.newGroup(String) — sets name
db.getRootGroup().addGroup(g);

// Enumerate child groups of root (one level only)
List<SimpleGroup> groups = db.getRootGroup().getGroups();  // List<SimpleGroup>
g.getName();    // group name
g.getEntries(); // List<SimpleEntry> — entries directly in this group

// Add / remove entries across groups
g.addEntry(entry);    // moves ownership to this group
g.removeEntry(entry); // removes by reference

// Move entry between groups (reference-equal SimpleGroup objects from getGroups())
oldGroup.removeEntry(entry);
newGroup.addEntry(entry);
```

Group equality uses `Object.equals()` (reference identity) — the same `SimpleGroup` instance
returned from `root.getGroups()` is safe to compare with `==` / `.equals()`.

## Timestamps

**Timestamps are exposed as direct methods on `SimpleEntry`, NOT via `getTimes()`.**
`entry.getTimes()` is package-protected (returns `model.Times`); calling it compiles but
is not part of the public API.

```java
Date createdAt  = entry.getCreationTime();          // set by KeePassJava2 on newEntry()
Date modifiedAt = entry.getLastModificationTime();  // auto-updated by setTitle/setUsername/etc.
// Times constructor truncates to seconds: new Date(System.currentTimeMillis()/1000*1000)
// So timestamp tests need a ±1-second tolerance window
```

`touch()` is called by `setTitle()`, `setPassword()`, `setUrl()`, `setUsername()`, `setProperty()`
— so `getLastModificationTime()` always reflects the most recent field mutation.

## Module system — Java 9+ named modules

Sub-JARs declare **invalid `Automatic-Module-Name`** values containing hyphens
(e.g. `org.linguafranca.pwdb.KeePassJava2-simple` — hyphens are not valid in
Java identifiers). Additionally, `KeePassJava2-2.2.4.jar` and `database-2.2.4.jar`
both export `org.linguafranca.pwdb` — a **split package** that fails on the module path.

**Fix:** Keep all KeePassJava2 JARs on the classpath (unnamed module).
Grant read access in the host module via compiler/runtime flags:

```
--add-reads <your.module>=ALL-UNNAMED
```

Surefire also needs these for simple-xml's UUID reflection on JDK 17+:

```
--add-opens java.base/java.util=ALL-UNNAMED
--add-opens java.base/java.lang=ALL-UNNAMED
```

Do NOT add `requires KeePassJava2;` to `module-info.java` — it will fail.

## pom.xml pattern (`<your.module>` = your JPMS module name)

```xml
<!-- maven-compiler-plugin -->
<compilerArgs>
    <arg>--add-reads</arg>
    <arg><your.module>=ALL-UNNAMED</arg>
</compilerArgs>

<!-- maven-surefire-plugin argLine -->
--add-opens java.base/java.util=ALL-UNNAMED
--add-opens java.base/java.lang=ALL-UNNAMED
--add-reads <your.module>=ALL-UNNAMED
--add-opens <your.module>/<your.package>=ALL-UNNAMED

<!-- javafx-maven-plugin options (runtime) -->
<option>--add-reads</option>
<option><your.module>=ALL-UNNAMED</option>
<option>--add-opens</option>
<option>java.base/java.util=ALL-UNNAMED</option>
<option>--add-opens</option>
<option>java.base/java.lang=ALL-UNNAMED</option>
```

## Entry history field — access via reflection only

**The `history` field** (`protected List<SimpleEntry> history`) is present on `SimpleEntry` as a
JAXB-annotated field for KDBX round-tripping, but **has no public getter, setter, or adder method**.

### UUID — getter only

```java
public java.util.UUID getUuid()           // exists
public void setUuid(UUID)                 // does NOT exist

// But the field is protected:
protected java.util.UUID uuid;
// So it can be set via reflection if needed
```

UUID is initialized to `UUID.randomUUID()` in the no-arg constructor. Real KeePass history
entries share the same UUID as their live parent entry — to replicate this, either:
1. Copy the live entry's UUID via reflection to a freshly created history entry.
2. Directly manipulate the `uuid` field via reflection: `Field f = SimpleEntry.class.getDeclaredField("uuid"); f.setAccessible(true); f.set(historyEntry, liveEntry.getUuid());`

### Copy / clone — not supported

- `SimpleEntry` does NOT implement `Cloneable` (bytecode: only extends `AbstractEntry`, no additional interfaces)
- No `clone()` method exists
- No copy constructor
- `SimpleDatabase.newEntry()` is the only creation path — there is no `newEntry(Entry)` overload that copies fields

Building a history snapshot requires:
1. Create a fresh entry: `SimpleEntry snapshot = db.newEntry()`
2. Copy all fields manually: `snapshot.setTitle(live.getTitle()), snapshot.setUsername(live.getUsername()), …`
3. Copy the UUID via reflection: `uuidField.set(snapshot, live.getUuid())`
4. Access the history list via reflection and add the snapshot

### All public setter methods on SimpleEntry (including inherited)

From `AbstractEntry` contract:
```java
setTitle(String)
setUsername(String)
setPassword(String)
setUrl(String)
setNotes(String)
setExpires(boolean)
setExpiryTime(Date)
setIcon(SimpleIcon) / setIcon(Icon)     // two overloads
```

From `SimpleEntry` itself:
```java
setProperty(String key, String value)      // for custom properties
setBinaryProperty(String key, byte[] value)
removeProperty(String key)
removeBinaryProperty(String key)
```

`touch()` is `protected` (not public) — auto-invoked by any field setter, updates `LastModificationTime`.

### Timestamps (read-only in public API)

```java
entry.getCreationTime()           // public
entry.getLastModificationTime()   // public (auto-updated on field writes)
entry.getLastAccessTime()         // public
```

All returned as `java.util.Date`; truncated to seconds by `Times` constructor.

### `<History>` round-trips but has no public API — reflection required

`SimpleEntry` declares (directly, not inherited — confirmed via `javap` on the
jar, not just source): `protected UUID uuid` and `protected List<SimpleEntry>
history` (`@ElementList(name="History", required=false)`, SimpleXML not JAXB).
The XML **does** serialize/deserialize on save/load — a KDBX file with
pre-existing `<History>` from real KeePass round-trips correctly — but there
is no getter/setter/adder for either field, no `setUuid`, no `clone()`, no
copy constructor, and `SimpleDatabase.newEntry()` has only a no-arg signature.

To build and append a history snapshot from application code:
```java
Field uuidF = SimpleEntry.class.getDeclaredField("uuid");
uuidF.setAccessible(true);
uuidF.set(snapshotEntry, liveEntry.getUuid());   // real KeePass history shares the parent's UUID

Field histF = SimpleEntry.class.getDeclaredField("history");
histF.setAccessible(true);
@SuppressWarnings("unchecked")
List<SimpleEntry> hist = (List<SimpleEntry>) histF.get(liveEntry);
if (hist == null) { hist = new ArrayList<>(); histF.set(liveEntry, hist); }
hist.add(snapshotEntry);   // build snapshotEntry via db.newEntry() + the public setters
```
No `--add-opens` needed beyond the existing `--add-reads
<your-module>=ALL-UNNAMED` — KeePassJava2 is classpath/unnamed-module, which
already grants full reflective access. Wrap in try/catch
`ReflectiveOperationException` and degrade to a no-op; don't let a future
library version renaming these fields break the save/edit path.

Internal storage order is whatever you append in (oldest-first is the natural
choice, matching real KeePass); present newest-first to callers by reversing
a copy, not the live list. Historical entries' `getLastModificationTime()`
reads as snapshot-capture time, not the entry's true original timestamp —
the real per-revision timestamp lives on an internal `Times` object reachable
only via package-protected accessors with no confirmed field shape; not worth
another speculative reflection layer unless a real need shows up.
