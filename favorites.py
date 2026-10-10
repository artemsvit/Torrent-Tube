"""Favorites: the titles kept with the heart, one list for every app and the
web page that uses this server. Saved as JSON in the state folder."""
import json
import os
import threading
import time

KINDS = ("movie", "tv", "cartoon")
TEXT_FIELDS = ("title", "clean_title", "poster", "media_type", "magnet", "download_link")
SOURCE_FIELDS = ("id", "path", "magnet", "download_link")
MAX_TEXT = 8192
MAX_ENTRIES = 5000


def _text(value):
    return value if isinstance(value, str) and 0 < len(value) <= MAX_TEXT else None


def clean_entry(raw):
    """The known fields of one entry, or None when it has no id or title."""
    if not isinstance(raw, dict):
        return None
    entry_id, title = _text(raw.get("id")), _text(raw.get("title"))
    if not entry_id or not title:
        return None
    entry = {"id": entry_id}
    for field in TEXT_FIELDS:
        value = _text(raw.get(field))
        if value:
            entry[field] = value
    tmdb_id = raw.get("tmdb_id")
    if isinstance(tmdb_id, int) and not isinstance(tmdb_id, bool) and tmdb_id > 0:
        entry["tmdb_id"] = tmdb_id
    entry["kind"] = raw.get("kind") if raw.get("kind") in KINDS else "movie"
    source = raw.get("source_override")
    if isinstance(source, dict):
        cleaned = {k: source[k] for k in SOURCE_FIELDS if _text(source.get(k))}
        file_index = source.get("file")
        if isinstance(file_index, int) and not isinstance(file_index, bool) and file_index >= 0:
            cleaned["file"] = file_index
        if cleaned:
            entry["source_override"] = cleaned
    added = raw.get("added_at")
    entry["added_at"] = float(added) if isinstance(added, (int, float)) and not isinstance(added, bool) and added > 0 else time.time()
    return entry


class Favorites:
    def __init__(self, path):
        self.path = path
        self._lock = threading.Lock()
        self._entries = {}
        try:
            for raw in json.loads(path.read_text()):
                entry = clean_entry(raw)
                if entry:
                    self._entries[entry["id"]] = entry
        except (OSError, ValueError, TypeError):
            pass

    def _save(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(list(self._entries.values()), ensure_ascii=False))
        os.replace(temporary, self.path)

    def items(self):
        """Newest first."""
        with self._lock:
            return sorted((dict(e) for e in self._entries.values()), key=lambda e: e["added_at"], reverse=True)

    def add(self, raw_entries):
        """Adds or updates entries. A title saved before keeps its first date,
        so a device that uploads its old list does not reorder it."""
        added = 0
        with self._lock:
            for raw in raw_entries if isinstance(raw_entries, list) else []:
                entry = clean_entry(raw)
                if not entry:
                    continue
                known = self._entries.get(entry["id"])
                if known:
                    entry["added_at"] = min(known["added_at"], entry["added_at"])
                elif len(self._entries) >= MAX_ENTRIES:
                    continue
                self._entries[entry["id"]] = entry
                added += 1
            if added:
                self._save()
        return added

    def remove(self, ids):
        with self._lock:
            removed = [i for i in ids if isinstance(i, str) and self._entries.pop(i, None)]
            if removed:
                self._save()
            return len(removed)
