# storybook-vrt-workflows

@fohte's personal GitHub Actions workflows for Storybook visual regression testing

## Usage

Two reusable workflows:

- `vrt.yml` -- captures Storybook screenshots (sharded per project), compares them against the shared baseline with reg-suit, publishes a report, comments on the PR, and sets the `vrt` commit status. Updates the baseline on pushes to `main`.
- `vrt-approval.yml` -- lets a human override a failing `vrt` status to success via the `vrt-approved` label, and clears the label on the next push.

A consumer repo needs:

- A Storybook project wired up via `@fohte/storybook-addon`'s vitest-plugin (`createStorybookProject`).
- A named npm script that captures screenshots (passed as `capture-script`).
- An R2 bucket already provisioned for screenshots/baseline/report storage.

### `vrt.yml` inputs

| Input             | Required | Default           | Description                                                                                                                              |
| ----------------- | -------- | ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `capture-script`  | yes      | --                | npm script that captures screenshots, invoked as `pnpm run <capture-script> -- --project=<name> --shard=<n>/<total>`.                    |
| `bucket`          | yes      | --                | R2 bucket for screenshots/baseline/report. The report domain is derived as `<bucket>.fohte.net`.                                         |
| `package-dir`     | no       | `.`               | Directory containing the Storybook/vitest project.                                                                                       |
| `install-dir`     | no       | `.`               | Directory to install dependencies from (the workspace root for a pnpm workspace, or the same as `package-dir` for a non-workspace repo). |
| `screenshots-dir` | no       | `__screenshots__` | Directory (relative to `package-dir`) screenshots are written to and read back from.                                                     |
| `projects`        | no       | `["storybook"]`   | JSON array of vitest `--project` names to capture and shard.                                                                             |
| `shards`          | no       | `1`               | Number of shards per project.                                                                                                            |

`vrt-approval.yml` takes only `bucket` (same meaning as above).

### Example caller

```yaml
# .github/workflows/vrt.yml
name: VRT

on:
  pull_request:
  push:
    branches: [main]

jobs:
  vrt:
    permissions:
      contents: read
      pull-requests: write
      statuses: write
    uses: fohte/storybook-vrt-workflows/.github/workflows/vrt.yml@main
    with:
      capture-script: test:storybook
      bucket: example-app-vrt
    secrets:
      AWS_ACCESS_KEY_ID: ${{ secrets.VRT_AWS_ACCESS_KEY_ID }}
      AWS_SECRET_ACCESS_KEY: ${{ secrets.VRT_AWS_SECRET_ACCESS_KEY }}
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
    uses: fohte/storybook-vrt-workflows/.github/workflows/vrt-approval.yml@main
    with:
      bucket: example-app-vrt
```

Pin `@main` to a tag or SHA as appropriate for your repo's update policy.

reg-suit's config lives in this repo (`reg-suit/regconfig.json`) and is not meant to be copied into consumer repos -- `vrt.yml` fetches it directly at the pinned ref.
