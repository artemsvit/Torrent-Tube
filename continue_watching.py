"""Shared playback positions, with dated removals to reject stale device copies."""
import json
import math
import os
import threading
from favorites import _text, SOURCE_FIELDS


def clean_change(raw):
    if not isinstance(raw, dict):
        return None
    torrent = _text(raw.get("torrent_id"))
    file = raw.get("file")
    updated = raw.get("updated_at")
    if not torrent or not isinstance(file, int) or isinstance(file, bool) or file < 0:
        return None
    if not isinstance(updated, (int, float)) or isinstance(updated, bool) or not math.isfinite(updated) or updated <= 0:
        return None
    entry = {"torrent_id": torrent, "file": file, "updated_at": updated, "removed": raw.get("removed") is True}
    if entry["removed"]:
        return entry
    title, source = _text(raw.get("title")), raw.get("source")
    seconds, duration = raw.get("seconds"), raw.get("duration")
    if not title or not isinstance(source, dict):
        return None
    if any(not isinstance(v, (int, float)) or isinstance(v, bool) or not math.isfinite(v) for v in (seconds, duration)):
        return None
    if seconds < 10 or duration <= 0 or seconds >= duration - 15:
        return None
    cleaned = {k: source[k] for k in SOURCE_FIELDS if _text(source.get(k))}
    if not cleaned:
        return None
    cleaned["file"] = file
    entry.update(title=title, source=cleaned, seconds=seconds, duration=duration)
    if _text(raw.get("artwork")):
        entry["artwork"] = raw["artwork"]
    return entry


class ContinueWatching:
    def __init__(self, path):
        self.path = path
        self._lock = threading.Lock()
        self._entries = {}
        self._cleared_at = 0
        try:
            saved = json.loads(path.read_text())
            cleared = saved.get("cleared_at", 0)
            if isinstance(cleared, (int, float)) and not isinstance(cleared, bool) and math.isfinite(cleared):
                self._cleared_at = max(0, cleared)
            for raw in saved.get("items", []):
                entry = clean_change(raw)
                if entry and entry["updated_at"] > self._cleared_at:
                    self._entries[(entry["torrent_id"], entry["file"])] = entry
        except (OSError, ValueError, TypeError, AttributeError):
            pass

    def _save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps({"cleared_at": self._cleared_at, "items": list(self._entries.values())}, ensure_ascii=False, allow_nan=False))
        os.replace(temporary, self.path)

    def items(self):
        with self._lock:
            return sorted((dict(e) for e in self._entries.values() if not e["removed"]), key=lambda e: e["updated_at"], reverse=True)[:50]

    def update(self, changes, clear_before=None):
        with self._lock:
            changed = False
            if isinstance(clear_before, (int, float)) and not isinstance(clear_before, bool) and math.isfinite(clear_before) and clear_before > self._cleared_at:
                self._cleared_at = clear_before
                self._entries = {k: e for k, e in self._entries.items() if e["updated_at"] > clear_before}
                changed = True
            for raw in changes:
                entry = clean_change(raw)
                if not entry or entry["updated_at"] <= self._cleared_at:
                    continue
                key = (entry["torrent_id"], entry["file"])
                known = self._entries.get(key)
                if known and known["updated_at"] >= entry["updated_at"]:
                    continue
                self._entries[key] = entry
                changed = True
            if changed:
                self._save()
