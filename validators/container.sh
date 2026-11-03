#!/usr/bin/env bash
# container.sh <dir with Dockerfile>
# `docker build` the job image, then run it the way Cloud Run runs a job task:
#   docker run -e CLOUD_RUN_TASK_INDEX=0 -e CLOUD_RUN_TASK_COUNT=1 <image> --version
# Cloud Run sets CLOUD_RUN_TASK_INDEX (0..count-1) and CLOUD_RUN_TASK_COUNT on each task
# (docs.cloud.google.com/run/docs/create-jobs; marked [unverified] in docs/BUILD_PROMPT.md until
# that page is fetched; culvert#287 pins it). `--version` is the smallest argument a dbt
# entrypoint accepts, so a green run proves the image builds, starts and has dbt on it.
# Tier: offline, needs a Docker daemon. Without one: not_run, never pass.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

dir="${1:-}"
[ -n "$dir" ] || result fail "usage: container.sh <dir with Dockerfile>"
need_dir "$dir" "container dir"
[ -f "$dir/Dockerfile" ] || result fail "container dir: no Dockerfile in $dir"

DOCKER="${SLUICE_DOCKER_BIN:-docker}"
need_cmd "$DOCKER" "docker (build and run the job image)"
"$DOCKER" info >/dev/null 2>&1 || result not_run "docker daemon is not reachable (is Docker running?)"

tag="sluice-check-$(date +%s)-$RANDOM"
cleanup() { "$DOCKER" image rm -f "$tag" >/dev/null 2>&1 || true; }
trap cleanup EXIT

if ! run_logged "$DOCKER" build --quiet --tag "$tag" "$dir"; then
  result fail "docker build failed for $dir (see above)"
fi
if run_logged "$DOCKER" run --rm -e CLOUD_RUN_TASK_INDEX=0 -e CLOUD_RUN_TASK_COUNT=1 "$tag" --version; then
  result pass "image builds and runs as a Cloud Run task: $dir"
else
  result fail "image built but did not run with the Cloud Run task env (see above): $dir"
fi
