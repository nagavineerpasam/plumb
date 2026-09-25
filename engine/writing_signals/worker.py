"""Signal worker: newline-delimited JSON over stdin/stdout, started by the app.

App -> worker: {"type": "score", "id", "sentences": [{"id", "text"}]} and {"type": "shutdown"}.
Worker -> app: ready, progress, result, error. See the spec for the full contract.
"""
import json
import os
import queue
import sys
import threading
import time
from typing import Callable, Dict, List

from .catalogue import CATALOGUE_VERSION

BUNDLE_REPO = "convaiinnovations/laya"
# Only what the English checkpoint needs; the bundle repo also holds other models and images.
MODEL_FILES = ["model.safetensors", "rl_agent_config.json", "encoder/*", "tokenizer/*"]


def ensure_models(emit: Callable[[dict], None]) -> None:
    """Fetch the English checkpoint once, reporting bytes as they arrive."""
    from huggingface_hub import HfApi, hf_hub_download
    from huggingface_hub.utils import filter_repo_objects

    try:  # Already cached: no network needed, so later launches work offline.
        from huggingface_hub import snapshot_download
        snapshot_download(BUNDLE_REPO, allow_patterns=MODEL_FILES, local_files_only=True)
        return
    except Exception:
        pass

    info = HfApi().model_info(BUNDLE_REPO, files_metadata=True)
    files = {s.rfilename: s.size or 0 for s in info.siblings}
    wanted = list(filter_repo_objects(files, allow_patterns=MODEL_FILES))
    total = sum(files[f] for f in wanted)
    done = 0
    stop = threading.Event()

    def report():
        blobs = None
        while not stop.wait(0.5):
            if blobs is None:
                from huggingface_hub.constants import HF_HUB_CACHE
                blobs = os.path.join(HF_HUB_CACHE, "models--" + BUNDLE_REPO.replace("/", "--"), "blobs")
            partial = 0
            if os.path.isdir(blobs):
                partial = sum(os.path.getsize(os.path.join(blobs, n))
                              for n in os.listdir(blobs) if n.endswith(".incomplete"))
            emit({"type": "progress", "downloaded": min(done + partial, total), "total": total})

    reporter = threading.Thread(target=report, daemon=True)
    reporter.start()
    try:
        for name in wanted:
            hf_hub_download(BUNDLE_REPO, name)  # resumes a partial download on retry
            done += files[name]
    finally:
        stop.set()
    emit({"type": "progress", "downloaded": total, "total": total})


def _plan(batch: List[dict]) -> List[List[dict]]:
    """For each request, the sentences it still owns: a later request with the same
    sentence id supersedes the older text, which is then never scored."""
    latest: Dict[str, int] = {}
    for i, request in enumerate(batch):
        for sentence in request["sentences"]:
            latest[sentence["id"]] = i
    return [[s for s in request["sentences"] if latest[s["id"]] == i]
            for i, request in enumerate(batch)]


def _valid(message) -> bool:
    return (isinstance(message, dict) and message.get("type") == "score"
            and isinstance(message.get("id"), str) and isinstance(message.get("sentences"), list)
            and all(isinstance(s, dict) and isinstance(s.get("id"), str) and isinstance(s.get("text"), str)
                    for s in message["sentences"]))


def main() -> int:
    protocol = sys.stdout
    sys.stdout = sys.stderr  # library chatter must never corrupt the protocol stream
    lock = threading.Lock()

    def emit(message: dict) -> None:
        with lock:
            protocol.write(json.dumps(message, ensure_ascii=False) + "\n")
            protocol.flush()

    inbox: "queue.Queue" = queue.Queue()

    def read():
        for line in sys.stdin:
            if not line.strip():
                continue
            try:
                message = json.loads(line)
            except ValueError as exc:
                emit({"type": "error", "id": None, "message": f"invalid JSON: {exc}"})
                continue
            if isinstance(message, dict) and message.get("type") == "shutdown":
                break
            if not _valid(message):
                request_id = message.get("id") if isinstance(message, dict) else None
                emit({"type": "error", "id": request_id, "message": "expected a score request with id and sentences"})
                continue
            inbox.put(message)
        inbox.put(None)

    # Read from the start so requests sent while we load queue up and can supersede each other.
    threading.Thread(target=read, daemon=True).start()

    try:
        ensure_models(emit)
        from .engine import SignalEngine
        engine = SignalEngine()
    except Exception as exc:
        emit({"type": "error", "id": None, "message": f"could not load models: {exc}"})
        return 1
    emit({"type": "ready", "catalogue_version": CATALOGUE_VERSION})

    while True:
        batch = [inbox.get()]
        while True:
            try:
                batch.append(inbox.get_nowait())
            except queue.Empty:
                break
        closing = None in batch
        batch = [m for m in batch if m is not None]
        if batch:
            owned = _plan(batch)
            flat = [s for sentences in owned for s in sentences]
            try:
                scored = dict(zip((s["id"] for s in flat), engine.score([s["text"] for s in flat])))
            except Exception as exc:
                for request in batch:
                    emit({"type": "error", "id": request["id"], "message": str(exc)})
            else:
                for request, sentences in zip(batch, owned):
                    emit({"type": "result", "id": request["id"],
                          "sentences": {s["id"]: scored[s["id"]] for s in sentences}})
        if closing:
            return 0


if __name__ == "__main__":
    sys.exit(main())
