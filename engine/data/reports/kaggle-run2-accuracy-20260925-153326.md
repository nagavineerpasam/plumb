# Accuracy check (20260925-153326)

Catalogue v2 · x86_64 Linux · 2 CPU threads · samples: {'cola': 1043, 'dair': 2000, 'claude-draft': 1000, 'note': 'full splits'}

| signal | judged on | n | accuracy | bar | majority baseline | result |
|---|---|---|---|---|---|---|
| grammar | cola | 1043 | 0.700 | 0.75 | 0.691 | FAIL |
| sense | claude-draft | 200 | 0.610 | 0.75 | 0.500 | FAIL |
| emotion | dair | 2000 | 0.564 | 0.55 | 0.427 | PASS |
| tone | claude-draft | 200 | 0.635 | 0.70 | 0.250 | FAIL |
| formality | claude-draft | 150 | 0.600 | 0.70 | 0.333 | FAIL |
| confidence | claude-draft | 150 | 0.707 | 0.70 | 0.333 | PASS |
| clarity | claude-draft | 150 | 0.413 | 0.70 | 0.333 | FAIL |
| flow | claude-draft | 200 | 0.780 | 0.75 | – | PASS |

Grammar, informational: best yes-probability threshold on CoLA is 0.40 → accuracy 0.708 (tuned on the same set, so optimistic).

## Per source

- grammar: claude-draft 0.510 (n=100), cola 0.700 (n=1043)
- sense: claude-draft 0.610 (n=200)
- emotion: claude-draft 0.940 (n=50), dair 0.564 (n=2000)
- tone: claude-draft 0.635 (n=200)
- formality: claude-draft 0.600 (n=150)
- confidence: claude-draft 0.707 (n=150)
- clarity: claude-draft 0.413 (n=150)

## Latency (one call per sentence, all six signals, cuda)

- calls: 40, p50 56 ms, p95 58 ms

Checkpoint: convaiinnovations/laya @ 55cf4c4ebb4ebe31b2550e8bdf3bd21b99753851

The drafted English set is a DRAFT until the developer reviews it; results on it are provisional.
