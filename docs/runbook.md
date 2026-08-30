# Runbook

One entry per failure mode, added by the slice that introduces it. Format:
**symptom → likely cause → check → fix**.

---

## Slice 0

### `scripts/validate.sh` fails on a file you think is valid

- **Likely cause:** the file's `apiVersion`/`kind` has no pinned schema under
  `schemas/`, or kubeconform's schema-location order is wrong.
- **Check:** `scripts/validate.sh -v` (verbose) prints which schema it resolved
  per file. `ls schemas/` for the CRD in question.
- **Fix:** add the pinned CRD schema to `schemas/` (record its source + version in
  `docs/bootstrap-toolchain.md`), or if the file genuinely isn't a Kubernetes
  manifest, add it to the validator's skip list.

### `scripts/gen-digests.sh` produces a diff on a clean tree

- **Likely cause:** someone hand-edited `digests.env` or `params.yaml` instead of
  `digests.cue`; or the `cue` binary version drifted.
- **Check:** `cue version` matches the pin in `docs/bootstrap-toolchain.md`.
  `git diff digests.env params.yaml`.
- **Fix:** edit `digests.cue`, re-run `scripts/gen-digests.sh`, commit all three.
  The generated files are outputs — never edit them directly.

### Pre-commit hook blocks a commit

- **Likely cause:** shellcheck finding, a failing bats test, or `validate.sh`.
- **Check:** the hook prints which step failed. Re-run it manually:
  `.githooks/pre-commit`.
- **Fix:** address the finding. `git commit --no-verify` only for a genuine
  emergency, and fix it in the next commit.

### `cue vet digests.cue` fails with a constraint error

- **Likely cause:** a digest value is not `sha256:` + 64 hex chars (a tag slipped
  in, or a truncated digest).
- **Check:** the error names the field.
- **Fix:** put the full `sha256:...` digest in. Get it with
  `crane digest <ref>` (Slice 1+) or from the source registry's UI.
