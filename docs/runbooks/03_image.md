# Runbook: Image

Why the image is built this way: [../03_image.md](../03_image.md).

## Build and test locally

```bash
make lint-image  # needs shellcheck, shfmt, hadolint, yamllint and actionlint on PATH
make smoke       # builds claudetainer:dev for the local architecture, then runs test/smoke.sh
```

Expected: every smoke line starts with `ok`. A `FAIL` line names the tool, the pinned version and what it
printed.

## Add a tool

1. Add an `ARG` at the top of the `Dockerfile`, with a `# renovate: datasource=... depName=...` line above it.
   Without that line Renovate never updates it.
2. Redeclare the `ARG` above the `RUN` that installs it, and install it for both `amd64` and `arm64`.
3. Add a probe and an `expect` line to `test/smoke.sh`.
4. `make smoke`, then open a PR. CI builds and smoke-tests both architectures.

A tool that only installs with apt goes into the apt `RUN`. Sessions cannot install it themselves: there is no
sudo in the pod.

## Update a pin by hand

Change the `ARG` value, `make smoke`, open a PR. The merge releases and deploys, which restarts the pod.

## Roll back

Revert the deploy PR in the GitOps repo, see [05_deployment.md](05_deployment.md). Then revert or fix the change
here, so the next release does not bring it back.
