# Accuracy check (20260925-155906)

Catalogue v2 · x86_64 Linux · 2 CPU threads · samples: {'cola': 1043, 'dair': 2000, 'claude-draft': 1000, 'note': 'full splits'}

| signal | judged on | n | accuracy | bar | majority baseline | result |
|---|---|---|---|---|---|---|
| grammar | cola | 1043 | 0.775 | 0.75 | 0.691 | PASS |
| sense | claude-draft | 200 | 0.940 | 0.75 | 0.500 | PASS |
| emotion | dair | 2000 | 0.906 | 0.55 | 0.427 | PASS |
| tone | claude-draft | 200 | 0.975 | 0.70 | 0.250 | PASS |
| formality | claude-draft | 150 | 0.973 | 0.70 | 0.333 | PASS |
| confidence | claude-draft | 150 | 0.947 | 0.70 | 0.333 | PASS |
| clarity | claude-draft | 150 | 0.900 | 0.70 | 0.333 | PASS |
| flow | claude-draft | 200 | 0.885 | 0.75 | – | PASS |

Grammar, informational: best yes-probability threshold on CoLA is 0.88 → accuracy 0.805 (tuned on the same set, so optimistic).

## Per source

- grammar: claude-draft 0.920 (n=100), cola 0.775 (n=1043)
- sense: claude-draft 0.940 (n=200)
- emotion: claude-draft 1.000 (n=50), dair 0.906 (n=2000)
- tone: claude-draft 0.975 (n=200)
- formality: claude-draft 0.973 (n=150)
- confidence: claude-draft 0.947 (n=150)
- clarity: claude-draft 0.900 (n=150)

## Latency (one call per sentence, all six signals, cuda)

- calls: 40, p50 57 ms, p95 59 ms

Checkpoint: /kaggle/working/laya-writing-signals @ None

The drafted English set is a DRAFT until the developer reviews it; results on it are provisional.
