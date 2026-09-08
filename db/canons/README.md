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
       canon_fp, canon_cmd, canon_dec, canon_evt, canon_bkg, canon_nrg,
       canon_prop, canon_defr,            -- 0199: written by the pair from round 19 on
       canon_cal,                         -- 0201
       canon_rule, canon_rcl,             -- carried and printed, NOT compared (see below)
       pairs_seen, consecutive_passes, green
  FROM public.ottoq_cert_matrix(public.ottoq_cert_recert_floor())
 ORDER BY scenario, seed, ticks;
```

**This query is not the whole canon, and the matrix is not the whole judge.**
Corrected 2026-09-08: the version above previously listed six canon columns when
the function returns eleven, which was merely stale. The part that is not merely
stale is `db/checks/0134`:

| the pair enforces | the matrix compares |
|---|---|
| `fp` `h_cmd` `h_dec` `h_evt` `h_bkg` `h_nrg` | strictly |
| `h_prop` `h_defr` `h_cal` | NULL-tolerantly (0199/0201) |
| `h_rule` (0205) · `h_rcl` (0217) | **carried, printed, never compared** |
| `h_sdr` (0219) · `endst` (0139) | **not carried at all** |

Fourteen equalities in the pair, nine in `on_canon` — and `on_canon` is what
feeds `consecutive_passes`, which feeds `green`. So **four enforced atoms can
move between rounds without breaking a streak**, and two of them appear in the
matrix's output looking exactly like the ones that would.

Until that is fixed, the round file you write by hand is the only place those
four are compared. Copy `h_rule`, `h_rcl`, `h_sdr` and the `endst` verdict into
every round file and diff them against the previous round yourself. That is not
belt-and-braces; for those four it is the only belt.

### And the same is true of the whole across-round comparison, right now

**`db/checks/0135` (G28): since 2026-09-04 15:00, no `forces_recert: FALSE`
classification has reached the floor function at all.** It joins
`ottoq_cert_lineage` to `supabase_migrations` on the raw name, and every lineage
row since that date carries the `NNNN_` file prefix the apply path does not
write — so 33 of 92 fall through the conservative default and the floor jumps to
the newest migration after every apply. Measured 2026-09-08: **not one column
green, six of seven stale, and one column carrying twenty-six consecutive
passing pairs against a `consecutive_passes` of zero.**

So while 0134's four atoms are the part the matrix *cannot* see, G28 means the
matrix has not been seeing anything. Between them: **for four days the round
file you write by hand has not been the last belt, it has been the only one.**
Fix drafted as `0226`; until it is applied and a round runs above the corrected
floor, treat every `green` in the matrix as unavailable rather than false.

`ottoq_cert_recert_floor()` is the cutoff below which pairs no longer count,
raised by every `forces_recert` migration — whether registered in
`supabase_migrations` or only classified in `ottoq_cert_lineage` (0199; before it,
six recerts applied through the SQL endpoint did not move the floor), and, per
G28 above, currently raised by every migration whether or not it forces one. A
column with `green = false` has not yet shown two consecutive passes at the
current floor, so its canon is provisional — record it anyway and mark it,
because a provisional canon that later moves is still evidence.

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
- `h_cal` — the calibration priors the arm booted on (0201).
- `h_rule` — the L1 shield's disposals (enforced 0205).
- `h_rcl` — the recall-decision ledger (enforced 0217).
- `h_sdr` — the settlement records (enforced 0219). Its first correct value is
  post-0218; anything earlier is the contaminated kind and must not be used as a
  baseline.
- `endst` — the end-state fingerprint, id-blind since 0139. Compared with `->`
  rather than `->>` because it is a JSON object, not a string.

A migration that only adds keys to a decision rationale moves `h_dec` and nothing
else. A migration that changes what the engine *decides* moves `h_bkg`. That
distinction is the whole value of keeping the hashes separate, and it is only
usable if the previous round's values are on disk.
