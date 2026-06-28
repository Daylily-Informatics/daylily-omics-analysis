from pathlib import Path


def test_sentdhiomr_mito_uses_writable_tmp_root() -> None:
    rule_text = (
        Path(__file__).resolve().parents[1]
        / "workflow"
        / "rules"
        / "sent_hybrid_ilmn_ont_modular.refactored.smk"
    ).read_text()
    start = rule_text.index("rule sentdhiomr_mito_call:")
    end = rule_text.index("rule produce_sentdhiomr_mito:", start)
    rule_block = rule_text[start:end]

    assert 'tmp_parent="/tmp"' in rule_block
    assert 'test -w "$tmp_parent"' in rule_block
    assert "mktemp -d" in rule_block
    assert 'TMPDIR="/scratch' not in rule_text
    assert "/scratch/sentdhiomr" not in rule_text
