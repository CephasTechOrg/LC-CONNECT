"""Server-side user search backing the scholar picker (`GET /admin/users?q=&role=`).

Search must happen in SQL, not in the browser: the endpoint is capped, so a client-side filter
would silently hide anyone outside the cap — on a real campus roster the person you're looking
for usually isn't in the most recent signups.
"""

from __future__ import annotations

from app.features.admin.router import list_users


async def _student(db, factory, *, name: str, email: str | None = None):
    user = await factory.user(display_name=name)
    if email:
        user.email = email
    await db.commit()
    return user


async def test_search_matches_display_name_case_insensitively(db, factory):
    await _student(db, factory, name='Amara Johnson')
    await _student(db, factory, name='Kwame Mensah')

    results = await list_users(q='amara', role=None, _=None, db=db)
    assert [r.display_name for r in results] == ['Amara Johnson']


async def test_search_matches_email(db, factory):
    await _student(db, factory, name='Amara Johnson', email='amara.j@students.livingstone.edu')
    await _student(db, factory, name='Kwame Mensah', email='kwame.m@students.livingstone.edu')

    results = await list_users(q='kwame.m@', role=None, _=None, db=db)
    assert [r.display_name for r in results] == ['Kwame Mensah']


async def test_role_filter_excludes_non_students(db, factory):
    student = await _student(db, factory, name='Real Student')
    staff = await _student(db, factory, name='Real Staff')
    staff.role = 'staff'
    await db.commit()

    results = await list_users(q=None, role='student', _=None, db=db)
    names = {r.display_name for r in results}
    assert 'Real Student' in names
    assert 'Real Staff' not in names
    assert student.id in {r.id for r in results}


async def test_wildcards_in_search_are_escaped_not_interpreted(db, factory):
    """A literal '%' must search for that character, not match every row — otherwise a stray
    keystroke silently returns the entire roster and looks like a working search."""
    await _student(db, factory, name='Normal Name')
    await _student(db, factory, name='Odd%Name')

    results = await list_users(q='%', role=None, _=None, db=db)
    assert [r.display_name for r in results] == ['Odd%Name']


async def test_no_params_returns_everyone(db, factory):
    await _student(db, factory, name='One')
    await _student(db, factory, name='Two')

    results = await list_users(q=None, role=None, _=None, db=db)
    assert len(results) >= 2


async def test_blank_query_is_ignored_not_treated_as_a_filter(db, factory):
    await _student(db, factory, name='Someone')
    results = await list_users(q='   ', role=None, _=None, db=db)
    assert len(results) >= 1


async def test_search_returns_profile_display_name_and_email(db, factory):
    user = await _student(db, factory, name='Display Me')
    results = await list_users(q='Display Me', role=None, _=None, db=db)
    assert results[0].display_name == 'Display Me'
    assert results[0].email == user.email
