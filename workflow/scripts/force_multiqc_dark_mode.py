from __future__ import annotations

import argparse
import re
import shutil
from pathlib import Path


DARK_MODE_MARKER = "data-dayoa-multiqc-dark-mode"
DARK_MODE_SNIPPET = (
    f'<script {DARK_MODE_MARKER}>'
    'localStorage.setItem("mqc-theme","dark");'
    'document.documentElement.setAttribute("data-bs-theme","dark");'
    "</script>"
)


def patch_html(html_path: Path, backup_path: Path) -> None:
    if not html_path.is_file():
        raise SystemExit(f"MultiQC HTML does not exist: {html_path}")
    if html_path.stat().st_size == 0:
        raise SystemExit(f"MultiQC HTML is empty: {html_path}")

    backup_path.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(html_path, backup_path)

    html = html_path.read_text(encoding="utf-8")
    if DARK_MODE_MARKER in html:
        print(f"MultiQC dark-mode patch already present in {html_path}")
        return

    patched, count = re.subn(
        r"(<head\b[^>]*>)",
        r"\1\n" + DARK_MODE_SNIPPET,
        html,
        count=1,
        flags=re.IGNORECASE,
    )
    if count != 1:
        raise SystemExit(f"Could not find a <head> element in MultiQC HTML: {html_path}")

    html_path.write_text(patched, encoding="utf-8")
    print(f"Backed up unpatched MultiQC HTML to {backup_path}")
    print(f"Patched MultiQC HTML to load in dark mode: {html_path}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Back up a MultiQC HTML file, then patch it to load in dark mode."
    )
    parser.add_argument("--html", required=True, type=Path)
    parser.add_argument("--backup", required=True, type=Path)
    args = parser.parse_args()

    patch_html(args.html, args.backup)


if __name__ == "__main__":
    main()
