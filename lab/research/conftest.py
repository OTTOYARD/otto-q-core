# lab/research/conftest.py -- the research wing's scripts in this folder are run by hand against the lab's own database
# server (lab/engine/README.md), never collected by the repository's pytest run: they need psycopg and a running lab
# server, which CI does not have. lab/research/p1_agent_challenger/test_0795.py is such a script (an executed check with
# its own main(), cited by db/migrations/0795 under that name), not a pytest module. The lab's unit tests elsewhere
# (lab/safety/tests/) are collected as before.
collect_ignore_glob = ["*"]
