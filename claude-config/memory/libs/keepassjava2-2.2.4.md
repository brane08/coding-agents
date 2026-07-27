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
