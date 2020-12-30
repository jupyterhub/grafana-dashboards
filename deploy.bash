#!/usr/bin/env bash
set -euo pipefail

GRAFANA_URL="${1}"
DASHBOARD_FILE="${2}"
GRAFANA_TOKEN="${GRAFANA_TOKEN}"


PAYLOAD="{\"dashboard\": "$(jsonnet -J vendor ${DASHBOARD_FILE})", \"overwrite\": true}"

curl \
    -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "${PAYLOAD}" \
    "${GRAFANA_URL}/api/dashboards/db"
