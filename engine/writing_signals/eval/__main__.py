"""python -m writing_signals.eval: run the accuracy check and save the report."""
import argparse
import json
import os
import platform
import random
import time

from .. import CATALOGUE_VERSION, SignalEngine
from .check import measure_latency, predict, summarise
from .datasets import DATA_DIR, load_cola, load_dair, load_drafted


def _checkpoint():
    from huggingface_hub import snapshot_download
    from ..engine import CHECKPOINT
    from ..worker import MODEL_FILES
    try:
        revision = os.path.basename(snapshot_download(CHECKPOINT, allow_patterns=MODEL_FILES, local_files_only=True))
    except Exception:
        revision = None
    return {"repo": CHECKPOINT, "revision": revision}


def _markdown(report) -> str:
    lines = [f"# Accuracy check ({report['timestamp']})", "",
             f"Catalogue v{report['catalogue_version']} · {report['machine']} · {report['threads']} CPU threads · "
             f"samples: {report['samples']}", "",
             "| signal | judged on | n | accuracy | bar | majority baseline | result |",
             "|---|---|---|---|---|---|---|"]
    for name, s in report["signals"].items():
        lines.append(f"| {name} | {s['bar_source']} | {s['n']} | {s['accuracy']:.3f} | {s['bar']:.2f} | "
                     f"{s['majority_baseline']:.3f} | {'PASS' if s['pass'] else 'FAIL'} |")
    g = report["signals"]["grammar"].get("best_threshold")
    if g:
        lines += ["", f"Grammar, informational: best yes-probability threshold on CoLA is {g['threshold']:.2f} "
                      f"→ accuracy {g['accuracy']:.3f} (tuned on the same set, so optimistic)."]
    lines += ["", "## Per source", ""]
    for name, s in report["signals"].items():
        lines.append(f"- {name}: " + ", ".join(f"{src} {v['accuracy']:.3f} (n={v['n']})" for src, v in s["by_source"].items()))
    lat = report["latency"]
    lines += ["", f"## Latency (one call per sentence, all six signals, {report['device']})", "",
              f"- calls: {lat['calls']}, p50 {lat['p50_ms']:.0f} ms, p95 {lat['p95_ms']:.0f} ms",
              "", f"Checkpoint: {report['checkpoint']['repo']} @ {report['checkpoint']['revision']}",
              "", "The drafted English set is a DRAFT until the developer reviews it; results on it are provisional."]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", type=int, default=300,
                        help="seeded sample size for CoLA and DAIR (0 = full split)")
    parser.add_argument("--threads", type=int, default=4,
                        help="CPU threads; the default keeps the laptop cool")
    parser.add_argument("--checkpoint", default=None, help="model repo or folder (default: the app's)")
    parser.add_argument("--device", default="cpu")
    args = parser.parse_args()
    import torch
    torch.set_num_threads(args.threads)

    cola, dair, drafted = load_cola(), load_dair(), load_drafted()
    if args.sample:
        rng = random.Random(13)
        cola, dair = rng.sample(cola, min(args.sample, len(cola))), rng.sample(dair, min(args.sample, len(dair)))

    from ..engine import CHECKPOINT, default_checkpoint
    checkpoint = args.checkpoint or default_checkpoint()
    engine = SignalEngine(checkpoint, device=args.device)
    started = time.time()
    rows = predict(engine, cola + dair + drafted)
    signals = summarise(rows)
    latency = measure_latency(engine, [e["sentence"] for e in random.Random(13).sample(drafted, min(40, len(drafted)))])

    stamp = time.strftime("%Y%m%d-%H%M%S")
    report = {
        "timestamp": stamp, "catalogue_version": CATALOGUE_VERSION,
        "machine": f"{platform.machine()} {platform.mac_ver()[0] or platform.system()}",
        "threads": args.threads,
        "samples": {"cola": len(cola), "dair": len(dair), "claude-draft": len(drafted),
                    "note": f"seeded sample of {args.sample}" if args.sample else "full splits"},
        "scoring_seconds": round(time.time() - started, 1),
        "signals": signals, "latency": latency, "device": args.device,
        "checkpoint": _checkpoint() if checkpoint == CHECKPOINT else {"repo": checkpoint, "revision": None},
    }
    out_dir = os.path.join(DATA_DIR, "reports")
    os.makedirs(out_dir, exist_ok=True)
    base = os.path.join(out_dir, f"accuracy-{stamp}")
    with open(base + ".json", "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    with open(base + ".md", "w", encoding="utf-8") as f:
        f.write(_markdown(report))
    print(_markdown(report))
    print(f"Saved {base}.json and .md")


if __name__ == "__main__":
    main()
