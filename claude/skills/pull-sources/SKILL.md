---
name: pull-sources
description: >
  Use when a library has no `-sources.jar` in ~/.m2/repository (e.g. jar-inspect replied
  "no sources jar for <gav>"). Pulls the sources jar with a per-GAV attempt limit.
---
# Pull library sources

  bash ~/.claude/skills/pull-sources/pull.sh <groupId:artifactId:version>

- Network call (`mvn dependency:get`); may prompt once.
- Every attempt is logged to `<project>/.claude/logs/pull-sources.log`. After 2 failed
  attempts for the same GAV it exits 3: stop, tell the user, and ask whether `javap` is OK.
- Exit 0 = sources present (re-dispatch `jar-inspect`); 1 = pull failed; 2 = bad GAV.

Report: exit status and the pulled path, or the last [ERROR] lines. Nothing else.
