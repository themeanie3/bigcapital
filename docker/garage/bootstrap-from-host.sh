#!/usr/bin/env bash
#
# Bootstrap Garage from the Docker HOST (Dokploy server terminal / SSH).
#
# The dxflrs/garage image is distroless: it has no shell, so `setup.sh`
# cannot run inside the container ("exec: sh: executable file not found").
# This script runs the same steps by calling the `garage` binary through
# `docker exec` one command at a time.
#
# Usage:
#   bash docker/garage/bootstrap-from-host.sh [container-name-or-id]
# The container defaults to the first running container whose name contains
# "garage". Idempotent: safe to re-run.

set -euo pipefail

CONTAINER="${1:-$(docker ps --filter name=garage --format '{{.Names}}' | head -n1)}"
if [ -z "${CONTAINER}" ]; then
  echo "ERROR: no running garage container found. Pass its name as the first argument." >&2
  exit 1
fi

GARAGE_LOCAL_ZONE="${GARAGE_LOCAL_ZONE:-dc1}"
GARAGE_CAPACITY="${GARAGE_CAPACITY:-10G}"
S3_BUCKET="${S3_BUCKET:-bigcapital}"

g() { docker exec "${CONTAINER}" /garage "$@"; }

echo "==> Using container ${CONTAINER}"
for _ in $(seq 1 30); do
  g status >/dev/null 2>&1 && break
  sleep 2
done
g status >/dev/null 2>&1 || { echo "ERROR: Garage not reachable in ${CONTAINER}." >&2; exit 1; }

if g status | grep -q "Healthy"; then
  echo "==> Layout already healthy, skipping."
else
  NODE_ID=$(g node id 2>/dev/null | awk 'NR==1{print $1}')
  echo "==> Assigning layout (node ${NODE_ID}, zone ${GARAGE_LOCAL_ZONE}, capacity ${GARAGE_CAPACITY})"
  g layout assign "${NODE_ID}" -z "${GARAGE_LOCAL_ZONE}" -c "${GARAGE_CAPACITY}" >/dev/null 2>&1 || true
  g layout apply --version 1 >/dev/null 2>&1 || g layout apply >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    g status | grep -q "Healthy" && break
    sleep 2
  done
  g status | grep -q "Healthy" || { echo "ERROR: cluster not healthy; run: docker exec ${CONTAINER} /garage status" >&2; exit 1; }
fi

if g key list | grep -qw bigcapital; then
  echo "==> Key 'bigcapital' exists, reusing."
  KEY_ID=$(g key info bigcapital | awk '/Key ID/{print $NF}' | head -n1)
  SECRET_KEY=""
else
  OUT=$(g key create --name bigcapital)
  KEY_ID=$(echo "${OUT}" | awk '/Key ID/{print $NF}' | head -n1)
  SECRET_KEY=$(echo "${OUT}" | awk '/Secret key/{print $NF}' | head -n1)
fi

g bucket list | grep -qw "${S3_BUCKET}" || g bucket create "${S3_BUCKET}"
g bucket allow --read --write --owner --key bigcapital --bucket "${S3_BUCKET}" >/dev/null

echo ""
echo "================================================================"
echo " Garage is ready. Set these in the Dokploy Environment tab and redeploy:"
echo "================================================================"
echo "S3_ACCESS_KEY_ID=${KEY_ID}"
if [ -n "${SECRET_KEY}" ]; then
  echo "S3_SECRET_ACCESS_KEY=${SECRET_KEY}"
else
  echo "S3_SECRET_ACCESS_KEY= (already created earlier; the secret is only shown once)"
  echo "  If you lost it: docker exec ${CONTAINER} /garage key delete --yes bigcapital  then re-run this script."
fi
