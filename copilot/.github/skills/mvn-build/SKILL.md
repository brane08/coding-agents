---
name: mvn-build
description: >
  Use when asked to build, compile, or package a Maven project or module.
  Targets the specified module directly. Runs the full reactor only when asked,
  or after changes to data-ebean or workflow-core.
---
# Maven Build

Run one of:
  bash .github/skills/mvn-build/build.sh mono-quarkus      # main app module (with -am)
  bash .github/skills/mvn-build/build.sh data-ebean        # data module (with -am)
  bash .github/skills/mvn-build/build.sh --reactor         # full reactor (when asked, or after data-ebean/workflow-core changes)

Module names: core-api, data-ebean, data-hibernate, mono-quarkus, workflow-core

`--reactor` only runs `package`; it does not install jars to ~/.m2. After changes to data-ebean or workflow-core, run `mvn install -DskipTests -pl <module> -am` so modules built alone pick up the new jars.

Report:
- Exit status (OK / FAILED)
- Build duration
- Any [ERROR] lines verbatim, nothing else
