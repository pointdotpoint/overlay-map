"""The pre-campaign install and data, backed up once (soak/backup/<campaign>/); each run's build
swapped in; everything put back, also from a new process after a crash of the supervisor."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

from .paths import PARTS, VERIFY_PARTS, Paths, rels, tree_hash

ALL_RELS = rels(list(PARTS))
VERIFY_RELS = rels(VERIFY_PARTS)


def _remove(p: Path) -> None:
    if p.is_symlink() or p.is_file():
        p.unlink()
    elif p.is_dir():
        shutil.rmtree(p)


def _copy(src: Path, dst: Path) -> None:
    _remove(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(src, dst, symlinks=True)
    else:
        shutil.copy2(src, dst)


def _save_dirs(saves: Path) -> list[str]:
    return sorted(d.name for d in saves.iterdir() if d.is_dir()) if saves.is_dir() else []


class Snapshot:
    def __init__(self, paths: Paths, campaign: str):
        self.paths = paths
        self.dir = paths.soak / "backup" / campaign
        self.journal_path = self.dir / "journal.json"
        self.journal: dict = json.loads(self.journal_path.read_text()) if self.journal_path.exists() else {}

    @property
    def original(self) -> Path:
        return self.dir / "original"

    @property
    def data(self) -> Path:
        return self.dir / "data"

    def _write(self) -> None:
        self.dir.mkdir(parents=True, exist_ok=True)
        tmp = self.journal_path.with_suffix(".tmp")
        tmp.write_text(json.dumps(self.journal, indent=1))
        tmp.replace(self.journal_path)

    def _data_items(self) -> list[tuple[str, Path]]:
        p = self.paths
        return [("saves", p.saves), ("persistent.dat", p.persistent),
                ("mod_storage", p.mod_storage), ("settings", p.settings)]

    def _saves_hash(self) -> str:
        return tree_hash(self.paths.saves, _save_dirs(self.paths.saves))

    def take(self) -> None:
        if self.journal.get("taken"):
            return
        game = self.paths.game
        present = {}
        for rel in ALL_RELS:
            present[rel] = (game / rel).exists()
            if present[rel]:
                _copy(game / rel, self.original / rel)
        data_present = {}
        for name, src in self._data_items():
            data_present[name] = src.exists()
            if src.exists():
                _copy(src, self.data / name)
        self.journal = {"taken": True, "present": present, "data_present": data_present,
                        "install_hash": tree_hash(game, ALL_RELS), "saves_hash": self._saves_hash(),
                        "installed": None, "installed_hash": None, "restored": False}
        self._write()

    def install(self, build_dir: Path, build_id: str) -> None:
        game = self.paths.game
        for rel in ALL_RELS:
            src = build_dir / rel
            if not src.exists():
                _remove(game / rel)
            elif tree_hash(build_dir, [rel]) != tree_hash(game, [rel]):
                _copy(src, game / rel)
        self.journal["installed"] = build_id
        self.journal["installed_hash"] = tree_hash(game, VERIFY_RELS)
        self._write()

    def verify_installed(self) -> bool:
        return tree_hash(self.paths.game, VERIFY_RELS) == self.journal.get("installed_hash")

    def _put_back(self, name: str, dst: Path) -> None:
        if self.journal["data_present"].get(name):
            _copy(self.data / name, dst)
        else:
            _remove(dst)

    def reset_run_data(self) -> None:
        self._put_back("persistent.dat", self.paths.persistent)
        self._put_back("mod_storage", self.paths.mod_storage)
        _remove(self.paths.channel)

    def check_saves(self) -> bool:
        if self._saves_hash() == self.journal["saves_hash"]:
            return True
        self._put_back("saves", self.paths.saves)
        return False

    def restore(self) -> bool:
        game = self.paths.game
        for rel in ALL_RELS:
            if self.journal["present"].get(rel):
                if tree_hash(self.original, [rel]) != tree_hash(game, [rel]):
                    _copy(self.original / rel, game / rel)
            else:
                _remove(game / rel)
        for name, dst in self._data_items():
            if name == "saves":
                self.check_saves()
            else:
                self._put_back(name, dst)
        _remove(self.paths.channel)
        ok = tree_hash(game, ALL_RELS) == self.journal["install_hash"]
        self.journal["restored"] = ok
        self._write()
        return ok


def latest_unrestored(paths: Paths) -> str | None:
    backups = paths.soak / "backup"
    if not backups.is_dir():
        return None
    for d in sorted(backups.iterdir(), reverse=True):
        j = d / "journal.json"
        if j.exists() and not json.loads(j.read_text()).get("restored"):
            return d.name
    return None


def prune(paths: Paths, keep: int = 2) -> None:
    """Disk: staged builds (re-staged on demand) and restored backups beyond the newest `keep` go
    (each is a copy of the same pre-campaign install). A backup not restored is never touched."""
    shutil.rmtree(paths.soak / "builds", ignore_errors=True)
    root = paths.soak / "backup"
    if not root.is_dir():
        return
    restored = []
    for d in sorted(root.iterdir()):
        try:
            if json.loads((d / "journal.json").read_text()).get("restored"):
                restored.append(d)
        except (OSError, ValueError):
            continue
    for d in restored[:-keep] if keep > 0 else restored:
        shutil.rmtree(d, ignore_errors=True)
