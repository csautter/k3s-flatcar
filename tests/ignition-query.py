#!/usr/bin/env python3
"""Read an Ignition JSON config and print one requested value.

Used by test-config-generation.sh to assert on generated configs without
needing jq. Ignition stores file contents as a data: URL that may be
base64-encoded and gzip-compressed, so plain text matching on the raw JSON
is not enough.

Usage:
  ignition-query.py <config.json> content <path>   inline body, or the remote URL
  ignition-query.py <config.json> mode <path>      file mode, as four octal digits
  ignition-query.py <config.json> paths            every file path, one per line
  ignition-query.py <config.json> units            every systemd unit body
"""
import base64
import gzip
import json
import sys
import urllib.parse


def decode(contents):
    head, payload = contents["source"].split(",", 1)
    if head.endswith(";base64"):
        raw = base64.b64decode(payload)
    else:
        raw = urllib.parse.unquote_to_bytes(payload)
    if contents.get("compression") == "gzip":
        raw = gzip.decompress(raw)
    return raw.decode()


def find(files, path):
    for f in files:
        if f["path"] == path:
            return f
    sys.exit("no such file in config: %s" % path)


def main():
    doc = json.load(open(sys.argv[1]))
    cmd = sys.argv[2]
    files = doc.get("storage", {}).get("files", [])

    if cmd == "content":
        entry = find(files, sys.argv[3])
        contents = entry.get("contents", {})
        source = contents.get("source", "")
        if not source:
            # No contents at all: Ignition would create an empty file. This is
            # what a dropped contents key looks like, so surface it explicitly.
            sys.exit("file has no contents: %s" % sys.argv[3])
        print(decode(contents) if source.startswith("data:") else source)
    elif cmd == "mode":
        print(oct(find(files, sys.argv[3])["mode"])[2:].zfill(4))
    elif cmd == "paths":
        for f in files:
            print(f["path"])
    elif cmd == "units":
        for u in doc.get("systemd", {}).get("units", []):
            print(u["contents"])
    else:
        sys.exit("unknown query: %s" % cmd)


if __name__ == "__main__":
    main()
