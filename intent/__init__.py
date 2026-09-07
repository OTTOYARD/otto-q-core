"""The intent artifact — machine-readable commander's intent.

`intent_v1.json` declares the full objective taxonomy, the regime-conditioned
priority orderings, and the numeraire decision. `intent.py` loads, verifies
(fingerprint), and resolves the active regime. See `README.md` for the design
and the honest statement of what is wired versus pending.
"""

from intent.intent import (  # noqa: F401
    ActiveIntent, Intent, load_intent, resolve_intent, stamp,
)

__all__ = ["ActiveIntent", "Intent", "load_intent", "resolve_intent", "stamp"]
