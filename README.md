# storybook-vrt-workflows

@fohte's personal GitHub Actions workflows for Storybook visual regression testing

## Usage

Two composite actions and one reusable workflow:

- `vrt-capture` -- captures one shard's Storybook screenshots and uploads them as an artifact. Call once per (project, shard) combination from your own matrix job.
- `vrt-report` -- downloads every shard's screenshots, compares them against the shared baseline with reg-suit, publishes a report, comments on the PR, and sets the `vrt` commit status. Updates the baseline on pushes to `main`.
- `vrt-approval.yml` (reusable workflow) -- lets a human override a failing `vrt` status to success via the `vrt-approved` label, and clears the label on the next push.

Both `vrt-capture` and `vrt-report` are composite actions, not reusable workflows: installing the caller's own toolchain and dependencies is a property of the caller's repo, not something this repo can standardize on. The caller's own job does its own checkout and setup, then calls these actions as steps interleaved with that setup.

A consumer repo needs:

- A Storybook project wired up via `@fohte/storybook-addon`'s vitest-plugin (`createStorybookProject`).
- A named npm script that captures screenshots (passed as `capture-script`).
- An R2 bucket already provisioned for screenshots/baseline/report storage.

### Example caller

```yaml
# .github/workflows/vrt.yml
name: VRT

on:
  pull_request:
  push:
    branches: [main]

env:
  SHARDS: 2

jobs:
  setup:
    runs-on: ubuntu-latest
    outputs:
      shards: ${{ steps.shards.outputs.json }}
    steps:
      - name: Enumerate shard indices
        id: shards
        run: echo "json=$(jq -nc --argjson n "$SHARDS" '[range(1; $n + 1)]')" >> "$GITHUB_OUTPUT"

  # vitest's shard sequencer sorts specs by sha1(file path) and slices ranges
  # off that order -- it never looks at which `--project` a spec belongs to.
  # Running multiple projects in one `vitest` invocation means every story
  # file produces one spec per project with the *same* path and thus the same
  # hash, so ties between them settle in collection order, which isn't stable
  # across shards. A tied pair straddling a shard boundary gets duplicated
  # into one shard and dropped from another. One project per job keeps every
  # hash in a run unique, so the sort -- and the shard split -- is
  # deterministic.
  capture:
    needs: setup
    strategy:
      fail-fast: false
      matrix:
        project: [storybook]
        shard: ${{ fromJSON(needs.setup.outputs.shards) }}
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - run: mise install && corepack enable && pnpm install --frozen-lockfile
      - uses: fohte/storybook-vrt-workflows/vrt-capture@1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b # v0.1.0
        with:
          project: ${{ matrix.project }}
          shard: ${{ matrix.shard }}
          shards: ${{ env.SHARDS }}
          capture-script: test:storybook

  report:
    needs: capture
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      statuses: write
    # Overlapping runs for the same ref would otherwise race to publish to the
    # same R2 key at once -- most importantly two main pushes racing to
    # update the single `baseline/actual/` key, where each run's diff was
    # computed against a baseline the other run is concurrently mutating.
    concurrency:
      group: vrt-report-${{ (github.ref == 'refs/heads/main') && 'push' || 'pr' }}-${{ github.event_name == 'pull_request' && github.event.pull_request.head.ref || github.ref_name }}
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - run: mise install && corepack enable && pnpm install --frozen-lockfile
      - uses: fohte/storybook-vrt-workflows/vrt-report@1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b # v0.1.0
        with:
          r2-bucket: example-app-vrt
          github-token: ${{ secrets.GITHUB_TOKEN }}
          aws-access-key-id: ${{ secrets.VRT_AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.VRT_AWS_SECRET_ACCESS_KEY }}
```

```yaml
# .github/workflows/vrt-approval.yml
name: VRT approval

on:
  pull_request:
    types: [synchronize, labeled]

jobs:
  vrt-approval:
    permissions:
      contents: read
      pull-requests: write
      statuses: write
    uses: fohte/storybook-vrt-workflows/.github/workflows/vrt-approval.yml@1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b # v0.1.0
    with:
      r2-bucket: example-app-vrt
```

reg-suit's config lives in this repo (`reg-suit/regconfig.json`) and is not meant to be copied into consumer repos -- `vrt-report` fetches it directly at the pinned ref.

`core.thresholdPixel` is an absolute per-image diff-pixel count applied uniformly to every screenshot in every consumer repo, not scaled by image or element size. A genuine regression confined to a region at or under this pixel count (e.g. a small icon or a thin border) will not be flagged.

### `vrt-capture` inputs

| Input             | Required | Default           | Description                                                                                                        |
| ----------------- | -------- | ----------------- | ------------------------------------------------------------------------------------------------------------------ |
| `project`         | yes      | --                | vitest `--project` name to capture.                                                                                |
| `shard`           | yes      | --                | 1-based shard index for this job.                                                                                  |
| `shards`          | yes      | --                | Total number of shards `shard` is drawn from.                                                                      |
| `capture-script`  | yes      | --                | npm script that captures screenshots, invoked as `pnpm run <capture-script> --project=<name> --shard=<n>/<total>`. |
| `package-dir`     | no       | `.`               | Directory containing the Storybook/vitest project.                                                                 |
| `screenshots-dir` | no       | `__screenshots__` | Directory (relative to `package-dir`) screenshots are written to.                                                  |

### Triaging duplicate screenshot failures

`vrt-capture`'s "Check for duplicate screenshots" step fails when two stories in the same directory render byte-identical screenshots. The correct fix depends on whether the duplicated stories have a `play` function:

- **Both stories have `play`** (behavior tests): landing on the same screen state is expected, so add `parameters: { screenshot: { skip: true } }` (the skip flag `@fohte/storybook-addon`'s screenshot plugin reads) to skip the screenshot.
- **Only one has `play`**: skip only that story.
- **Neither has `play`** (both stories assert on appearance): don't skip. An identical screenshot means the component or the story has a bug -- find it and fix it.

This isn't purely "has `play` -> skippable": a story that asserts on the visual result reached via a `play` interaction still needs its own screenshot even though it has `play`. The question is where the story's assertion actually lives -- in `play`'s `expect` calls, or in the rendered appearance.

### `vrt-report` inputs

| Input                   | Required | Default                           | Description                                                                                                                       |
| ----------------------- | -------- | --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `package-dir`           | no       | `.`                               | Directory containing the Storybook/vitest project.                                                                                |
| `screenshots-dir`       | no       | `__screenshots__`                 | Directory (relative to `package-dir`) every shard's screenshots are downloaded into.                                              |
| `r2-bucket`             | yes      | --                                | R2 bucket for screenshots/baseline/report.                                                                                        |
| `r2-endpoint`           | no       | fohte's shared Cloudflare account | S3-compatible endpoint URL that hosts `r2-bucket`. Override for a consumer using its own account.                                 |
| `report-domain`         | no       | `<r2-bucket>.fohte.net`           | Custom domain the published report and PR comment link are served from. Override for a consumer not using fohte's shared account. |
| `aws-access-key-id`     | yes      | --                                | AWS-compatible access key ID for `r2-bucket`.                                                                                     |
| `aws-secret-access-key` | yes      | --                                | AWS-compatible secret access key for `r2-bucket`.                                                                                 |
| `github-token`          | yes      | --                                | Token used for PR comments and commit statuses (needs `pull-requests:write`, `statuses:write`).                                   |

`vrt-approval.yml` takes only `r2-bucket` and `report-domain` (same meaning as above) -- pass the same `report-domain` value given to `vrt-report`, if any.
