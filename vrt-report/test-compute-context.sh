#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_dir=$(mktemp -d)
trap 'rm -r "$test_dir"' EXIT
script="$script_dir/compute-context.sh"
sentinel="$test_dir/injected"

assert_env() {
  local env_file=$1
  local name=$2
  local expected=$3

  if ! grep -Fqx -- "$name=$expected" "$env_file"; then
    printf 'Expected %s=%s in %s\n' "$name" "$expected" "$env_file" >&2
    exit 1
  fi
}

check_case() {
  local name=$1
  local expected_is_main=$2
  local event_name=$3
  local current_ref=$4
  local default_branch=$5
  local report_domain_input=$6
  local expected_branch=$7
  local expected_sha=$8
  local expected_report_domain=$9
  local env_file="$test_dir/$name.env"
  local push_ref_name=${current_ref#refs/heads/}

  if [ "$push_ref_name" = "$current_ref" ]; then
    push_ref_name=${current_ref#refs/tags/}
  fi

  : > "$env_file"
  env \
    GITHUB_ENV="$env_file" \
    EVENT_NAME="$event_name" \
    CURRENT_REF="$current_ref" \
    DEFAULT_BRANCH="$default_branch" \
    REPORT_DOMAIN_INPUT="$report_domain_input" \
    R2_BUCKET=fixture-vrt \
    R2_ENDPOINT=https://objects.example.invalid \
    PR_HEAD_REF=feature/context-fixture \
    PR_HEAD_SHA=2222222222222222222222222222222222222222 \
    PUSH_REF_NAME="$push_ref_name" \
    PUSH_SHA=1111111111111111111111111111111111111111 \
    TEST_SENTINEL="$sentinel" \
    bash "$script"

  assert_env "$env_file" VRT_BRANCH "$expected_branch"
  assert_env "$env_file" VRT_SHA "$expected_sha"
  assert_env "$env_file" VRT_IS_MAIN "$expected_is_main"
  assert_env "$env_file" VRT_BUCKET fixture-vrt
  assert_env "$env_file" VRT_REPORT_DOMAIN "$expected_report_domain"
  assert_env "$env_file" VRT_R2_ENDPOINT https://objects.example.invalid
}

fallback_domain=fixture-vrt.fohte.net
push_sha=1111111111111111111111111111111111111111
pr_sha=2222222222222222222222222222222222222222

check_case main-push true push refs/heads/main main '' main "$push_sha" "$fallback_domain"
check_case master-push true push refs/heads/master master '' master "$push_sha" "$fallback_domain"
check_case non-default-branch false push refs/heads/main master '' main "$push_sha" "$fallback_domain"
check_case feature-branch false push refs/heads/feature/context-fixture main '' feature/context-fixture "$push_sha" "$fallback_domain"
check_case pull-request false pull_request refs/pull/42/merge main '' feature/context-fixture "$pr_sha" "$fallback_domain"
check_case default-named-tag false push refs/tags/master master '' master "$push_sha" "$fallback_domain"
check_case missing-default-branch false push refs/heads/main '' '' main "$push_sha" "$fallback_domain"
check_case workflow-dispatch true workflow_dispatch refs/heads/main main '' main "$push_sha" "$fallback_domain"
check_case report-domain-override true push refs/heads/main main reports.example.invalid main "$push_sha" reports.example.invalid

malicious_default_branch="main\"; touch \"\$TEST_SENTINEL\"; #"
check_case untrusted-default-branch false push refs/heads/main "$malicious_default_branch" '' main "$push_sha" "$fallback_domain"
if [ -e "$sentinel" ]; then
  printf 'Default branch value was executed as shell code\n' >&2
  exit 1
fi

printf 'VRT context cases passed\n'
