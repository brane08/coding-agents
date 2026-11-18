---
name: mvn-build
description: >
  Use when asked to build, compile, or package a Maven project or module.
  Builds the specified module plus its upstream modules (-am). Runs the full reactor
  only when asked, or after changes to data-ebean or workflow-core.
---
# Maven Build

Run one of (from the repo root; at a reactor root a module or --reactor is required):
  bash ~/.claude/skills/mvn-build/build.sh mono-quarkus      # main app module
  bash ~/.claude/skills/mvn-build/build.sh data-ebean        # data module
  bash ~/.claude/skills/mvn-build/build.sh --reactor         # full reactor (when asked, or after data-ebean/workflow-core changes)

Module names (examples; the real list is the root pom's `<modules>`): core-api, data-ebean, data-hibernate, mono-quarkus, workflow-core

After changes to data-ebean or workflow-core, run the full reactor (package only, nothing is installed to ~/.m2):
  bash ~/.claude/skills/mvn-build/build.sh --reactor
If a separate `quarkus:dev` needs the new jars in ~/.m2: `mvn install -DskipTests -pl <module> -am`.

After a successful build it also runs `mvn dependency:sources` (best effort, once per pom change; never affects the
build result; `PULL_SOURCES=0` skips it), so `-sources.jar` files are in `~/.m2` for library inspection.

Report:
- Exit status (OK / FAILED)
- Build duration
- Any [ERROR] lines verbatim, nothing else
