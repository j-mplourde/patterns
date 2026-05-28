#!/usr/bin/env bash
# Container entrypoint shim. Reads the host-mounted /app/deployment-info file
# (written by Ansible) and emits a one-line JSON record so CloudWatch logs
# always contain "what's running now" for every container at startup.
#
# After logging, exec's the real command via $@ - so this script is transparent
# in `docker compose` definitions: just set entrypoint to this script and put
# the real command in `command:`.
set -euo pipefail

if [ -f /app/deployment-info ]; then
  # shellcheck disable=SC1091
  . /app/deployment-info
fi

printf '{"event":"container_start","environment":"%s","tag":"%s","deployed_at":"%s","previous_tag":"%s"}\n' \
  "${CURRENT_ENVIRONMENT:-unknown}" \
  "${CURRENT_TAG:-unknown}" \
  "${CURRENT_DEPLOYMENT_DATE:-unknown}" \
  "${PREVIOUS_TAG:-N/A}"

exec "$@"
