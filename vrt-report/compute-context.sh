#!/usr/bin/env bash
set -euo pipefail

if [ "$EVENT_NAME" = "pull_request" ]; then
  branch="$PR_HEAD_REF"
  sha="$PR_HEAD_SHA"
else
  branch="$PUSH_REF_NAME"
  sha="$PUSH_SHA"
fi

if [ -n "${DEFAULT_BRANCH:-}" ] && [ "$CURRENT_REF" = "refs/heads/$DEFAULT_BRANCH" ]; then
  is_main=true
else
  is_main=false
fi

# Falls back to <r2-bucket>.fohte.net -- the convention for buckets on fohte's
# shared Cloudflare account -- when report-domain isn't set.
report_domain="${REPORT_DOMAIN_INPUT:-${R2_BUCKET}.fohte.net}"
{
  printf 'VRT_BRANCH=%s\n' "$branch"
  printf 'VRT_SHA=%s\n' "$sha"
  printf 'VRT_IS_MAIN=%s\n' "$is_main"
  printf 'VRT_BUCKET=%s\n' "$R2_BUCKET"
  printf 'VRT_REPORT_DOMAIN=%s\n' "$report_domain"
  printf 'VRT_R2_ENDPOINT=%s\n' "$R2_ENDPOINT"
} >> "$GITHUB_ENV"
