"""csms/deploy/deploy_ssm.py, the parts that run here: what ships, and that the box rebuilds it byte for byte."""
import io
import os
import subprocess
import sys
import tarfile
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "deploy"))
import deploy_ssm  # noqa: E402


def test_the_service_ships_whole_and_the_same_every_time():
    a, b = deploy_ssm.tarball(), deploy_ssm.tarball()
    assert a == b
    assert sorted(tarfile.open(fileobj=io.BytesIO(a)).getnames()) == sorted(deploy_ssm.SHIP)


def test_the_chunks_rebuild_the_tarball_under_sh():
    t = deploy_ssm.tarball()
    with tempfile.TemporaryDirectory() as d:
        dest = os.path.join(d, "x.tgz")
        out = subprocess.run(["sh", "-c", "\n".join(deploy_ssm.chunked(t, dest, "SRC"))], capture_output=True, text=True)
        assert out.returncode == 0 and f"DECODED_SRC {len(t)} bytes" in out.stdout
        assert open(dest, "rb").read() == t


def test_no_command_prints_the_key():
    for script in (deploy_ssm.DISCOVER, deploy_ssm.MAKE_KEY, deploy_ssm.DEPLOY):
        for line in script.splitlines():
            if "/etc/ottoq-csms/key" in line and ("echo" in line or "cat " in line):
                assert "sha256sum" in line or "head -c 14" in line or "KEY_MADE" in line or "-f /etc" in line, line
