"""Build the Lite download with its runnable demo and usage guide."""
import configparser
import hashlib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def version():
    config = configparser.ConfigParser()
    config.read(ROOT / "addons/savestate/plugin.cfg", encoding="utf-8")
    return config["plugin"]["version"].strip('"')


def files():
    selected = [ROOT / name for name in ("README.md", "GUIDE.md", "CHANGELOG.md", "LICENSE", "project.godot", "icon.png")]
    for folder in ("addons/savestate", "samples/minimal-demo"):
        selected.extend(p for p in (ROOT / folder).rglob("*") if p.is_file()
                        and p.suffix in {".gd", ".uid", ".cfg", ".tscn", ".tres", ".svg", ".png", ".md"})
    return sorted(selected)


def build():
    destination = ROOT / "dist" / f"savestate-lite-v{version()}.zip"
    destination.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for source in files():
            info = zipfile.ZipInfo(source.relative_to(ROOT).as_posix(), (2026, 9, 24, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            data = source.read_bytes()
            if source.suffix != ".png": data = data.replace(b"\r\n", b"\n")
            archive.writestr(info, data)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    destination.with_suffix(".zip.sha256").write_text(f"{digest}  {destination.name}\n", encoding="ascii")
    print(destination)
    return destination


if __name__ == "__main__":
    build()
