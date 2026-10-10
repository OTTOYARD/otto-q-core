# OTTO-Q's charger back end and the twin's live bridge, one process (csms/csms_service.py). Built and run on the AWS box by
# csms/deploy/deploy_ssm.sh with --cpus and --memory limits, beside the intelligence service and never inside it.
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
# the two libraries the back end and the bridge speak through, pinned as in requirements.txt
RUN pip install --no-cache-dir ocpp==2.1.0 websockets==15.0.1
COPY csms_server.py station_sim.py charger_bridge.py csms_relay.py csms_service.py /app/csms/
USER 65534:65534
ENTRYPOINT ["python3", "/app/csms/csms_service.py"]
