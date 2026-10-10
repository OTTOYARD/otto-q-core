"""Put OTTO-Q's charger back end (csms/csms_service.py) on the AWS box beside the intelligence service, over Systems Manager.

    python3 -I csms/deploy/deploy_ssm.py discover    # read only: the box, its load, and whether the key exists
    python3 -I csms/deploy/deploy_ssm.py make-key    # make the back end's key ON THE BOX if it has none; print its hash
    python3 -I csms/deploy/deploy_ssm.py deploy      # ship csms/, build the image, run it with CPU and memory limits
    python3 -I csms/deploy/deploy_ssm.py stop        # remove the container (the twin does not depend on it)

Credentials are the caller's AWS environment (boto3's usual chain); none is written anywhere here. From GitHub it runs
in ottoq-intelligence's csms-deploy-ssm workflow, with that repository's AWS secrets, by hand only. It follows
ottoq-intelligence/.github/workflows/aws-deploy-ssm.yml, whose failures taught most of it: the target is found by its
Name tag and refused unless exactly one is running and SSM reports it Online; the source ships as a tarball in printf
chunks of base64 with a breadcrumb after each step, because the box has no git and a single decode line once failed with
nothing to say; the poll waits up to 55 minutes because a docker build on a t3.medium takes minutes; and stdout past
24,000 characters is cut by SSM, so the box prints little and says when it was cut.

THE KEY NEVER LEAVES THE BOX. make-key writes it to /etc/ottoq-csms/key (mode 0400, owned by the container's user) and
prints only its SHA-256 and its 14-character prefix, which a person registers with
public.ottoq_register_source_key_hash (db/migrations/0697). The container reads it as a read-only file.

The container: --cpus 0.25 --memory 256m, read-only root, loopback only for the back end (its stations are the
bridge's), outbound HTTPS to the relay, restart unless stopped, state in /var/lib/ottoq-csms.
"""
from __future__ import annotations

import base64
import gzip
import hashlib
import io
import os
import sys
import tarfile
import textwrap
import time

NAME = "ottoq-intel-2"
REGION = "us-east-1"
RELAY = "https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-csms-relay"
HERE = os.path.dirname(os.path.abspath(__file__))
CSMS = os.path.dirname(HERE)
SHIP = ["csms_server.py", "station_sim.py", "charger_bridge.py", "csms_relay.py", "csms_service.py", "Dockerfile"]


def tarball() -> bytes:
    """csms/'s service files, reproducibly (sorted, mtime 0, owner 0, and no build time in the gzip header)."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for name in sorted(SHIP):
            data = open(os.path.join(CSMS, name), "rb").read()
            info = tarfile.TarInfo(name)
            info.size, info.mtime, info.uid, info.gid, info.mode = len(data), 0, 0, 0, 0o644
            tar.addfile(info, io.BytesIO(data))
    # tarfile's "w:gz" stamps the gzip header with the time it ran (RFC 1952's MTIME), so two builds a second apart
    # differed; compressed here with mtime 0, the same sources give the same bytes and the same sha256 every time
    return gzip.compress(buf.getvalue(), compresslevel=9, mtime=0)


def chunked(data: bytes, dest: str, label: str) -> list[str]:
    b64 = base64.b64encode(data).decode()
    out = [f"rm -f {dest}.b64"]
    out += [f"printf '%s' '{c}' >> {dest}.b64" for c in textwrap.wrap(b64, 700)]
    out += [f'echo "WROTE_{label} $(wc -c < {dest}.b64) bytes"', f"base64 -d {dest}.b64 > {dest}",
            f'echo "DECODED_{label} $(wc -c < {dest}) bytes"']
    return out


DISCOVER = r"""
echo "--- the box ---"
echo "nproc=$(nproc) loadavg=$(cut -d' ' -f1-3 /proc/loadavg) mem: $(free -m | awk '/Mem:/ {print $2" MB total, "$7" MB available"}')"
docker ps -a --format '  {{.Names}}  {{.Image}}  {{.Status}}' 2>/dev/null | head -10
docker stats --no-stream --format '  {{.Name}}  cpu={{.CPUPerc}}  mem={{.MemUsage}}' 2>/dev/null | head -10
if [ -f /etc/ottoq-csms/key ]; then
  echo "KEY_PRESENT sha256=$(tr -d '\n' < /etc/ottoq-csms/key | sha256sum | cut -d' ' -f1) prefix=$(head -c 14 /etc/ottoq-csms/key)"
else
  echo "KEY_ABSENT"
fi
"""

MAKE_KEY = r"""
set -euo pipefail
mkdir -p /etc/ottoq-csms && chmod 0700 /etc/ottoq-csms
if [ ! -f /etc/ottoq-csms/key ]; then
  ( umask 077; python3 -c "import secrets; print('ottow_' + secrets.token_hex(32), end='')" > /etc/ottoq-csms/key )
  echo "KEY_MADE"
