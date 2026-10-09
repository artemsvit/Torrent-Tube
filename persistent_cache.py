"""The server's lasting cache (TMDB matches and details, episodes, YouTube
results): SQLite on disk, with the recent entries also kept in memory."""
import json
import sqlite3
import threading
import time
from pathlib import Path


class PersistentCache:
    """Thread-safe SQLite persistent cache with an in-memory hot layer.
    Persists TMDB metadata, negative lookups, details, episodes, and YouTube results."""

    def __init__(self, db_path: Path):
        self.db_path = db_path
        self._ram = {}
        self._lock = threading.Lock()
        self._init_db()

    def _init_db(self):
        try:
            with sqlite3.connect(self.db_path) as conn:
                conn.execute("PRAGMA journal_mode=WAL")
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS cache (
                        key TEXT PRIMARY KEY,
                        value TEXT,
                        expires_at REAL,
                        is_hit INTEGER
                    )
                """)
                conn.execute("CREATE INDEX IF NOT EXISTS idx_cache_expires ON cache(expires_at)")
        except Exception:
            pass

    def get(self, key: str):
        """Returns (found: bool, value: Any). Note: value can be None for negative hits."""
        now = time.time()
        with self._lock:
            ram_hit = self._ram.get(key)
            if ram_hit:
                expires_at, val = ram_hit
                if now < expires_at:
                    return True, val
                else:
                    self._ram.pop(key, None)

        try:
            with sqlite3.connect(self.db_path, timeout=5) as conn:
                row = conn.execute("SELECT value, expires_at FROM cache WHERE key = ?", (key,)).fetchone()
                if row:
                    val_str, expires_at = row
                    if now < expires_at:
                        val = json.loads(val_str) if val_str is not None else None
                        with self._lock:
                            self._ram[key] = (expires_at, val)
                        return True, val
                    else:
                        conn.execute("DELETE FROM cache WHERE key = ?", (key,))
        except Exception:
            pass
        return False, None

    def set(self, key: str, value, ttl: float, is_hit: bool = True):
        expires_at = time.time() + ttl
        with self._lock:
            self._ram[key] = (expires_at, value)
        try:
            val_str = json.dumps(value, ensure_ascii=False) if value is not None else None
            with sqlite3.connect(self.db_path, timeout=5) as conn:
                conn.execute(
                    "INSERT OR REPLACE INTO cache (key, value, expires_at, is_hit) VALUES (?, ?, ?, ?)",
                    (key, val_str, expires_at, 1 if is_hit else 0),
                )
        except Exception:
            pass

    def clear(self):
        with self._lock:
            self._ram.clear()
        try:
            with sqlite3.connect(self.db_path, timeout=5) as conn:
                conn.execute("DELETE FROM cache")
        except Exception:
            pass
