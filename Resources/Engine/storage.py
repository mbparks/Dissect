"""Dissect workspace boundaries. No Ghidra or third-party imports here."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile

MAX_BINARY = 512 * 1024 * 1024
SCHEMA = 1

class WorkspaceError(ValueError):
    pass

def plain_file(value: str | Path, max_bytes: int = MAX_BINARY) -> Path:
    p = Path(value).expanduser().absolute()
    if p.is_symlink() or not p.is_file():
        raise WorkspaceError("Choose a regular file, not a folder or symbolic link.")
    if not 0 < p.stat().st_size <= max_bytes:
        raise WorkspaceError(f"File must be between 1 byte and {max_bytes // 1024 // 1024} MiB.")
    return p

def digest(path: Path) -> str:
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else _hash(f)

def _hash(f):
    h = hashlib.sha256()
    for chunk in iter(lambda: f.read(1024 * 1024), b''):
        h.update(chunk)
    return h.hexdigest()

def atomic_json(path: Path, value: dict) -> None:
    if path.is_symlink():
        raise WorkspaceError("Refusing to replace a symbolic link.")
    fd, name = tempfile.mkstemp(prefix='.dissect-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            json.dump(value, f, ensure_ascii=False, indent=2)
            f.flush()
            os.fsync(f.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def safe_tree(root: Path) -> None:
    # Ghidra opens its own database files: reject any link in the package first.
    if root.is_symlink() or not root.is_dir():
        raise WorkspaceError("Workspace must be a regular directory.")
    count = 0
    for directory, folders, files in os.walk(root, followlinks=False):
        for name in folders + files:
            p = Path(directory) / name
            count += 1
            if p.is_symlink():
                raise WorkspaceError("Workspace contains a symbolic link; opening it is disabled.")
            if count > 100_000:
                raise WorkspaceError("Workspace contains too many files.")

def read_manifest(root: Path) -> dict:
    safe_tree(root)
    path = plain_file(root / 'workspace.json', 1024 * 1024)
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except (ValueError, UnicodeError) as e:
        raise WorkspaceError('Workspace metadata is not valid JSON.') from e
    if not isinstance(data, dict) or data.get('schema') != SCHEMA or data.get('format') != 'dissect-workspace':
        raise WorkspaceError('Unsupported workspace format or version. The workspace was not modified.')
    if data.get('program') != '/Binary' or not re.fullmatch(r'[a-f0-9]{64}', str(data.get('sha256', ''))):
        raise WorkspaceError('Workspace metadata is invalid.')
    if digest(plain_file(root / 'original.bin')) != data['sha256']:
        raise WorkspaceError('Original binary checksum does not match the workspace. No changes were made.')
    return data

def page_bounds(offset=0, limit=200):
    if type(offset) is not int or type(limit) is not int or offset < 0 or not 1 <= limit <= 500:
        raise WorkspaceError('Invalid page range (limit 1–500).')
    return offset, limit

def label(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]{0,127}', value):
        raise WorkspaceError('Use 1–128 letters, digits, or underscores; start with a letter or underscore.')
    return value

def text_limit(value: str, length=16384) -> str:
    if not isinstance(value, str) or len(value) > length or '\x00' in value:
        raise WorkspaceError(f'Text must be at most {length} characters and contain no NUL characters.')
    return value
