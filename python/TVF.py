import struct
import json
import time
from pathlib import Path


class TVF:
    MAGIC = b"TVF"
    VERSION = 2

    def __init__(self):
        self.index = {}
        self.file_path = None

    # ----------------------------
    # Helpers
    # ----------------------------

    def _now(self):
        return int(time.time())

    def _normalize_path(self, path, dir_mode=False):
        path = path.strip().replace("\\", "/")

        while path.startswith("/"):
            path = path[1:]

        while "//" in path:
            path = path.replace("//", "/")

        if dir_mode:
            if path and not path.endswith("/"):
                path += "/"
        else:
            if path.endswith("/"):
                path = path[:-1]

        return path

    def _write_string(self, f, text):
        data = text.encode("utf-8")
        f.write(struct.pack("<I", len(data)))
        f.write(data)

    def _read_string(self, f):
        size = struct.unpack("<I", f.read(4))[0]
        return f.read(size).decode("utf-8")

    # ----------------------------
    # Directory handling
    # ----------------------------

    def make_dir(self, path):
        path = self._normalize_path(path, True)

        if path in self.index:
            return

        self.index[path] = {
            "kind": "dir",
            "created": self._now(),
            "modified": self._now(),
        }

    def _ensure_parent_dirs(self, path):
        parts = path.split("/")
        cur = ""

        for part in parts[:-1]:
            cur += part + "/"
            self.make_dir(cur)

    # ----------------------------
    # Adding files
    # ----------------------------

    def add_bytes(self, path, file_type, data):
        path = self._normalize_path(path)

        self._ensure_parent_dirs(path)

        self.index[path] = {
            "kind": "file",
            "type": file_type,
            "data": data,
            "offset": -1,
            "size": len(data),
            "created": self._now(),
            "modified": self._now(),
        }

    def add_text(self, path, text):
        self.add_bytes(path, "text", text.encode("utf-8"))

    def add_json(self, path, obj):
        self.add_text(path, json.dumps(obj))

    def add_file(self, path, file_type, disk_path):
        with open(disk_path, "rb") as f:
            data = f.read()

        self.add_bytes(path, file_type, data)

    # ----------------------------
    # Saving
    # ----------------------------

    def save(self, path):
        self.file_path = path

        with open(path, "wb") as f:
            f.write(self.MAGIC)

            f.write(struct.pack("<I", self.VERSION))

            paths = sorted(self.index.keys())

            f.write(struct.pack("<I", len(paths)))

            offset_positions = {}

            # Write index
            for p in paths:
                e = self.index[p]

                self._write_string(f, p)
                self._write_string(f, e.get("kind", "file"))
                self._write_string(f, e.get("type", ""))

                f.write(struct.pack("<Q", e.get("created", 0)))
                f.write(struct.pack("<Q", e.get("modified", 0)))

                offset_positions[p] = f.tell()

                f.write(struct.pack("<Q", 0))
                f.write(struct.pack("<Q", 0))

            # Write file data
            for p in paths:
                e = self.index[p]

                if e["kind"] == "dir":
                    continue

                offset = f.tell()

                f.write(e["data"])

                back = f.tell()

                f.seek(offset_positions[p])

                f.write(struct.pack("<Q", offset))
                f.write(struct.pack("<Q", len(e["data"])))

                f.seek(back)

    # ----------------------------
    # Loading
    # ----------------------------

    def load(self, path):
        self.file_path = path
        self.index.clear()

        with open(path, "rb") as f:
            magic = f.read(3)

            if magic != self.MAGIC:
                raise ValueError("Invalid TVF file")

            version = struct.unpack("<I", f.read(4))[0]

            count = struct.unpack("<I", f.read(4))[0]

            for _ in range(count):
                p = self._read_string(f)

                kind = self._read_string(f)
                file_type = self._read_string(f)

                created = struct.unpack("<Q", f.read(8))[0]
                modified = struct.unpack("<Q", f.read(8))[0]

                offset = struct.unpack("<Q", f.read(8))[0]
                size = struct.unpack("<Q", f.read(8))[0]

                self.index[p] = {
                    "kind": kind,
                    "type": file_type,
                    "created": created,
                    "modified": modified,
                    "offset": offset,
                    "size": size,
                }

    # ----------------------------
    # Reading
    # ----------------------------

    def read_bytes(self, path):
        path = self._normalize_path(path)

        if path not in self.index:
            raise FileNotFoundError(path)

        e = self.index[path]

        if e["kind"] != "file":
            return b""

        with open(self.file_path, "rb") as f:
            f.seek(e["offset"])
            return f.read(e["size"])

    def get_text(self, path):
        return self.read_bytes(path).decode("utf-8")

    def get_json(self, path):
        return json.loads(self.get_text(path))