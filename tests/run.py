"""Run the zone protection regression against a local Factorio 2.1 executable."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--factorio-exe", type=Path, required=True)
parser.add_argument("--source", type=Path)
parser.add_argument("--work-dir", type=Path)
args = parser.parse_args()
repository = Path(__file__).resolve().parent.parent
if args.source:
    source = args.source.resolve()
else:
    source = max(
        (p for p in repository.glob("zone-permissions_*") if p.is_dir()),
        key=lambda p: tuple(map(int, json.loads((p / "info.json").read_text())["version"].split("."))),
    )
metadata = json.loads((source / "info.json").read_text(encoding="utf-8"))
root_name = f'{metadata["name"]}_{metadata["version"]}'
test_root = args.work_dir.resolve() if args.work_dir else Path(tempfile.mkdtemp(prefix="zone-tests-"))
test_root.mkdir(parents=True, exist_ok=True)
mods = test_root / "mods"
mods.mkdir(exist_ok=True)
(test_root / "saves").mkdir(exist_ok=True)
package = mods / f"{root_name}.zip"
driver = Path(__file__).with_name("zone-protection.lua").read_text(encoding="utf-8")
with zipfile.ZipFile(package, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(source.rglob("*")):
        if path.is_file():
            content = path.read_bytes()
            if path == source / "control.lua":
                content += ("\n" + driver).encode("utf-8")
            archive.writestr((Path(root_name) / path.relative_to(source)).as_posix(), content)
    archive.writestr(f"{root_name}/scenarios/zone-protection-regression/control.lua", "-- Test driver runs in the mod.\n")
(mods / "mod-list.json").write_text(json.dumps({"mods": [
    {"name": "base", "enabled": True},
    {"name": "elevated-rails", "enabled": False},
    {"name": "quality", "enabled": False},
    {"name": "space-age", "enabled": False},
    {"name": "recycler", "enabled": False},
    {"name": metadata["name"], "enabled": True},
]}), encoding="utf-8")
data = args.factorio_exe.resolve().parents[2] / "data"
config = test_root / "config.ini"
config.write_text(f"[path]\nread-data={data.as_posix()}\nwrite-data={test_root.as_posix()}\n", encoding="utf-8")
common = [str(args.factorio_exe.resolve()), "--config", str(config), "--mod-directory", str(mods),
          "--disable-audio", "--no-log-rotation"]
save = test_root / "saves" / "zone-protection-regression.zip"
for label, invocation, marker in (
    ("prepare", ["--test-scenario", f'{metadata["name"]}/zone-protection-regression',
                 "--test-ticks", "120", "--test-arg", "prepare"], "initial regression run completed"),
    ("save", ["--create", str(save)], "persistence fixture created"),
    ("reload", ["--test-save", str(save), "--test-ticks", "120", "--test-arg", "reload"],
     "restoration after reload"),
):
    log_file = test_root / "factorio-current.log"
    log_offset = log_file.stat().st_size if log_file.exists() else 0
    result = subprocess.run(common + invocation, cwd=test_root,
                            capture_output=True, text=True, encoding="utf-8", errors="replace",
                            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), timeout=120)
    output = result.stdout + result.stderr
    (test_root / f"{label}-stdout.log").write_text(output, encoding="utf-8")
    game_log = test_root / "factorio-current.log"
    log_text = game_log.read_bytes()[log_offset:].decode("utf-8", errors="replace") if game_log.exists() else ""
    (test_root / f"{label}-factorio.log").write_text(log_text, encoding="utf-8")
    if result.returncode != 0 or marker not in log_text:
        print(log_text[-9000:] or output[-9000:])
        raise SystemExit(f"FAIL: {label}; Factorio exit code {result.returncode}; logs in {test_root}")
    for line in log_text.splitlines():
        if "ZONE TEST PASS:" in line:
            print(line)
    if label == "save" and not save.is_file():
        raise SystemExit(f"FAIL: native --create did not write {save}")
print(f"PASS: zone protection regressions, including save/load. Logs: {test_root}")