fi
chown 65534:65534 /etc/ottoq-csms/key && chmod 0400 /etc/ottoq-csms/key
echo "KEY sha256=$(tr -d '\n' < /etc/ottoq-csms/key | sha256sum | cut -d' ' -f1) prefix=$(head -c 14 /etc/ottoq-csms/key)"
"""

DEPLOY = r"""
set -euo pipefail
[ -f /etc/ottoq-csms/key ] || { echo "FATAL: no key; run make-key and register its hash first"; exit 1; }
mkdir -p /opt/ottoq-csms/src /var/lib/ottoq-csms
chown 65534:65534 /var/lib/ottoq-csms
rm -rf /opt/ottoq-csms/src/* && tar xzf /tmp/ottoq_csms.tgz -C /opt/ottoq-csms/src && echo EXTRACTED
TAG="ottoq-csms:__SRC12__"
docker build -q -t "$TAG" /opt/ottoq-csms/src | tail -1 && echo "BUILT $TAG"
docker rm -f ottoq-csms >/dev/null 2>&1 || true
docker run -d --name ottoq-csms --restart unless-stopped --cpus 0.25 --memory 256m --read-only --tmpfs /tmp \
  -v /var/lib/ottoq-csms:/var/lib/ottoq-csms -v /etc/ottoq-csms/key:/run/secrets/ottoq_csms_key:ro \
  -e OTTOQ_CSMS_KEY_FILE=/run/secrets/ottoq_csms_key -e OTTOQ_CSMS_RELAY=__RELAY__ \
  -e OTTOQ_CSMS_STATE=/var/lib/ottoq-csms/relay.json "$TAG" >/dev/null && echo STARTED
sleep 20
docker inspect ottoq-csms --format 'state={{.State.Status}} restarts={{.RestartCount}} oom={{.State.OOMKilled}}'
docker logs ottoq-csms --tail 30 2>&1
docker logs ottoq-csms 2>&1 | grep -q "back end listening" && echo "VERIFIED: the back end is listening" || echo "NOT VERIFIED"
"""

STOP = "docker rm -f ottoq-csms && echo STOPPED || echo NOTHING_TO_STOP\n"


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in ("discover", "make-key", "deploy", "stop"):
        print(__doc__)
        return 2
    import boto3  # imported here so the module loads (and is tested) without it
    ec2, ssm = boto3.client("ec2", region_name=REGION), boto3.client("ssm", region_name=REGION)
    res = ec2.describe_instances(Filters=[{"Name": "tag:Name", "Values": [NAME]},
                                          {"Name": "instance-state-name", "Values": ["running"]}])
    ids = [i["InstanceId"] for r in res["Reservations"] for i in r["Instances"]]
    if len(ids) != 1:
        print(f"REFUSING: expected exactly one running instance named {NAME}, found {len(ids)}")
        return 1
    iid = ids[0]
    info = ssm.describe_instance_information(Filters=[{"Key": "InstanceIds", "Values": [iid]}])["InstanceInformationList"]
    if not info or info[0].get("PingStatus") != "Online":
        print(f"REFUSING: SSM does not report {iid} Online")
        return 1
    mode = argv[1]
    cmds = ["echo BEGIN"]
    if mode == "discover":
        cmds += [DISCOVER]
    elif mode == "make-key":
        cmds += [MAKE_KEY]
    elif mode == "stop":
        cmds += [STOP]
    else:
        tgz = tarball()
        src12 = hashlib.sha256(tgz).hexdigest()[:12]
        print(f"shipping {len(tgz)} bytes, sha256 {hashlib.sha256(tgz).hexdigest()}")
        cmds += chunked(tgz, "/tmp/ottoq_csms.tgz", "SRC")
        cmds += [DEPLOY.replace("__SRC12__", src12).replace("__RELAY__", RELAY)]
    cid = ssm.send_command(InstanceIds=[iid], DocumentName="AWS-RunShellScript", TimeoutSeconds=600,
                           Comment=f"ottoq-csms {mode}", Parameters={"commands": cmds})["Command"]["CommandId"]
    print(f"command {cid} on {iid}")
    status = "Pending"
    for _ in range(330):
        time.sleep(10)
        try:
            inv = ssm.get_command_invocation(CommandId=cid, InstanceId=iid)
        except ssm.exceptions.InvocationDoesNotExist:
            continue
        status = inv["Status"]
        if status in ("Success", "Failed", "Cancelled", "TimedOut"):
            out = inv.get("StandardOutputContent", "")
            print(out)
            if len(out) >= 23900:
                print("(stdout was cut by SSM at 24,000 characters)")
            err = inv.get("StandardErrorContent", "")
            if err:
                print("--- stderr ---\n" + err)
            break
    print(f"status: {status}")
    return 0 if status == "Success" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
