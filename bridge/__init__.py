"""bridge/ -- the proposer's database client.

NOT a kernel package (tests/test_separation.py, NON_KERNEL_PACKAGES). It is the
one place that holds a database connection on the proposer's behalf: it reads
the decision frame, calls proposer.forward_proposer.propose(), and submits the
rows through public.ottoq_submit_external_proposal. The kernel packages never
import it, and the separation guard bans the import.
"""
