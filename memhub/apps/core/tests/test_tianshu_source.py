"""天枢 (Rivet) sessions are zstd frames in a ``.jsonl`` container.

Two traits of that directory are easy to get wrong, and both broke a real
import before they were pinned here:

* ``~/.rivet/sessions`` holds one directory per session full of plain-JSON
  working files (``frames.jsonl``, ``cache-log.jsonl``, ``sensorium.jsonl``,
  ``tool-result-trace.jsonl``). They are the host's bookkeeping, not dialogue.
* Not every ``.jsonl`` in the tree is a zstd frame. Assuming the extension was
  enough made the scan hand a plain file to the decompressor and fail the whole
  source with "Unknown frame descriptor".
"""

import asyncio
import hashlib
import json
from pathlib import Path

import zstandard

from one_memory.imports.access import AuthorizedSourceRoot
from one_memory.imports.adapters import ScanOptions, ScannedEvidence
from one_memory.imports.sources.tianshu import create_tianshu_adapter


def grant(root: Path) -> AuthorizedSourceRoot:
    return AuthorizedSourceRoot.grant(
        source_id="tianshu",
        root=root,
        user_confirmed=True,
        home=root.parent / "other-home",
    )


def write_rivet_transcript(path: Path, records: list[dict]) -> None:
    """One zstd frame per line, each line ending in Rivet's ``|<hex>`` tag."""
    path.parent.mkdir(parents=True, exist_ok=True)
    frames = []
    for record in records:
        line = json.dumps(record).encode("utf-8")
        checksum = hashlib.sha256(line).hexdigest()[:8]
        frames.append(
            zstandard.ZstdCompressor().compress(
                line + b"|" + checksum.encode() + b"\n"
            )
        )
    path.write_bytes(b"".join(frames))


def write_plain_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "".join(f"{json.dumps(record)}\n" for record in records),
        encoding="utf-8",
    )


def scanned(events) -> list:
    return [event for event in events if isinstance(event, ScannedEvidence)]


def test_scan_reads_transcripts_and_skips_session_sidecars(tmp_path: Path) -> None:
    root = tmp_path / "sessions"
    session = root / "11111111-1111-1111-1111-111111111111"
    write_rivet_transcript(
        session.with_suffix(".jsonl"),
        [
            {"role": "user", "content": "帮我把这周的排查结论整理一下"},
            {"role": "assistant", "content": "好的，我先按时间线排一遍。"},
        ],
    )
    session.with_suffix(".meta.json").write_text(
        json.dumps(
            {
                "sessionId": "11111111-1111-1111-1111-111111111111",
                "cwd": "/Users/apple/projects/demo",
                "model": "claude-sonnet",
            }
        ),
        encoding="utf-8",
    )
    write_plain_jsonl(
        session / "frames.jsonl",
        [{"kind": "frame", "index": 0}],
    )
    write_plain_jsonl(
        session / "tool-result-trace.jsonl",
        [{"role": "tool", "content": "tool result should never be a turn"}],
    )

    adapter = create_tianshu_adapter(grant(root))

    async def collect():
        return [event async for event in adapter.scan(ScanOptions())]

    records = scanned(asyncio.run(collect()))

    assert [item.evidence.verbatim for item in records] == [
        "帮我把这周的排查结论整理一下",
        "好的，我先按时间线排一遍。",
    ]
    assert {item.evidence.conversation_id for item in records} == {
        "11111111-1111-1111-1111-111111111111"
    }
    # Evidence keeps a workspace by identity, not by path, so the assertion is
    # about the one workspace the session ran in rather than its text.
    workspaces = {item.evidence.workspace for item in records}
    assert len(workspaces) == 1
    assert next(iter(workspaces)).startswith("workspace:v1:")


def test_plain_transcript_is_read_as_jsonl_not_decompressed(tmp_path: Path) -> None:
    """A transcript Rivet never compressed still imports, line by line."""
    root = tmp_path / "sessions"
    write_plain_jsonl(
        root / "22222222-2222-2222-2222-222222222222.jsonl",
        [
            {"role": "user", "content": "这条是明文写的"},
            {"role": "user", "origin": "hook", "content": "host injected preamble"},
        ],
    )

    adapter = create_tianshu_adapter(grant(root))

    async def collect():
        return [event async for event in adapter.scan(ScanOptions())]

    records = scanned(asyncio.run(collect()))

    assert [item.evidence.verbatim for item in records] == ["这条是明文写的"]
