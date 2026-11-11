#!/usr/bin/env python3
"""Package an already built production Web app and an allowlist of server files.

No network access, server changes, .env files, private prompts or customer data.
"""

import argparse
import hashlib
from pathlib import Path
import tarfile


ROOT = Path(__file__).resolve().parents[1]


def release_files(root: Path, web_root: Path):
    required_web = ("index.html", "main.dart.js", "flutter_bootstrap.js")
    for name in required_web:
        if not (web_root / name).is_file():
            raise ValueError(f"Missing production Web file: {name}")
    # Fail closed: do not accidentally ship the local development build.
    main = (web_root / "main.dart.js").read_text(encoding="utf-8")
    if "http://127.0.0.1:8000" in main or "http://localhost:8000" in main:
        raise ValueError("Local API address in Web build; rebuild with --dart-define=API_BASE_URL=")
    files = [(p, "web/" + p.relative_to(web_root).as_posix()) for p in sorted(web_root.rglob("*")) if p.is_file() and p.name != ".last_build_id"]
    files += [(p, p.relative_to(root).as_posix()) for p in sorted((root / "backend/app").glob("*.py"))]
    server_files = [
        "backend/requirements.txt", "backend/prompts/royal_brick.txt",
        "backend/prompts/response_contract.txt", "backend/prompts/prepare_transcript.txt", "scripts/with_timeout.py",
        "deploy/royal-brick.service", "deploy/nginx-http.conf.template",
        "deploy/nginx-https.conf.template", "deploy/backend.env.example",
        "deploy/README.md",
    ]
    files += [(root / name, name) for name in server_files]
    for source, name in files:
        if source.is_symlink() or not source.is_file():
            raise ValueError(f"Not a regular release file: {name}")
        if name.startswith("web/") and (any(part.startswith(".") for part in Path(name).parts) or name.endswith((".local.txt", ".env"))):
            raise ValueError(f"Private file in Web build: {name}")
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web", type=Path, default=ROOT / "build/production-web")
    parser.add_argument("--output", type=Path, default=ROOT / "build/royal-brick-release.tar.gz")
    args = parser.parse_args()
    files = release_files(ROOT, args.web.resolve())
    if args.output.exists():
        parser.error("Output already exists; choose another --output or move the previous archive.")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(args.output, "w:gz") as archive:
        for source, name in files:
            archive.add(source, arcname=name, recursive=False)
    print(f"Release archive: {args.output} ({len(files)} files, no secrets or customer recordings)")
    with args.output.open("rb") as source:
        print(f"SHA256: {hashlib.file_digest(source, 'sha256').hexdigest()}")


if __name__ == "__main__":
    main()
