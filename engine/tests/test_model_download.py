import os
import zipfile

import pytest

from writing_signals import worker


def make_model_zip(path):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("plumb_model.json", '{"catalogue": "4", "run": 4}')
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
    (target / "plumb_model.json").write_text('{"catalogue": "4", "run": 4}')
    monkeypatch.setattr(worker, "MODEL_DIR", str(target))
    monkeypatch.setattr(worker, "MODEL_URL", "https://invalid.example/never")
    events = []

    worker.ensure_models(events.append)

    assert events == []


def test_an_older_model_is_replaced_by_the_current_one(tmp_path, monkeypatch):
    source = tmp_path / "plumb-model.zip"
    make_model_zip(source)
    target = tmp_path / "support" / "model"
    target.mkdir(parents=True)
    (target / "model.safetensors").write_bytes(b"old")  # run 2: no plumb_model.json
    monkeypatch.setattr(worker, "MODEL_DIR", str(target))
    monkeypatch.setattr(worker, "MODEL_URL", source.as_uri())

    worker.ensure_models(lambda e: None)

    assert (target / "model.safetensors").stat().st_size == 50_000
    assert (target / "plumb_model.json").exists()


def test_a_run_3_model_is_upgraded_to_run_4(tmp_path, monkeypatch):
    source = tmp_path / "plumb-model.zip"
    make_model_zip(source)
    target = tmp_path / "support" / "model"
    target.mkdir(parents=True)
    (target / "model.safetensors").write_bytes(b"run3")
    (target / "plumb_model.json").write_text('{"catalogue": "3", "run": 3}')
    monkeypatch.setattr(worker, "MODEL_DIR", str(target))
    monkeypatch.setattr(worker, "MODEL_URL", source.as_uri())

    worker.ensure_models(lambda e: None)

    assert '"run": 4' in (target / "plumb_model.json").read_text()


def test_if_the_upgrade_cant_download_the_older_model_keeps_working(tmp_path, monkeypatch):
    target = tmp_path / "support" / "model"
    target.mkdir(parents=True)
    (target / "model.safetensors").write_bytes(b"old")
    monkeypatch.setattr(worker, "MODEL_DIR", str(target))
    monkeypatch.setattr(worker, "MODEL_URL", (tmp_path / "missing.zip").as_uri())

    worker.ensure_models(lambda e: None)  # no exception: Plumb starts on the model it has

    assert (target / "model.safetensors").read_bytes() == b"old"


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
