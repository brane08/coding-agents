---
name: await-user
description: >
  Use at the end of the autonomous tracking loop, after the one-line status, to wait a short
  fixed time (default 30 s) for a user reply before ending the turn. Not for polling or
  general sleeping.
---
# Await user

Run under Monitor (foreground `sleep` is blocked):
  bash ~/.claude/skills/await-user/wait.sh <seconds>

- `<seconds>` is an integer 1..120; anything else exits 2 with a usage line.
- Prints `waited N s` when done. A user reply arrives as a new turn; none -> end the turn.
- End-of-loop use is `wait.sh 30`.
