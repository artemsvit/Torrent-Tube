"""Short-lived native player leases, separate from legacy socket cleanup."""
import secrets
import threading
import time


class PlaybackSessions:
    def __init__(self, ttl=90, clock=time.monotonic):
        self.ttl = ttl
        self.clock = clock
        self._sessions = {}
        self._lock = threading.Lock()

    def _expire(self):
        now = self.clock()
        self._sessions = {k: v for k, v in self._sessions.items() if v["expires"] > now}

    def create(self, torrent_id, file_index):
        with self._lock:
            self._expire()
            token = secrets.token_urlsafe(32)
            self._sessions[token] = {"torrent_id": torrent_id, "file": file_index,
                                     "expires": self.clock() + self.ttl}
            return token

    def touch(self, token):
        with self._lock:
            self._expire()
            entry = self._sessions.get(token)
            if entry:
                entry["expires"] = self.clock() + self.ttl
                return dict(entry)

    def close(self, token):
        with self._lock:
            self._expire()
            return self._sessions.pop(token, None)

    def has_viewers(self, torrent_id):
        with self._lock:
            self._expire()
            return any(v["torrent_id"] == torrent_id for v in self._sessions.values())

    def discard_torrent(self, torrent_id):
        with self._lock:
            self._sessions = {k: v for k, v in self._sessions.items() if v["torrent_id"] != torrent_id}
