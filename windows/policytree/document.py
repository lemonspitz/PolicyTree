"""One open tree: its data, selection, undo history and file state."""
from __future__ import annotations

import json
import os
import tempfile
import uuid

from PySide6.QtCore import QObject, QStandardPaths, Signal

from .model import CORE_ID, FileFormatError, Tree


class Document(QObject):
    changed = Signal()

    def __init__(self, tree=None, path=None):
        super().__init__()
        self.tree = tree or Tree.blank()
        self.selection = CORE_ID
        self.path = path
        self._saved = self.tree.to_json()
        self._undo = []
        self._redo = []
        self._coalesce = None
        self.recovery_id = uuid.uuid4().hex

    # ---- edits

    def apply(self, name, fn, coalesce=None):
        """Every edit passes through here. `coalesce` merges keystrokes in one field into one undo step."""
        old_tree, old_sel = self.tree, self.selection
        new = old_tree.clone()
        fn(new)
        if new == old_tree:
            return
        if not (coalesce and coalesce == self._coalesce):
            self._undo.append((old_tree, old_sel, name))
            self._redo.clear()
        self._coalesce = coalesce
        self.tree = new
        self.changed.emit()

    def _restore(self, source, target):
        tree, sel, name = source.pop()
        target.append((self.tree, self.selection, name))
        self.tree = tree
        self.selection = sel if tree.node(sel) else CORE_ID
        self._coalesce = None
        self.changed.emit()

    def undo(self):
        if self._undo:
            self._restore(self._undo, self._redo)

    def redo(self):
        if self._redo:
            self._restore(self._redo, self._undo)

    @property
    def undo_name(self):
        return self._undo[-1][2] if self._undo else None

    @property
    def redo_name(self):
        return self._redo[-1][2] if self._redo else None

    def end_coalescing(self):
        self._coalesce = None

    def select(self, node_id):
        if node_id != self.selection and self.tree.node(node_id):
            self.selection = node_id
            self._coalesce = None
            self.changed.emit()

    # ---- file state

    @property
    def dirty(self):
        return self.tree.to_json() != self._saved

    @property
    def pristine(self):
        """A window showing nothing the user made, so opening a file can reuse it."""
        return self.path is None and not self.dirty and not self._undo

    def mark_recovered(self):
        self._saved = None

    def save(self, path):
        text = self.tree.to_json()
        _atomic_write(path, text)
        self.path = path
        self._saved = text
        self.changed.emit()

    @staticmethod
    def load(path):
        with open(path, encoding="utf-8-sig") as f:
            return Document(Tree.from_json(f.read()), path)


def _atomic_write(path, text):
    """A failed save must never leave a half-written file in place of the old one."""
    folder = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(prefix=".policytree-", dir=folder)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# ---- crash recovery: unsaved work is copied here and removed once saved or discarded

def recovery_dir():
    base = os.environ.get("POLICYTREE_RECOVERY") or os.path.join(
        QStandardPaths.writableLocation(QStandardPaths.AppLocalDataLocation), "Recovery")
    os.makedirs(base, exist_ok=True)
    return base


def recovery_path(doc):
    return os.path.join(recovery_dir(), doc.recovery_id + ".json")


def write_recovery(doc):
    _atomic_write(recovery_path(doc), json.dumps({"path": doc.path, "tree": json.loads(doc.tree.to_json())}, ensure_ascii=False))


def clear_recovery(doc):
    try:
        os.unlink(recovery_path(doc))
    except FileNotFoundError:
        pass


def pending_recoveries():
    """Yields (recovery file, Document). A damaged recovery file is skipped, not fatal."""
    folder = recovery_dir()
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".json"):
            continue
        full = os.path.join(folder, name)
        try:
            with open(full, encoding="utf-8") as f:
                d = json.load(f)
            doc = Document(Tree.from_json(json.dumps(d["tree"])), d.get("path"))
            doc.mark_recovered()
            yield full, doc
        except (OSError, ValueError, KeyError, TypeError, FileFormatError):
            continue
