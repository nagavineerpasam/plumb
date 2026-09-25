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

from .engine import TRAINED_DIR

# Plumb's fine-tuned model, attached to the latest GitHub release. Overridable for testing.
MODEL_URL = os.environ.get(
    "PLUMB_MODEL_URL", "https://github.com/nagavineerpasam/plumb-releases/releases/latest/download/plumb-model.zip")
MODEL_DIR = TRAINED_DIR


def ensure_models(emit: Callable[[dict], None]) -> None:
    """On first launch, download Plumb's model (resuming a partial download) and unpack it.
    Reports bytes as they arrive; does nothing once the model is installed."""
    import shutil
    import urllib.request
    import zipfile

    if os.path.exists(os.path.join(MODEL_DIR, "model.safetensors")):
        return
    parent = os.path.dirname(MODEL_DIR)
    os.makedirs(parent, exist_ok=True)
    part = os.path.join(parent, "plumb-model.zip.part")
    have = os.path.getsize(part) if os.path.exists(part) else 0

    request = urllib.request.Request(MODEL_URL, headers={"Range": f"bytes={have}-"} if have else {})
    with urllib.request.urlopen(request, timeout=60) as response:
        resumed = have and getattr(response, "status", 200) == 206
        if not resumed and not MODEL_URL.startswith("file:"):
            have = 0  # the server ignored the range: start over
        length = response.headers.get("Content-Length")
        if MODEL_URL.startswith("file:"):  # local files ignore ranges; skip what we already have
            total = os.path.getsize(urllib.request.url2pathname(MODEL_URL[len("file://"):]))
            response.read(have)
        else:
            total = have + int(length) if length else 0
        with open(part, "ab" if have else "wb") as out:
            done, last = have, 0.0
            emit({"type": "progress", "downloaded": done, "total": total})
            while chunk := response.read(1 << 20):
                out.write(chunk)
                done += len(chunk)
                now = time.monotonic()
                if now - last > 0.25:
                    emit({"type": "progress", "downloaded": done, "total": total})
                    last = now
    staging = MODEL_DIR + ".unpacking"
    shutil.rmtree(staging, ignore_errors=True)
    with zipfile.ZipFile(part) as archive:
        archive.extractall(staging)
    shutil.rmtree(MODEL_DIR, ignore_errors=True)
    os.replace(staging, MODEL_DIR)
    os.remove(part)
    size = total or done
    emit({"type": "progress", "downloaded": size, "total": size})


def _plan(batch: List[dict]) -> List[List[dict]]:
    """For each request, the sentences it still owns: a later request with the same
    sentence id supersedes the older text, which is then never scored."""
    latest: Dict[str, int] = {}
    for i, request in enumerate(batch):
        for sentence in request["sentences"]:
            latest[sentence["id"]] = i
    return [[s for s in request["sentences"] if latest[s["id"]] == i]
            for i, request in enumerate(batch)]


def _valid_flow(message) -> bool:
    return (isinstance(message, dict) and message.get("type") == "flow"
            and isinstance(message.get("id"), str) and isinstance(message.get("pairs"), list)
            and all(isinstance(p, dict) and all(isinstance(p.get(k), str) for k in ("id", "previous", "sentence"))
                    for p in message["pairs"]))


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
            if not (_valid(message) or _valid_flow(message)):
                request_id = message.get("id") if isinstance(message, dict) else None
                emit({"type": "error", "id": request_id, "message": "expected a score request (id, sentences) or a flow request (id, pairs)"})
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
        # Flow is only asked for on demand, so it is answered as it comes, never superseded.
        for request in [m for m in batch if m is not None and m["type"] == "flow"]:
            try:
                signals = engine.flow([(p["previous"], p["sentence"]) for p in request["pairs"]])
            except Exception as exc:
                emit({"type": "error", "id": request["id"], "message": str(exc)})
            else:
                emit({"type": "flow_result", "id": request["id"],
                      "sentences": {p["id"]: sig for p, sig in zip(request["pairs"], signals)}})
        batch = [m for m in batch if m is not None and m["type"] == "score"]
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
