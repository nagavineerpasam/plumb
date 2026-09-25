import os
import zipfile

from writing_signals import worker


def make_model_zip(path):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("model.safetensors", b"x" * 50_000)
        z.writestr("rl_agent_config.json", "{}")
        z.writestr("tokenizer/tokenizer.json", "{}")


def test_first_launch_downloads_and_unpacks_the_model_with_progress(tmp_path, monkeypatch):
    source = tmp_path / "plumb-model.zip"
    make_model_zip(source)
    target = tmp_path / "support" / "model"
    monkeypatch.setattr(worker, "MODEL_DIR", str(target))
    monkeypatch.setattr(worker, "MODEL_URL", source.as_uri())
    events = []

    worker.ensure_models(events.append)

    assert (target / "model.safetensors").stat().st_size == 50_000
    assert (target / "tokenizer" / "tokenizer.json").exists()
    assert events[-1] == {"type": "progress", "downloaded": source.stat().st_size, "total": source.stat().st_size}
    assert not any(p.name.endswith(".part") for p in (tmp_path / "support").iterdir())


def test_an_interrupted_download_resumes(tmp_path, monkeypatch):
    source = tmp_path / "plumb-model.zip"
    make_model_zip(source)
    target = tmp_path / "support" / "model"
    target.parent.mkdir()
    data = source.read_bytes()
    (target.parent / "plumb-model.zip.part").write_bytes(data[: len(data) // 2])  # half-way
    monkeypatch.setattr(worker, "MODEL_DIR", str(target))
    monkeypatch.setattr(worker, "MODEL_URL", source.as_uri())
    events = []

    worker.ensure_models(events.append)

    assert (target / "model.safetensors").exists()
    assert events[0]["downloaded"] >= len(data) // 2  # started from where it stopped


def test_nothing_is_downloaded_when_the_model_is_installed(tmp_path, monkeypatch):
    target = tmp_path / "model"
    target.mkdir()
    (target / "model.safetensors").write_bytes(b"x")
    monkeypatch.setattr(worker, "MODEL_DIR", str(target))
    monkeypatch.setattr(worker, "MODEL_URL", "https://invalid.example/never")
    events = []

    worker.ensure_models(events.append)

    assert events == []
