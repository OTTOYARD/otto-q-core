import sys, time, json
import os; sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'lib'))
import psycopg
from lab_run import Arm, clone_database
D = "host=/var/tmp port=55433 user=postgres"
with psycopg.connect(f"{D} dbname=postgres", autocommit=True) as admin:
    clone_database(admin, 'ottoq_lab', 'ottoq_lab_t2')
out = {}
# A: two arms, each in its own transaction, committed (the second sees the first's rows)
with psycopg.connect(f"{D} dbname=ottoq_lab_t2", autocommit=False) as conn:
    for k in ('arm1_own_txn', 'arm2_own_txn_after_commit'):
        t0 = time.perf_counter()
        arm = Arm(conn, seed=171717); arm.start(); arm.tick(12)
        h = arm.q("SELECT public.ottoq_ab_arm_atoms(%s, %s)->>'h_evt'", (arm.depot, arm.run))[0][0]
        arm.finish(); conn.commit()
        out[k] = {"seconds": round(time.perf_counter() - t0, 1), "tick_seconds": [round(x, 2) for x in arm.tick_seconds], "h_evt": h}
# B: two arms in ONE transaction, as the pair does
with psycopg.connect(f"{D} dbname=ottoq_lab_t2", autocommit=False) as conn:
    for k in ('arm1_shared_txn', 'arm2_shared_txn'):
        t0 = time.perf_counter()
        arm = Arm(conn, seed=171717); arm.start(); arm.tick(12)
        h = arm.q("SELECT public.ottoq_ab_arm_atoms(%s, %s)->>'h_evt'", (arm.depot, arm.run))[0][0]
        arm.finish()
        out[k] = {"seconds": round(time.perf_counter() - t0, 1), "tick_seconds": [round(x, 2) for x in arm.tick_seconds], "h_evt": h}
    conn.rollback()
json.dump(out, open(sys.argv[1], 'w'), indent=1)
for k, v in out.items(): print(k, v['seconds'], 's; median tick', sorted(v['tick_seconds'])[6], 'h_evt', v['h_evt'][:8])
