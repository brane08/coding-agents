---
name: mvn-build
description: Build, compile or package a Maven project or module and report a one-line verdict plus the [ERROR] lines. Use when asked to build, compile or package. Builds the named module and its upstream modules (-am); runs the full reactor only with --reactor, when asked, or after changes to data-ebean or workflow-core.
compatibility: Requires bash and Maven (mvn) on PATH.
metadata:
  version: "1.0"
---
# Maven Build

Run one of (from the repo root; at a reactor root a module or `--reactor` is required):

```
bash ~/.agents/skills/mvn-build/build.sh mono-quarkus      # main app module
bash ~/.agents/skills/mvn-build/build.sh data-ebean        # data module
bash ~/.agents/skills/mvn-build/build.sh --reactor         # full reactor
```

Module names: core-api, data-ebean, data-hibernate, mono-quarkus, workflow-core.

After changes to data-ebean or workflow-core, run the full reactor (package only, nothing is installed to `~/.m2`).
If a separate `quarkus:dev` needs the new jars in `~/.m2`: `mvn install -DskipTests -pl <module> -am`.

Extra `-flags` are passed to `mvn` as separate arguments (never evaluated by a shell). The full output is in
`<project>/.agents/logs/mvn-build.log` (self-ignoring dir); read it there, not from `/tmp`.

Report:
- Exit status (OK / FAILED)
- Build duration
- Any `[ERROR]` lines verbatim, nothing else
