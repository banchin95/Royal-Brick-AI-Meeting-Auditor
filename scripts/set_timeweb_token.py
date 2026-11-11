#!/usr/bin/env python3
"""Save an AI Gateway token locally with hidden input and no secret output."""

from getpass import getpass
import os
from pathlib import Path
import re
import sys


def main():
    if not sys.stdin.isatty():
        raise SystemExit("Запустите эту команду в обычном интерактивном терминале.")
    target = Path(__file__).resolve().parents[1] / "backend/.env.timeweb.local"
    if target.is_symlink():
        raise SystemExit("Refusing a symlink token file.")
    token = getpass("Новый ключ Timeweb AI Gateway (ввод скрыт): ").strip()
    if not re.fullmatch(r"sk-[A-Za-z0-9_-]{12,}", token):
        raise SystemExit("Формат ключа не распознан. Файл не изменён.")
    descriptor = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        stream.write("TIMEWEB_AI_TOKEN=" + token + "\n")
    target.chmod(0o600)
    print("Ключ сохранён только в backend/.env.timeweb.local. Значение не выводится.")


if __name__ == "__main__":
    main()
