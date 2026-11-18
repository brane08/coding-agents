---
name: pull-sources
description: Pull a library's -sources.jar into ~/.m2/repository with a per-GAV attempt limit. Use when a library has no sources jar to read (instead of decompiling or javap), then read the sources jar.
compatibility: Requires bash and Maven (mvn) on PATH, and network access.
metadata:
  version: "1.0"
---
# Pull library sources

```
bash ~/.agents/skills/pull-sources/pull.sh <groupId:artifactId:version>
```

- Network call (`mvn dependency:get`).
- Every attempt is logged to `<project>/.agents/logs/pull-sources.log` (self-ignoring dir). After 2 failed
  attempts for the same GAV it exits 3: stop, tell the user, and ask whether decompiling/`javap` is OK.
- Exit 0 = sources present (read them with `unzip -p <artifact>-<version>-sources.jar <path/Class.java>`);
  1 = pull failed; 2 = bad GAV.

Report: exit status and the pulled path, or the last `[ERROR]` lines. Nothing else.
