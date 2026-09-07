---
name: mvn-build
description: >
  Use when asked to build, compile, or package a Maven project or module.
  Targets the specified module directly — never runs full reactor unless
  explicitly asked.
---
# Maven Build

Run one of:
  bash ~/.claude/skills/mvn-build/build.sh                   # current dir module
  bash ~/.claude/skills/mvn-build/build.sh mono-quarkus      # main app module
  bash ~/.claude/skills/mvn-build/build.sh data-ebean        # data module
  bash ~/.claude/skills/mvn-build/build.sh --reactor         # full reactor (explicit only)

Module names: core-api, data-ebean, data-hibernate, mono-quarkus, workflow-core

After module changes (data-ebean, workflow-core) always do a full install:
  bash ~/.claude/skills/mvn-build/build.sh --reactor

Report:
- Exit status (OK / FAILED)
- Build duration
- Any [ERROR] lines verbatim, nothing else
