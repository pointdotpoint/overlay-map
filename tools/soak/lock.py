"""One lock on the game folder, shared with tools/install.sh (flock on <game>/.pmui-deploy.lock).
A soak campaign holds it from start to restore, so another session's deploy can't swap the mod
under a run. The kernel drops it if the holder dies."""
from __future__ import annotations

import fcntl
import json
import os
import time
from pathlib import Path


class LockBusy(RuntimeError):
    pass


class DeployLock:
    def __init__(self, path: Path):
        self.path = path
        self.fd: int | None = None

    @property
    def owner_path(self) -> Path:
        return self.path.with_name(self.path.name + ".owner")

    def holder(self) -> str | None:
        try:
            return json.loads(self.owner_path.read_text()).get("owner")
        except (OSError, ValueError):
            return None

    def acquire(self, owner: str) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            os.close(fd)
            raise LockBusy(f"game folder locked by: {self.holder() or 'unknown holder'}") from None
        self.fd = fd
        self.owner_path.write_text(json.dumps(
            {"owner": owner, "pid": os.getpid(), "since": time.strftime("%Y-%m-%d %H:%M:%S")}))

    def release(self) -> None:
        if self.fd is None:
            return
        self.owner_path.unlink(missing_ok=True)
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        os.close(self.fd)
        self.fd = None

    def is_free(self) -> bool:
        if self.fd is not None:
            return False
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(self.path, os.O_RDWR | os.O_CREAT, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return False
        else:
            fcntl.flock(fd, fcntl.LOCK_UN)
            return True
        finally:
            os.close(fd)
