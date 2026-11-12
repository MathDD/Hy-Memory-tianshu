from datetime import UTC, datetime

from one_memory.call_event_recorder import ask_call_event
from one_memory.memory_governance import GovernedMemory, MemoryKind, MemoryOrigin, MemoryStatus
from one_memory.memory_qa import MemoryAnswer


def test_ask_records_memory_refs_without_answer():
    memory = GovernedMemory(
        memory_id="m1",
        user_id="local",
        kind=MemoryKind.CHAT,
        status=MemoryStatus.CONFIRMED,
        content="SECRET_MEMORY",
        scopes=("all-apps",),
        evidence_ids=("e1",),
        origin=MemoryOrigin.EXTRACTED,
        revision=4,
        created_at=datetime.now(UTC),
        updated_at=datetime.now(UTC),
        deleted_at=None,
    )
    event = ask_call_event(
        MemoryAnswer(answer="SECRET_ANSWER", memories=(memory,), mode="extractive"),
        None,
        8.0,
    )
    encoded = event.model_dump_json()
    assert event.tool == "om_ask" and event.state == "grounded"
    assert event.memory_count == 1 and event.references[0].id == "m1"
    assert event.references[0].revision == 4
    assert "SECRET" not in encoded


def test_tianshu_installation_is_attributed_to_the_host_it_came_from():
    """The recorder keeps a closed set of host ids.

    天枢 was missing from it, so its calls were stored with a null `host_id`
    even though the installation and its scopes resolved: the app could see
    that *something* had called, and nothing could say which app.
    """
    from one_memory.call_event_recorder import HOSTS
    from one_memory.external_memory_access import ExternalMemoryAccess
    from one_memory.memory_qa import MemoryAnswer

    assert "tianshu" in HOSTS

    access = ExternalMemoryAccess(
        installation_id="6ddd9385-93da-49e3-a988-edda531ee2c1",
        revision=2,
        scopes=frozenset({"all-apps", "source:tianshu"}),
        tools=frozenset({"om_recall"}),
        host_id="tianshu",
    )
    event = ask_call_event(
        MemoryAnswer(answer="在", memories=(), mode="extractive"),
        access,
        1.0,
    )
    assert event.host_id == "tianshu"
    assert str(event.installation_id) == "6ddd9385-93da-49e3-a988-edda531ee2c1"
