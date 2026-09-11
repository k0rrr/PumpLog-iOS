#!/usr/bin/env python3
"""Generate an original, lightweight PumpLog anatomy mannequin as a GLB.

This intentionally uses procedural primitives rather than any third-party mesh.
Each muscle region is a separate node with a stable anatomical name so the
existing viewer can highlight workout groups without changing its runtime code.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "pumplog_ios" / "BodyAnatomyOriginal.bundle" / "body.glb"


def unit_quaternion_from_y(direction: tuple[float, float, float]) -> list[float]:
    """Quaternion rotating the unit Y axis onto direction."""
    x, y, z = direction
    length = math.sqrt(x * x + y * y + z * z) or 1.0
    x, y, z = x / length, y / length, z / length
    # Cross((0,1,0), direction) and 1 + dot form the shortest-arc quaternion.
    qx, qy, qz = z, 0.0, -x
    qw = 1.0 + y
    qlen = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw) or 1.0
    return [qx / qlen, qy / qlen, qz / qlen, qw / qlen]


def sphere_geometry(latitudes: int = 14, longitudes: int = 20) -> tuple[bytes, bytes, int]:
    vertices: list[float] = []
    normals: list[float] = []
    indices: list[int] = []
    for lat in range(latitudes + 1):
        phi = math.pi * lat / latitudes
        sin_phi, cos_phi = math.sin(phi), math.cos(phi)
        for lon in range(longitudes):
            theta = 2.0 * math.pi * lon / longitudes
            sin_theta, cos_theta = math.sin(theta), math.cos(theta)
            x, y, z = sin_phi * cos_theta, cos_phi, sin_phi * sin_theta
            vertices.extend((x, y, z))
            normals.extend((x, y, z))
    for lat in range(latitudes):
        for lon in range(longitudes):
            a = lat * longitudes + lon
            b = lat * longitudes + (lon + 1) % longitudes
            c = (lat + 1) * longitudes + (lon + 1) % longitudes
            d = (lat + 1) * longitudes + lon
            indices.extend((a, b, d, b, c, d))
    vertex_bytes = struct.pack(f"<{len(vertices)}f", *vertices)
    normal_bytes = struct.pack(f"<{len(normals)}f", *normals)
    index_bytes = struct.pack(f"<{len(indices)}H", *indices)
    return vertex_bytes + normal_bytes, index_bytes, len(vertices) // 3


def align4(data: bytes) -> bytes:
    return data + b"\0" * ((4 - len(data) % 4) % 4)


def align_json4(data: bytes) -> bytes:
    # glTF requires JSON chunk padding to be ASCII spaces. NUL padding is only
    # valid for the binary chunk and causes strict JSON parsers to fail.
    return data + b" " * ((4 - len(data) % 4) % 4)


def build_glb() -> bytes:
    vertex_normal_bytes, index_bytes, vertex_count = sphere_geometry()
    vertex_bytes = vertex_normal_bytes[: vertex_count * 12]
    normal_bytes = vertex_normal_bytes[vertex_count * 12 :]

    buffer = bytearray()
    offsets: dict[str, tuple[int, int]] = {}
    for name, payload in (("positions", vertex_bytes), ("normals", normal_bytes), ("indices", index_bytes)):
        start = len(buffer)
        buffer.extend(align4(payload))
        offsets[name] = (start, len(payload))

    nodes: list[dict] = []
    # name, center, scale, optional orientation direction, group
    parts = [
        ("Core Torso", (0.0, 2.16, -0.02), (0.66, 0.83, 0.15), None, None),
        ("Sternum", (0.0, 2.15, 0.13), (0.07, 0.58, 0.06), None, None),
        ("Clavicle Left", (-0.23, 2.71, 0.14), (0.28, 0.07, 0.06), (-1.0, 0.10, 0.0), None),
        ("Clavicle Right", (0.23, 2.71, 0.14), (0.28, 0.07, 0.06), (1.0, 0.10, 0.0), None),
        ("Shoulder Base Left", (-0.51, 2.50, -0.02), (0.31, 0.30, 0.16), None, None),
        ("Shoulder Base Right", (0.51, 2.50, -0.02), (0.31, 0.30, 0.16), None, None),
        ("Upper Arm Base Left", (-0.75, 2.21, -0.01), (0.18, 0.42, 0.14), (0.04, -1.0, 0.0), None),
        ("Upper Arm Base Right", (0.75, 2.21, -0.01), (0.18, 0.42, 0.14), (0.04, -1.0, 0.0), None),
        ("Forearm Base Left", (-0.90, 1.78, -0.01), (0.15, 0.34, 0.12), (0.10, -1.0, 0.0), None),
        ("Forearm Base Right", (0.90, 1.78, -0.01), (0.15, 0.34, 0.12), (0.10, -1.0, 0.0), None),
        ("Pelvis", (0.0, 1.28, -0.02), (0.45, 0.35, 0.16), None, None),
        ("Thigh Base Left", (-0.25, 0.83, 0.0), (0.28, 0.53, 0.17), (0.0, -1.0, 0.0), None),
        ("Thigh Base Right", (0.25, 0.83, 0.0), (0.28, 0.53, 0.17), (0.0, -1.0, 0.0), None),
        ("Shin Base Left", (-0.25, 0.20, 0.0), (0.19, 0.37, 0.13), (0.0, -1.0, 0.0), None),
        ("Shin Base Right", (0.25, 0.20, 0.0), (0.19, 0.37, 0.13), (0.0, -1.0, 0.0), None),
        ("Head", (0.0, 3.34, 0.0), (0.31, 0.39, 0.30), None, None),
        ("Neck", (0.0, 2.91, 0.0), (0.17, 0.28, 0.16), None, None),
        ("Trapezius", (0.0, 2.67, 0.0), (0.48, 0.27, 0.18), None, "back"),
        ("Pectoralis Major Left", (-0.29, 2.48, 0.20), (0.39, 0.23, 0.14), None, "chest"),
        ("Pectoralis Major Right", (0.29, 2.48, 0.20), (0.39, 0.23, 0.14), None, "chest"),
        ("Pectoralis Minor Left", (-0.42, 2.31, 0.22), (0.18, 0.13, 0.08), (-0.30, -1.0, 0.0), "chest"),
        ("Pectoralis Minor Right", (0.42, 2.31, 0.22), (0.18, 0.13, 0.08), (0.30, -1.0, 0.0), "chest"),
        ("Deltoid Left", (-0.69, 2.52, 0.04), (0.20, 0.27, 0.20), None, "shoulders"),
        ("Deltoid Right", (0.69, 2.52, 0.04), (0.20, 0.27, 0.20), None, "shoulders"),
        ("Anterior Deltoid Left", (-0.63, 2.59, 0.16), (0.16, 0.20, 0.15), None, "shoulders"),
        ("Anterior Deltoid Right", (0.63, 2.59, 0.16), (0.16, 0.20, 0.15), None, "shoulders"),
        ("Posterior Deltoid Left", (-0.70, 2.48, -0.14), (0.16, 0.20, 0.14), None, "shoulders"),
        ("Posterior Deltoid Right", (0.70, 2.48, -0.14), (0.16, 0.20, 0.14), None, "shoulders"),
        ("Biceps Brachii Left", (-0.82, 2.17, 0.03), (0.14, 0.36, 0.14), (0.10, -1.0, 0.03), "biceps"),
        ("Biceps Brachii Right", (0.82, 2.17, 0.03), (0.14, 0.36, 0.14), (0.10, -1.0, -0.03), "biceps"),
        ("Biceps Long Head Left", (-0.84, 2.24, 0.16), (0.08, 0.30, 0.09), (0.10, -1.0, 0.0), "biceps"),
        ("Biceps Long Head Right", (0.84, 2.24, 0.16), (0.08, 0.30, 0.09), (0.10, -1.0, 0.0), "biceps"),
        ("Triceps Brachii Left", (-0.86, 2.14, -0.09), (0.13, 0.38, 0.13), (0.10, -1.0, 0.03), "triceps"),
        ("Triceps Brachii Right", (0.86, 2.14, -0.09), (0.13, 0.38, 0.13), (0.10, -1.0, -0.03), "triceps"),
        ("Triceps Lateral Head Left", (-0.91, 2.22, -0.01), (0.08, 0.28, 0.09), (0.10, -1.0, 0.0), "triceps"),
        ("Triceps Lateral Head Right", (0.91, 2.22, -0.01), (0.08, 0.28, 0.09), (0.10, -1.0, 0.0), "triceps"),
        ("Rectus Abdominis Upper", (0.0, 2.16, 0.19), (0.25, 0.19, 0.10), None, "abs"),
        ("Rectus Abdominis Middle", (0.0, 1.88, 0.20), (0.23, 0.22, 0.10), None, "abs"),
        ("Rectus Abdominis Lower", (0.0, 1.58, 0.19), (0.20, 0.18, 0.10), None, "abs"),
        ("External Oblique Left", (-0.40, 1.82, 0.17), (0.17, 0.38, 0.09), (0.22, -1.0, 0.0), "abs"),
        ("External Oblique Right", (0.40, 1.82, 0.17), (0.17, 0.38, 0.09), (0.22, -1.0, 0.0), "abs"),
        ("Serratus Anterior Left", (-0.52, 2.18, 0.15), (0.12, 0.35, 0.08), (0.15, -1.0, 0.0), "chest"),
        ("Serratus Anterior Right", (0.52, 2.18, 0.15), (0.12, 0.35, 0.08), (0.15, -1.0, 0.0), "chest"),
        ("Serratus Lower Left", (-0.53, 1.96, 0.14), (0.10, 0.20, 0.07), (0.15, -1.0, 0.0), "chest"),
        ("Serratus Lower Right", (0.53, 1.96, 0.14), (0.10, 0.20, 0.07), (0.15, -1.0, 0.0), "chest"),
        ("Latissimus Dorsi Left", (-0.38, 2.10, -0.10), (0.28, 0.47, 0.12), None, "back"),
        ("Latissimus Dorsi Right", (0.38, 2.10, -0.10), (0.28, 0.47, 0.12), None, "back"),
        ("Gluteus Maximus Left", (-0.25, 1.27, -0.02), (0.29, 0.27, 0.22), None, "legs"),
        ("Gluteus Maximus Right", (0.25, 1.27, -0.02), (0.29, 0.27, 0.22), None, "legs"),
        ("Quadriceps Left", (-0.25, 0.83, 0.12), (0.24, 0.51, 0.20), (0.0, -1.0, 0.0), "legs"),
        ("Quadriceps Right", (0.25, 0.83, 0.12), (0.24, 0.51, 0.20), (0.0, -1.0, 0.0), "legs"),
        ("Rectus Femoris Left", (-0.12, 0.91, 0.23), (0.11, 0.44, 0.09), (0.0, -1.0, 0.0), "legs"),
        ("Rectus Femoris Right", (0.12, 0.91, 0.23), (0.11, 0.44, 0.09), (0.0, -1.0, 0.0), "legs"),
        ("Vastus Lateralis Left", (-0.36, 0.86, 0.18), (0.11, 0.43, 0.10), (0.0, -1.0, 0.0), "legs"),
        ("Vastus Lateralis Right", (0.36, 0.86, 0.18), (0.11, 0.43, 0.10), (0.0, -1.0, 0.0), "legs"),
        ("Hamstrings Left", (-0.25, 0.82, -0.13), (0.21, 0.49, 0.17), (0.0, -1.0, 0.0), "legs"),
        ("Hamstrings Right", (0.25, 0.82, -0.13), (0.21, 0.49, 0.17), (0.0, -1.0, 0.0), "legs"),
        ("Gastrocnemius Left", (-0.25, 0.22, -0.01), (0.17, 0.34, 0.15), None, "legs"),
        ("Gastrocnemius Right", (0.25, 0.22, -0.01), (0.17, 0.34, 0.15), None, "legs"),
        ("Gastrocnemius Medial Left", (-0.31, 0.25, 0.11), (0.10, 0.25, 0.10), None, "legs"),
        ("Gastrocnemius Medial Right", (0.31, 0.25, 0.11), (0.10, 0.25, 0.10), None, "legs"),
        ("Tibialis Anterior Left", (-0.25, 0.18, 0.11), (0.12, 0.31, 0.11), None, "legs"),
        ("Tibialis Anterior Right", (0.25, 0.18, 0.11), (0.12, 0.31, 0.11), None, "legs"),
        ("Forearm Flexors Left", (-0.93, 1.79, 0.02), (0.12, 0.31, 0.13), (0.10, -1.0, 0.03), "biceps"),
        ("Forearm Flexors Right", (0.93, 1.79, 0.02), (0.12, 0.31, 0.13), (0.10, -1.0, -0.03), "biceps"),
        ("Hand Left", (-0.99, 1.42, 0.01), (0.13, 0.15, 0.10), None, None),
        ("Hand Right", (0.99, 1.42, 0.01), (0.13, 0.15, 0.10), None, None),
        ("Foot Left", (-0.25, -0.20, 0.11), (0.17, 0.12, 0.27), None, None),
        ("Foot Right", (0.25, -0.20, 0.11), (0.17, 0.12, 0.27), None, None),
    ]
    for name, center, scale, direction, group in parts:
        is_muscle = group is not None
        node = {"name": name, "mesh": 0 if is_muscle else 1, "translation": list(center), "scale": list(scale), "extras": {"type": "muscle" if is_muscle else "body", "name": name}}
        if direction:
            node["rotation"] = unit_quaternion_from_y(direction)
        nodes.append(node)

    json_doc = {
        "asset": {"version": "2.0", "generator": "PumpLog original procedural anatomy"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": [
            {"name": "OriginalMusclePrimitive", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "indices": 2, "material": 0}]},
            {"name": "OriginalBodyPrimitive", "primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1}, "indices": 2, "material": 1}]},
        ],
        "materials": [
            {"name": "MuscleBase", "pbrMetallicRoughness": {"baseColorFactor": [0.58, 0.16, 0.14, 1.0], "roughnessFactor": 0.72, "metallicFactor": 0.0}},
            {"name": "BodyBase", "pbrMetallicRoughness": {"baseColorFactor": [0.19, 0.11, 0.11, 1.0], "roughnessFactor": 0.80, "metallicFactor": 0.0}},
        ],
        "buffers": [{"byteLength": len(buffer)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": offsets["positions"][0], "byteLength": offsets["positions"][1], "target": 34962},
            {"buffer": 0, "byteOffset": offsets["normals"][0], "byteLength": offsets["normals"][1], "target": 34962},
            {"buffer": 0, "byteOffset": offsets["indices"][0], "byteLength": offsets["indices"][1], "target": 34963},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": vertex_count, "type": "VEC3", "min": [-1, -1, -1], "max": [1, 1, 1]},
            {"bufferView": 1, "componentType": 5126, "count": vertex_count, "type": "VEC3", "min": [-1, -1, -1], "max": [1, 1, 1]},
            {"bufferView": 2, "componentType": 5123, "count": (14 * 20 * 6), "type": "SCALAR", "min": [0], "max": [vertex_count - 1]},
        ],
    }
    json_bytes = json.dumps(json_doc, separators=(",", ":")).encode("utf-8")
    json_bytes = align_json4(json_bytes)
    binary = bytes(buffer)
    total_length = 12 + 8 + len(json_bytes) + 8 + len(binary)
    return b"glTF" + struct.pack("<II", 2, total_length) + struct.pack("<II", len(json_bytes), 0x4E4F534A) + json_bytes + struct.pack("<II", len(binary), 0x004E4942) + binary


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(build_glb())
    print(f"Wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
