# Project tracking pattern

Covers: findings/items/decisions/reviews tracking in `memory/tracking/`, apart from knowledge notes. Token-friendly: read only the index at session start.

```
memory/
  MEMORY.md                  index of notes + one pointer to tracking/
  <notes>.md                 knowledge notes only
  tracking/
    todo.md                  INDEX + RULES: counts and last-updated date per file. No items.
    findings/                what is wrong (logs)
      design.md   DS-nnn     architecture, decisions needed
      feature.md  FE-nnn     missing capability, Day 0-4 tag
      bugs.md     BG-nnn     defect with file:line
      tests.md    TS-nnn     test gap (table)
    items/                   what we will do (tasks)
      design.md feature.md bugs.md tests.md
      archive.md             DONE history
    decisions.md  DC-nnn     choice, why, rejected alternatives, status
    review.md     RV-nnn     scope, reviewer model, outcome, not-checked caveats, findings produced
```

## Rules (defined only in tracking/todo.md; CLAUDE.md and MEMORY.md just point to it)
- IDs: 2-letter code + 3-digit number, assigned in order of placement, never renumbered. A new entry takes the next number in its log.
- Item line: `- STATE: text (see findings/bugs.md#BG-014) | logged: YYYY-MM-DD | started: YYYY-MM-DD or - | closed: YYYY-MM-DD or -`
- States: DOING, BLOCKED, PARTIAL, PENDING, BACKLOG, DEFERRED, DONE, WONT-DO (WONT-DO sits in the DONE section).
  - PARTIAL: some work shipped, defined remainder open; text says "done: … / left: …"; started set, closed `-`.
  - PENDING: committed, next up. BACKLOG: accepted, not scheduled/reviewed (default for untiered and low-Day items); moves to PENDING when scheduled.
  - DEFERRED: deliberate postponement; item line adds `| revisit: <date or trigger>`; log a DC-nnn when it is a real choice. Not counted as open work.
- Item file sections: DOING, BLOCKED, PARTIAL, PENDING, BACKLOG, DEFERRED, DONE, Notes. Sort by Day (0 first, untiered last), then ID.
- Finishing a PARTIAL item's remainder makes it DONE; follow-up found while closing an item becomes a new item.
- todo.md table has one count column per state (DONE includes WONT-DO).
- Missing dates default to the date the file is touched.
- Per task: set DONE + closed date (and the finding's status, below); promote at most one PENDING→DOING + started date; update that file's row in todo.md (counts, date) in the same edit.
- Archive: when a file's DONE section reaches 30 items, move them all to items/archive.md and update the todo.md row.
  - Append under `## Archived from <file> on <date>`; keep each full item line unchanged (closed date and finding link included) so an old task is found by its ID.
  - Archiving runs whenever the file is next touched; a file may sit above 30 until then.
  - When archive.md passes ~500 lines, split by year (`archive-YYYY.md`) and list the files in the todo.md table.
  - Finding logs, decisions and reviews are never archived (IDs stay stable).
- When an item goes DONE/WONT-DO, set the finding's status in the same edit: add `Status: FIXED|WONT-DO YYYY-MM-DD` under that finding in its log (tests.md: Status column).
- Every flaw goes in a findings log; every task links to its finding ID.
- Log a decision when a choice changes how we build, track or review. Log every review, with what was not checked.
- Paths inside tracking/ are relative to tracking/; notes in the memory root are referenced as `../<name>.md`.

## Session use
- Read MEMORY.md and tracking/todo.md first.
- Open item files and finding logs by ID or line range; never load the archive, grep it by ID.
- Keep item lines short: one sentence plus a link to the finding.

## Setup in a new project
1. Create the folders and todo.md (table: one row per file with PENDING/DOING/BLOCKED/DONE counts and Last updated, plus these rules).
2. In project CLAUDE.md and MEMORY.md add one line: "Tracking pattern: tracking/todo.md § Tracking pattern. Do not restate it."
3. Git-track only `.claude/memory/`.
4. Route agent work by model: Opus reasons; haiku does searches, inventories, file restructuring and count checks.
