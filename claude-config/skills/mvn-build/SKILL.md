---
name: mvn-build
description: >
  Use when asked to build, compile, or package a Maven project or module.
  Targets the specified module directly. Runs the full reactor only when asked,
  or after changes to data-ebean or workflow-core.
---
# Maven Build

Run one of:
  bash ~/.claude/skills/mvn-build/build.sh                   # current dir module
  bash ~/.claude/skills/mvn-build/build.sh mono-quarkus      # main app module
  bash ~/.claude/skills/mvn-build/build.sh data-ebean        # data module
  bash ~/.claude/skills/mvn-build/build.sh --reactor         # full reactor (when asked, or after data-ebean/workflow-core changes)

Module names: core-api, data-ebean, data-hibernate, mono-quarkus, workflow-core

After changes to data-ebean or workflow-core, run a full install so dependent modules pick up the new jars:
  bash ~/.claude/skills/mvn-build/build.sh --reactor

Report:
- Exit status (OK / FAILED)
- Build duration
- Any [ERROR] lines verbatim, nothing else
