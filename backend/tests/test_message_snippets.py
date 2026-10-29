from app.shared.message_snippets import snippet


def test_short_text_is_kept_with_whitespace_collapsed():
    assert snippet('  see   you\nat 5 ') == 'see you at 5'


def test_long_text_is_cut_at_a_word_with_an_ellipsis():
    text = 'word ' * 30
    out = snippet(text, limit=20)
    assert out.endswith('…') and len(out) <= 21 and 'wor…' not in out


def test_a_deleted_message_is_never_quoted():
    assert snippet('secret', deleted=True) == ''
    assert snippet(None) == ''
