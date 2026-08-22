"""The paper packs must load, declare, and refuse. All three are the contract."""
from __future__ import annotations

import pytest

from adapters.base import assert_translation_only
from adapters.mining.adapter import (DECLARED_CONSTRAINTS as MINING_C, MiningAdapter,
                                     MiningAdapterNotImplemented)
from adapters.vertiport.adapter import (DECLARED_CONSTRAINTS as VERTIPORT_C,
                                        VertiportAdapter, VertiportAdapterNotImplemented)


@pytest.mark.parametrize("cls", [MiningAdapter, VertiportAdapter])
def test_paper_packs_still_obey_the_laws(cls):
    assert_translation_only(cls)


@pytest.mark.parametrize("cls,exc", [(MiningAdapter, MiningAdapterNotImplemented),
                                     (VertiportAdapter, VertiportAdapterNotImplemented)])
def test_paper_packs_refuse_to_run(cls, exc):
    a = cls()
    with pytest.raises(exc):
        a.inbound({})
    with pytest.raises(exc):
        a.outbound(None)


def test_the_kernel_breaker_constraints_are_declared_before_c11_runs():
    # C11's verdict must be checkable against what we said BEFOREHAND.
    assert "C6_Operator_Override_Overrules_System" in MINING_C
    assert "Charger_Compatibility" in VERTIPORT_C
