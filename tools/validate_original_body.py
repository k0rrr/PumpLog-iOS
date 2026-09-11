#!/usr/bin/env python3
"""Validate the bundled licensed anatomy model and its embedded metadata."""

from __future__ import annotations

import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "pumplog_ios" / "BodyAnatomyLicensed.bundle"
MODEL = BUNDLE / "body.glb"


def read_json_chunk(data: bytes) -> dict:
    if data[:4] != b"glTF":
        raise ValueError("invalid GLB magic")
    version, total_length = struct.unpack_from("<II", data, 4)
    if version != 2 or total_length != len(data):
        raise ValueError("invalid GLB header")
    json_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError("first GLB chunk is not JSON")
    return json.loads(data[20 : 20 + json_length])


def main() -> None:
    document = read_json_chunk(MODEL.read_bytes())
    nodes = document.get("nodes", [])
    types = {node.get("extras", {}).get("type") for node in nodes}
    muscle_count = sum(node.get("extras", {}).get("type") == "muscle" for node in nodes)
    body_count = sum(node.get("extras", {}).get("type") == "body" for node in nodes)
    if "muscle" not in types or muscle_count < 100:
        raise ValueError("licensed model is missing expected muscle metadata")
    if any(uri for buffer in document.get("buffers", []) for uri in [buffer.get("uri")] if uri):
        raise ValueError("model contains an external buffer URI")
    print(f"valid licensed GLB: {len(nodes)} nodes ({muscle_count} muscles, {body_count} body), {MODEL.stat().st_size} bytes")


if __name__ == "__main__":
    main()
