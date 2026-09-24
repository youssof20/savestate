"""Check an extracted Lite download without using existing game saves."""
import argparse
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

from build_release import ROOT, build


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    engine = args.godot.resolve(strict=True)
    archive = build()
    output = ROOT / ".test-runs"
    output.mkdir(exist_ok=True)
    run = Path(tempfile.mkdtemp(prefix="release-", dir=output))
    project = run / "project"
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        assert not any("savestate_pro/" in name or name.startswith(("tests/", "tools/", ".")) for name in bundle.namelist())
        bundle.extractall(project)
    shutil.copytree(ROOT / "tests", project / "tests")
    env = os.environ.copy()
    for key in ("APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
        directory = run / key.lower()
        directory.mkdir()
        env[key] = str(directory)

    def execute(label, arguments):
        with (run / f"{label}.log").open("w", encoding="utf-8") as log:
            try:
                result = subprocess.run([str(engine), "--headless", "--path", str(project)] + arguments,
                                        env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120)
            except subprocess.TimeoutExpired:
                log.flush()
                raise RuntimeError((run / f"{label}.log").read_text(encoding="utf-8"))
        text = (run / f"{label}.log").read_text(encoding="utf-8")
        (run / f"{label}.log").write_text(text, encoding="utf-8")
        if result.returncode != 0 or "SCRIPT ERROR:" in text or "ERROR:" in text or "FAIL:" in text:
            raise RuntimeError(f"{label} failed:\n{text}")
        print(label + ": PASS", flush=True)

    execute("import", ["--editor", "--import"])
    execute("demo-save", ["--script", "res://tests/demo.gd", "--", "save"])
    execute("demo-restart", ["--script", "res://tests/demo.gd", "--", "load"])
    settings = project / "project.godot"
    settings.write_text(settings.read_text(encoding="utf-8").replace(
        '"res://addons/savestate/plugin.cfg")',
        '"res://addons/savestate/plugin.cfg", "res://tests/editor/plugin.cfg")'), encoding="utf-8")
    execute("editor", ["--editor"])
    print(f"Logs: {run}")


if __name__ == "__main__":
    main()
