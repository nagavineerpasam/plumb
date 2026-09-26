import os
import zipfile

import pytest

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

    assert events[0] == {"type": "stage", "stage": "downloading"}  # the app shows setup at once
    assert (target / "model.safetensors").stat().st_size == 50_000
    assert (target / "tokenizer" / "tokenizer.json").exists()
    size = source.stat().st_size
    assert events[-2:] == [{"type": "progress", "downloaded": size, "total": size},
                           {"type": "stage", "stage": "unpacking"}]  # so the app never looks stuck at 100%
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
    assert events[1]["downloaded"] >= len(data) // 2  # started from where it stopped


def test_nothing_is_downloaded_when_the_model_is_installed(tmp_path, monkeypatch):
    target = tmp_path / "model"
    target.mkdir()
    (target / "model.safetensors").write_bytes(b"x")
    monkeypatch.setattr(worker, "MODEL_DIR", str(target))
    monkeypatch.setattr(worker, "MODEL_URL", "https://invalid.example/never")
    events = []

    worker.ensure_models(events.append)

    assert events == []


def test_a_damaged_partial_download_is_thrown_away_and_downloaded_again(tmp_path, monkeypatch):
    source = tmp_path / "plumb-model.zip"
    make_model_zip(source)
    target = tmp_path / "support" / "model"
    target.parent.mkdir()
    part = target.parent / "plumb-model.zip.part"
    data = source.read_bytes()
    part.write_bytes(data[: len(data) // 2] + b"x" * len(data))  # longer than the model, garbled
    monkeypatch.setattr(worker, "MODEL_DIR", str(target))
    monkeypatch.setattr(worker, "MODEL_URL", source.as_uri())

    with pytest.raises(Exception):
        worker.ensure_models(lambda _: None)
    assert not part.exists(), "the bad partial file is gone, so the next try starts fresh"

    worker.ensure_models(lambda _: None)
    assert (target / "model.safetensors").exists()
