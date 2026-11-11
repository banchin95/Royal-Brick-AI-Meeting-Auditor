"""Release packaging must not upload developer secrets or customer material."""

import pytest

from scripts.package_release import ROOT, release_files


def make_web(tmp_path, main="production same-origin API"):
    web = tmp_path / "web"
    web.mkdir()
    for name in ("index.html", "flutter_bootstrap.js"):
        (web / name).write_text("public", encoding="utf-8")
    (web / "main.dart.js").write_text(main, encoding="utf-8")
    return web


def test_only_public_server_files_are_packaged(tmp_path):
    web = make_web(tmp_path)
    (web / ".last_build_id").write_text("Flutter build metadata", encoding="utf-8")
    files = release_files(ROOT, web)
    names = [name for _, name in files]
    assert "web/main.dart.js" in names
    assert "backend/app/main.py" in names
    assert "backend/prompts/response_contract.txt" in names
    assert "backend/prompts/prepare_transcript.txt" in names
    assert "deploy/royal-brick.service" in names
    assert "web/.last_build_id" not in names
    assert not any(name.startswith(("private-data/", "backend/.venv/")) for name in names)
    assert not any(".env.local" in name or name.endswith(".local.txt") for name in names)
    assert not any(name.endswith((".m4a", ".mp3", ".wav")) for name in names)


def test_development_build_is_rejected(tmp_path):
    with pytest.raises(ValueError, match="Local API address"):
        release_files(ROOT, make_web(tmp_path, "http://127.0.0.1:8000"))


def test_private_file_inside_web_is_rejected(tmp_path):
    web = make_web(tmp_path)
    (web / ".env.local").write_text("not-public", encoding="utf-8")
    with pytest.raises(ValueError, match="Private file"):
        release_files(ROOT, web)


def test_web_symlink_is_rejected(tmp_path):
    web = make_web(tmp_path)
    private = tmp_path / "source.txt"
    private.write_text("not-public", encoding="utf-8")
    (web / "secret.txt").symlink_to(private)
    with pytest.raises(ValueError, match="Not a regular release file"):
        release_files(ROOT, web)
