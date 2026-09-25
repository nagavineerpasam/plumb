import json
import subprocess
import sys

import pytest


class Worker:
    """Drives the signal worker exactly as the app does: JSON lines over stdin/stdout."""

    def __init__(self):
        self.proc = subprocess.Popen(
            [sys.executable, "-m", "writing_signals.worker"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1,
        )

    def send(self, *messages):
        self.proc.stdin.write("".join(
            m if isinstance(m, str) else json.dumps(m) + "\n" for m in messages
        ))
        self.proc.stdin.flush()

    def next(self, kind):
        for line in self.proc.stdout:
            message = json.loads(line)
            if message["type"] == kind:
                return message
        raise AssertionError(f"worker exited before sending {kind!r}")

    def close(self):
        self.send({"type": "shutdown"})
        return self.proc.wait(timeout=30)


@pytest.fixture
def worker():
    w = Worker()
    yield w
    if w.proc.poll() is None:
        w.proc.kill()


def test_announces_ready_with_catalogue_version(worker):
    assert worker.next("ready")["catalogue_version"] == "1"


def test_scores_sentences_by_id(worker):
    worker.send({"type": "score", "id": "r1", "sentences": [{"id": "s1", "text": "We are happy."}]})

    result = worker.next("result")

    assert result["id"] == "r1"
    assert set(result["sentences"]) == {"s1"}
    assert result["sentences"]["s1"]["model"] == "english"
    assert "grammar" in result["sentences"]["s1"]["signals"]


def test_malformed_input_is_an_error_not_a_crash(worker):
    worker.send("this is not json\n", {"type": "score", "id": "r2"})

    assert "message" in worker.next("error")
    assert worker.next("error")["id"] == "r2"
    assert worker.close() == 0


def test_newer_request_supersedes_queued_older_text(worker):
    # Both requests are queued while the worker starts, so the older text is never scored.
    worker.send(
        {"type": "score", "id": "old", "sentences": [{"id": "s1", "text": "Draft"}, {"id": "s2", "text": "Keep me."}]},
        {"type": "score", "id": "new", "sentences": [{"id": "s1", "text": "Draft sentence, finished."}]},
    )

    old, new = worker.next("result"), worker.next("result")

    assert (old["id"], new["id"]) == ("old", "new")
    assert set(old["sentences"]) == {"s2"}
    assert set(new["sentences"]) == {"s1"}
