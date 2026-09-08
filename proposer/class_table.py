"""ottoq_vehicle_classes -> the class table the production bridge reads.

THE PROJECTION THAT WAS MISSING (finding L-41). proposer/README.md said the
class join "in production is ottoq_vehicle_classes"; it was not joinable and
the column names did not match, so the sentence described an integration that
had never been written. Three separate mismatches, all now closed:

  1. THE KEY. The table is keyed by `vehicle_class_code`; the frame emitted
     `platform` and not the class code. Migration 0209 adds the key to the
     frame, and frame_to_scenario's `class_key` names which frame field to
     join on -- defaulting to the production one.
  2. THE NAMES. `battery_capacity_kwh` / `max_charge_rate_kw` in the table;
     `battery_kwh` / `max_charge_kw` in the kernel. Passing a row verbatim
     raised KeyError. The rename is written down ONCE, here.
  3. charge_kinds HAD NO COLUMN. Migration 0209 adds it (backfilled from
     fast_charge_compatible, derivation recorded in the column COMMENT) so the
     bridge's refusal to default it is satisfiable from production data.

THIS MODULE TRANSLATES AND NEVER DECIDES -- the adapter law (CLAUDE.md 2.2,
C10). It renames fields and drops the ones the kernel has no use for. It never
supplies a battery size, a charge rate or a capability that the row does not
carry: a class row missing any required field RAISES, naming the class, exactly
as frame_to_scenario does. A guessed battery is a silently wrong plan for every
vehicle of that class.
"""

from __future__ import annotations

#: The query this projection is written against, committed so the SELECT and
#: the mapping below cannot drift apart. `status = 'active'` is the caller's
#: choice to make; the projection accepts whatever rows it is handed.
SELECT_VEHICLE_CLASSES = """
SELECT vehicle_class_code,
       battery_capacity_kwh,
       max_charge_rate_kw,
       charge_kinds,
       energy_curve,
       battery_chemistry
  FROM public.ottoq_vehicle_classes
 WHERE status = 'active'
 ORDER BY vehicle_class_code
"""

#: table column -> kernel field. Every rename in one place, so a reader can see
#: the whole translation without reading code.
REQUIRED = {
    "battery_capacity_kwh": "battery_kwh",
    "max_charge_rate_kw": "max_charge_kw",
    "charge_kinds": "charge_kinds",
}
OPTIONAL = {
    #: The kernel's piecewise acceptance curve; absent means the bridge's flat
    #: default, which is the kernel's own documented fallback.
    "energy_curve": "energy_curve",
    #: NOT a cap. The bridge maps a chemistry to a daily SoC cap (R-11); the
    #: table has no max_daily_soc_pct column, and inventing one here would put
    #: a scheduling opinion in a translator.
    "battery_chemistry": "battery_chemistry",
}


class ClassTableError(ValueError):
    """A class row this projection refuses to guess around."""


def class_table_from_rows(rows) -> dict[str, dict]:
    """Rows as the database returns them -> {vehicle_class_code: class dict}.

    Numeric columns arrive as Decimal from psycopg and as str from PostgREST;
    both are coerced to float here so the kernel sees one type regardless of
    which client fetched them. A row that cannot be coerced raises rather than
    being dropped -- a class that vanishes silently takes every vehicle of that
    class with it.
    """
    out: dict[str, dict] = {}
    for row in rows:
        code = row.get("vehicle_class_code")
        if not code:
            raise ClassTableError("a class row carries no vehicle_class_code; "
                                  "it cannot be joined to anything")
        if code in out:
            raise ClassTableError(f"duplicate vehicle_class_code {code!r}; the "
                                  f"class table would silently keep one of them")
        cls: dict = {}
        for column, field in REQUIRED.items():
            if row.get(column) is None:
                raise ClassTableError(
                    f"class {code!r} has no {column}; the kernel needs it as "
                    f"{field!r} and there is no safe default for it")
            cls[field] = row[column]
        cls["battery_kwh"] = _number(code, "battery_capacity_kwh", cls["battery_kwh"])
        cls["max_charge_kw"] = _number(code, "max_charge_rate_kw", cls["max_charge_kw"])
        cls["charge_kinds"] = _kinds(code, cls["charge_kinds"])
        for column, field in OPTIONAL.items():
            if row.get(column) is not None:
                cls[field] = row[column]
        out[code] = cls
    return out


def _number(code: str, column: str, value) -> float:
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        raise ClassTableError(f"class {code!r} has a non-numeric {column}: "
                              f"{value!r}") from exc


def _kinds(code: str, value) -> list[str]:
    #: A postgres text[] arrives as a list from psycopg and as a list from
    #: PostgREST; a string means somebody handed us the raw '{dcfc,l2}' literal,
    #: which would iterate as characters and produce a class capable of 'd'.
    if isinstance(value, str):
        raise ClassTableError(
            f"class {code!r} has charge_kinds as a string ({value!r}); pass the "
            f"text[] as a list, not its postgres literal")
    kinds = [str(k) for k in value]
    if not kinds:
        raise ClassTableError(
            f"class {code!r} has an empty charge_kinds; it names no service "
            f"point type this class can use, so no vehicle of it is plannable")
    return kinds
