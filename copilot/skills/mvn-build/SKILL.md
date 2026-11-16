---
name: mvn-build
description: >
  Use when asked to build, compile, or package a Maven project or module.
  Builds the specified module plus its upstream modules (-am). Runs the full reactor
  only when asked, or after changes to data-ebean or workflow-core.
---
# Maven Build

Run one of:
  bash ~/.copilot/skills/mvn-build/build.sh mono-quarkus      # main app module (with -am)
  bash ~/.copilot/skills/mvn-build/build.sh data-ebean        # data module (with -am)
  bash ~/.copilot/skills/mvn-build/build.sh --reactor         # full reactor (when asked, or after data-ebean/workflow-core changes)

Module names (examples; the real list is the root pom's `<modules>`): core-api, data-ebean, data-hibernate, mono-quarkus, workflow-core

`--reactor` only runs `package`; nothing is installed to ~/.m2. After changes to data-ebean or workflow-core, run `--reactor` to check the whole build, and `mvn install -DskipTests -pl <module> -am` when a separately started module (e.g. `quarkus:dev`) must pick up the new jars.

Report:
- Exit status (OK / FAILED)
- Build duration
- Any [ERROR] lines verbatim, nothing else
