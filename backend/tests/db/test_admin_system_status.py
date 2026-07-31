"""Admin dashboard System Status — every field must reflect a real check, never a hardcoded value."""

from __future__ import annotations

from app.features.admin import system_status
from app.shared import supabase_admin
from app.shared.storage import storage_service


async def test_all_operational_when_every_check_succeeds(db, monkeypatch):
    monkeypatch.setattr(supabase_admin, 'ping', lambda: True)
    monkeypatch.setattr(storage_service, 'ping', lambda: True)

    result = await system_status.get_system_status(db)
    assert result.api_gateway == 'operational'
    assert result.database == 'operational'
    assert result.auth == 'operational'
    assert result.storage == 'operational'


async def test_auth_down_when_ping_fails(db, monkeypatch):
    monkeypatch.setattr(supabase_admin, 'ping', lambda: False)
    monkeypatch.setattr(storage_service, 'ping', lambda: True)

    result = await system_status.get_system_status(db)
    assert result.auth == 'down'
    assert result.storage == 'operational'


async def test_storage_down_when_ping_fails(db, monkeypatch):
    monkeypatch.setattr(supabase_admin, 'ping', lambda: True)
    monkeypatch.setattr(storage_service, 'ping', lambda: False)

    result = await system_status.get_system_status(db)
    assert result.storage == 'down'
    assert result.auth == 'operational'


def test_supabase_admin_ping_false_when_unconfigured(monkeypatch):
    monkeypatch.setattr(supabase_admin, '_client', None)
    assert supabase_admin.ping() is False


def test_supabase_admin_ping_false_on_exception(monkeypatch):
    class _Boom:
        class auth:
            class admin:
                @staticmethod
                def list_users(*_a, **_kw):
                    raise RuntimeError('network error')

    monkeypatch.setattr(supabase_admin, '_client', _Boom())
    assert supabase_admin.ping() is False


def test_storage_ping_false_when_unconfigured(monkeypatch):
    monkeypatch.setattr(storage_service, 'client', None)
    assert storage_service.ping() is False


def test_storage_ping_false_on_exception(monkeypatch):
    class _Boom:
        class storage:
            @staticmethod
            def list_buckets():
                raise RuntimeError('network error')

    monkeypatch.setattr(storage_service, 'client', _Boom())
    assert storage_service.ping() is False
