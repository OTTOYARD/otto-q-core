# Canon baselines

## Why this directory exists

`db/checks/0078` §2 recorded a gap found the hard way. After five `forces_recert`
migrations landed on 2026-09-02, six certification columns re-ran and all six
passed — but only **one** of them could be compared against its pre-change value,
because only that one had a canon written down in the repo (`db/checks/0075` §4).

For the other five the round-8 values were a *new baseline, not a comparison*.
Five passing rows made "today's migrations introduced no carrier" an easy claim
to write, and it was not available from the evidence.

`ottoq_cert_matrix` carries canon history in the database, but the database is
where the engine lives. A canon committed to the repo is the thing an engine
change is diffed *against* — it survives a purge, it appears in a PR diff, and a
reviewer can see it move.

## The rule

**Commit all six canons at the end of every certification round.** One file per
round, named `round<N>.md`. Never edit a past round's file: a canon that changed
is the finding, and rewriting history destroys it.

## Regenerating

```sql
SELECT depot::text AS depot, scenario, seed, ticks,
       canon_cmd, canon_dec, canon_bkg, canon_nrg,
       canon_prop, canon_defr,            -- 0199: written by the pair from round 19 on
       pairs_seen, consecutive_passes, green
  FROM public.ottoq_cert_matrix(public.ottoq_cert_recert_floor())
 ORDER BY scenario, seed, ticks;
```

`ottoq_cert_recert_floor()` is the cutoff below which pairs no longer count,
raised by every `forces_recert` migration — whether registered in
`supabase_migrations` or only classified in `ottoq_cert_lineage` (0199; before it,
six recerts applied through the SQL endpoint did not move the floor). A column with `green = false` has not
yet shown two consecutive passes at the current floor, so its canon is provisional
— record it anyway and mark it, because a provisional canon that later moves is
still evidence.

## Reading a diff between rounds

- `h_cmd` — the vehicle command stream
- `h_dec` — the decision stream, including rationale content
- `h_bkg` — the booking stream: **the assignments themselves**
- `h_nrg` — the energy command stream
- `h_prop` — the proposal stream (`ottoq_external_proposals`, content multiset;
  0199). Moves with `h_cmd` when a proposer saw the same coin the disposer did;
  moves alone when a proposer is nondeterministic while the disposer is not.
- `h_defr` — the cuOpt deferral ledger (0199). `d41d8cd9` = empty: the 0152
  quiesce is holding.

A migration that only adds keys to a decision rationale moves `h_dec` and nothing
else. A migration that changes what the engine *decides* moves `h_bkg`. That
distinction is the whole value of keeping four separate hashes, and it is only
usable if the previous round's values are on disk.
