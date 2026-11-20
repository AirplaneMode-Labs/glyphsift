# Releasing glyphsift 0.1.3: the owner's steps

Nothing in this repository publishes by itself, and nobody on the team will run a publish, tag a commit, reserve a name, create a key or change a GitHub
setting. This page lists, in order, what is left for the owner and nothing the team could have done itself. The team's side is finished and checked:

- **The artefacts build as a release builds them** (`scripts/release/build-artefacts.sh`): the npm tarball `@airplanemode/glyphsift`, a wheel for each of three platforms, the source package
  and the two packaged crates `glyphsift-core` and `glyphsift-cli`.
- **The CI job `release-rehearsal (<os>)`** (Linux, macOS, Windows; [release.md](release.md), "Sprint 7: what only CI can prove") installs each built file into a fresh place and
  makes one real call, then signs a `glyphsift-rehearsal` manifest with the published RFC 8032 test key, verifies it with the explicit flag, and shows the refusals. It is a
  rehearsal: the test key can never sign a `-release` id and is refused everywhere else.
- **`.github/workflows/publish.yml`** exists and cannot fire by accident: `workflow_dispatch` only, main of this repository only, six locks, three bindings, provenance, then publishing from the exact
  files the verified manifest lists. Its checks are in `scripts/release/publish-guard.sh` and each refusal is tested (`tests/scripts/publish-guard.sh`). No one has run it.
- **`docs/release-keys.json`** is committed with no key in it, so today nothing verifies: a release signature cannot pass until you add your public key (step 4).

The release is `0.1.3` (`v0.1.3`). 0.1.0, 0.1.1 and 0.1.2 were never tagged and are superseded. Do not tag while a row of [release.md](release.md) that is yours is still open, and do not
say anything in a write-up that the rows do not support.

## Owner-only steps, in order

Run the commands from a checkout of `AirplaneMode-Labs/glyphsift` on the commit you intend to release unless a step says otherwise. Replace `<...>` with your own value; none of those values is written in this
repository, and no secret ever goes on a command line or into a file you commit.

### 1. Measure the 8 GB laptop figure

Follow "Owner must", row 2, in [release.md](release.md) on the 8 GB Windows laptop with no GPU. Commit the raw files first (the commands write them with their date, commit and machine; [benchmarks/README.md](benchmarks/README.md) says how to list them), then put the figures from those files in the README Benchmarks table in the "8 GB Windows no-GPU laptop" column.

```sh
node scripts/throughput.mjs corpus-1mib.txt --cli target/release/glyphsift --json docs/benchmarks/throughput-8gb.json
```

Why only you: the machine is yours. Every cell for that laptop reads "not measured on 8 GB" until you fill it, and no figure measured on another machine may stand in for it.

### 2. Check that the names are free, and reserve them

The names are placeholders until you reserve them: npm scope `@airplanemode` (package `@airplanemode/glyphsift`), PyPI `glyphsift`, crates.io `glyphsift-core` and `glyphsift-cli` (reservation was due on 22 Nov 2026).
Create the npm organisation `airplanemode` on npmjs.com. A PyPI project and a crates.io crate exist only once something is uploaded, so a name is held by the first release itself (a pending publisher on PyPI, step 7, does not hold
it); check that nobody took them first.

```sh
npm view @airplanemode/glyphsift version
pip index versions glyphsift
cargo search glyphsift-core --limit 1
```

If a name is taken, stop and tell the team: a different name is a new decision, not an edit.

Why only you: registry accounts, organisation ownership and any legal or money step are yours; the team has no registry account and creates none.

### 3. Create the real signing key, offline

On the offline key machine, with `cp-sign` from the private `AirplaneMode-Labs/control-plane` repository. The secret never leaves that machine, never goes into any repository, workflow or secret store, and is never used with a test-key flag.

```sh
git clone https://github.com/AirplaneMode-Labs/control-plane && cd control-plane
cargo run -p cp-sign -- keygen --out ./keys
cargo run -p cp-sign -- keyid --pub ./keys/key.pub
```

Print the public key as the canonical padded base64 of its 32 raw bytes, the form step 4 needs (this reads only `key.pub`, never the secret):

```sh keypub-b64
node -e 'const l=require("fs").readFileSync(process.argv[1],"utf8").split(/\r?\n/).find(s=>s.startsWith("ed25519-public "));const b=l&&Buffer.from(l.split(/\s+/)[1],"hex");if(!b||b.length!==32){console.error("not a cp-sign public key file");process.exit(1)}console.log(b.toString("base64"))' ./keys/key.pub
```

Record the key id (64 lower-case hex characters) and the public key. The release key signs only `-release` manifests and is separate from any key that signs models or data (R4, S1-127).

Why only you: no agent handles a real key, and custody (where the secret lives, who can reach it, how you would revoke it) is your decision.

### 4. Commit the public key

Put exactly one key in `docs/release-keys.json` (the file is committed empty today). The format is fixed: the spec string, then the list, each key with `keyId` and `publicKey` (canonical padded base64 of the 32 raw bytes).

```sh
cat > docs/release-keys.json <<'JSON'
{"spec":"airplanemode.release-keys/0.1","keys":[{"keyId":"<64 hex from step 3>","publicKey":"<base64 public key from step 3>"}]}
JSON
```

Do not add the RFC 8032 test key: the verifier refuses it. Commit and push this change on its own. Consider a `CODEOWNERS` entry that makes you the only reviewer of `docs/release-keys.json`, `scripts/release/release-tool.mjs` and `.github/workflows/publish.yml`.

Why only you: which key may sign a release is the one trust decision in this process; the workflow trusts only what is committed here.

### 5. Create the `release` environment

The publish job runs in the `release` environment. You are its required reviewer, deployments are limited to `main`, and administrators cannot bypass it. `prevent_self_review` stays `false` because you are the only reviewer.

```sh
OWNER_ID=$(gh api users/<your-github-login> --jq .id)
gh api -X PUT repos/AirplaneMode-Labs/glyphsift/environments/release --input - <<JSON
{"wait_timer":0,"prevent_self_review":false,"reviewers":[{"type":"User","id":$OWNER_ID}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true},"can_admins_bypass":false}
JSON
gh api -X POST repos/AirplaneMode-Labs/glyphsift/environments/release/deployment-branch-policies -f name=main -f type=branch
gh api repos/AirplaneMode-Labs/glyphsift/environments/release --jq '{can_admins_bypass, branch_policy: .deployment_branch_policy, reviewers: [.protection_rules[]? | .reviewers[]? | .reviewer.login]}'
```

Why only you: repository and environment settings belong to the repository owner; the team never changes them.

### 6. Tell the environment which key signs releases

`RELEASE_KEY_ID` is a variable of the `release` environment (not a secret; set it with `--env release`, never as a repository variable). It is read only in a step of the publish job, never in a job-level condition, and that step compares it with the single key in `docs/release-keys.json` at the commit it publishes and refuses if they differ.

```sh
gh variable set RELEASE_KEY_ID --env release --repo AirplaneMode-Labs/glyphsift --body "<64 hex from step 3>"
```

Why only you: it names your key.

### 7. Add the PyPI pending publisher

PyPI publishes through trusted publishing (OpenID Connect), so there is no PyPI token anywhere. On pypi.org, Account settings, Publishing, "Add a new pending publisher", fill in exactly:

- Project name: `glyphsift`
- Owner: `AirplaneMode-Labs`
- Repository name: `glyphsift`
- Workflow name: `publish.yml`
- Environment name: `release`

```sh
gh api repos/AirplaneMode-Labs/glyphsift/environments/release --jq .name
```

Why only you: it is your PyPI account, and the first upload through it creates the project under your name.

### 8. Create the registry tokens as secrets of the environment only

npm and crates.io publish with short-lived tokens that exist only as secrets of the `release` environment (never repository or organisation secrets). Create each token on the registry's own page, with the shortest lifetime that covers the release: 7 days or less
(npm's trusted publishing needs npm 11.5.1 or later, which Node 22 does not bundle, so the first publish uses a token; moving to trusted publishing is decided afterwards, TD-122).

- npm: a granular access token, read and write, limited to the `@airplanemode` scope, expiry 7 days. Tick "bypass two-factor authentication" only if your account requires a second factor for writes, since CI cannot answer a prompt.
- crates.io: an API token with the scopes `publish-new` and `publish-update`, limited to the crate names `glyphsift-core` and `glyphsift-cli`, expiry 7 days.

```sh
gh secret set NPM_TOKEN --env release --repo AirplaneMode-Labs/glyphsift
gh secret set CARGO_REGISTRY_TOKEN --env release --repo AirplaneMode-Labs/glyphsift
```

Each command asks for the value on standard input.

Why only you: only you can create tokens on your registry accounts, and a token is a credential the team must never see.

### 9. Date the release, read CI, tag

Give the `0.1.3` entry of `CHANGELOG.md` its date in place of `untagged` (`## [0.1.3] - YYYY-MM-DD`), commit that alone, push, and read CI on the pushed commit: every job green on Linux, macOS and Windows, the three `release-rehearsal` jobs included. Then tag
that exact commit with a signed annotated tag and push the tag.

```sh
git switch main && git pull --ff-only
git commit -am "release: 0.1.3"
git push origin main
gh run list --repo AirplaneMode-Labs/glyphsift --branch main --limit 3
gh run view <ci-run-id> --repo AirplaneMode-Labs/glyphsift --json jobs --jq '.jobs[] | [.name, .conclusion] | @tsv'
git tag -s v0.1.3 -m "glyphsift 0.1.3"
git push origin v0.1.3
```

Consider a tag ruleset for `v*` that only you can create, update or delete, branch protection on `main`, and secret-scanning push protection.

Why only you: commits, tags and pushes are yours; nobody on the team pushes or tags, and CI is read, not rerun, by them.

### 10. Dispatch the publish workflow (it builds, then waits)

Dispatch from `main`, which must still be the tagged commit. The build jobs run on all three operating systems and upload the candidate files for one day; the publish job then waits for your approval and runs nothing until you give it and until step 14 arms it.

```sh
gh workflow run publish.yml --repo AirplaneMode-Labs/glyphsift --ref main
gh run list --repo AirplaneMode-Labs/glyphsift --workflow publish.yml --limit 1
```

Why only you: the team never runs `publish.yml`, and the workflow itself refuses to start from anywhere but `main` of this repository.

### 11. Check the candidate before you sign it

The candidate files are what you will sign, so check where they came from first. The run must be this dispatch of `publish.yml` on the tagged commit, and the files must be the ones the build jobs printed.

```sh
RUN=<publish run id from step 10>
gh run view $RUN --repo AirplaneMode-Labs/glyphsift --json headSha,headBranch,event,workflowName,status --jq .
test "$(git rev-parse 'v0.1.3^{commit}')" = "<the headSha printed above>" && echo "tag commit equals the run's commit"
mkdir -p candidate cand && gh run download $RUN --repo AirplaneMode-Labs/glyphsift --dir candidate --pattern 'glyphsift-candidate-*'
cp candidate/*/* cand/ && ls cand && shasum -a 256 cand/*
```

`headBranch` must be `main`, `event` must be `workflow_dispatch`, `workflowName` must be `publish`, and `ls cand` must show exactly seven files: `airplanemode-glyphsift-0.1.3.tgz`, `glyphsift-0.1.3.tar.gz`, `glyphsift-core-0.1.3.crate`, `glyphsift-cli-0.1.3.crate` and one wheel each for manylinux x86_64,
macOS arm64 and `win_amd64`. Compare each digest with the line of the same name in the build jobs' log step "Print the candidate digests" (`gh run view $RUN --repo AirplaneMode-Labs/glyphsift --log`). If anything differs, stop: do not sign.

That comparison only shows that the files are the ones this run built. Before you sign, also compare the npm tarball, the sdist and the two crates with an independent build of the same commit (S1-135), so that a compromised publish run cannot hand you bytes that nothing else reproduces. Use one of these:

- the artefact `REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-ubuntu-latest-<sha>` of the `ci` run that CI made when the tagged commit was pushed (the tarball, the sdist and the crates are built on the Linux leg; the artefact is kept for 3 days, so if it has expired, re-run that `ci` run first); or
- a local run of `scripts/release/rehearse.sh` at that commit, with the same pinned tools as CI (`scripts/install-wasm-tools.sh` for wasm-bindgen and wasm-opt, and maturin from `tools/ci/requirements.txt`): it builds the tarball and the crates, and the sdist only on Linux.

```sh
gh run list --repo AirplaneMode-Labs/glyphsift --workflow ci --commit "$(git rev-parse 'v0.1.3^{commit}')" --json databaseId,conclusion,headSha
gh run download <ci-run-id> --repo AirplaneMode-Labs/glyphsift --dir rehearsal --pattern 'REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-ubuntu-latest-*'
shasum -a 256 rehearsal/*/dist-release/airplanemode-glyphsift-0.1.3.tgz rehearsal/*/dist-release/glyphsift-0.1.3.tar.gz rehearsal/*/dist-release/glyphsift-core-0.1.3.crate rehearsal/*/dist-release/glyphsift-cli-0.1.3.crate
shasum -a 256 cand/airplanemode-glyphsift-0.1.3.tgz cand/glyphsift-0.1.3.tar.gz cand/glyphsift-core-0.1.3.crate cand/glyphsift-cli-0.1.3.crate
```

The four digests of the independent build must equal the four of `cand`, file for file. A wheel's bytes depend on the build machine and the checkout path (README, Packaging notes), so wheels compare only between the two CI builds: each wheel in `cand` against the wheel of the same operating system in that push run's `REHEARSAL-test-key-NOT-A-RELEASE-glyphsift-<os>-<sha>` artefact. Do not sign a tarball, sdist or crate that differs, and do not sign a wheel whose difference you cannot explain.

Why only you: you are signing these bytes with a key only you hold, so you must be the one who checks they are the right bytes.

### 12. Sign the manifest on the offline key machine

Make the unsigned manifest of exactly those files with the vendored release tool, sign it with `cp-sign` and your real key with no expiry (a release manifest carries no `expiresAt`, TD-121), and check the result with the same tool and the committed key file. Never pass a test-key flag here.

```sh
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct v0.1.3) node scripts/release/release-tool.mjs manifest --dir cand --id glyphsift-release --version 0.1.3 --licence Apache-2.0 --publisher release
cargo run -p cp-sign -- sign --key ./keys/key.secret --no-expiry cand/release-manifest.json --out release-manifest.json
cp release-manifest.json cand/release-manifest.json
node scripts/release/release-tool.mjs sums --dir cand
node scripts/release/release-tool.mjs verify --dir cand --expect-id glyphsift-release --trust-file docs/release-keys.json
```

The last command must exit 0 and print `"verdict":"ok"` with `"testKey":false`. (Run `cp-sign` from your `control-plane` checkout and give it the absolute paths; the release tool from this checkout.)

Why only you: the real key never leaves the offline machine and no agent handles it.

### 13. Attach the signed manifest to a GitHub release

The publish job downloads `release-manifest.json` from the published GitHub release of tag `v0.1.3`; a draft release is not visible to it. The file must be named exactly `release-manifest.json`.

```sh
gh release create v0.1.3 --repo AirplaneMode-Labs/glyphsift --verify-tag --title "glyphsift 0.1.3" --notes-file release-notes.md release-manifest.json
```

Write `release-notes.md` from [CHANGELOG.md](../CHANGELOG.md) and the README Limitations, and say plainly what the release does not claim (below).

Why only you: creating a GitHub release is publishing; the team creates none.

### 14. Arm, approve, watch

Arm the release just before you approve the waiting deployment, and watch the publish job. The first step after the checkout refuses to go on unless `RELEASE_PUBLISH_ARMED` is `true` (a variable of the `release` environment, read only in a step of the publish job). The job then verifies the manifest against `docs/release-keys.json`, checks the three bindings,
attests the exact files, and publishes: npm first, then the crates, then PyPI (with attestations). The crates are packaged and published with `--no-verify`, so nothing is compiled in the job that holds the registry tokens (S1-131): one step re-packages them and compares their digests with your signed manifest, the very next step publishes them, and a last step reads
crates.io's sparse index until it shows both crates with the signed checksums (it asks again for up to 10 minutes, then fails loudly; do not publish again, look at the crates by hand).

```sh
gh variable set RELEASE_PUBLISH_ARMED --env release --repo AirplaneMode-Labs/glyphsift --body true
# Actions > the publish run > "Review deployments" > release > "Approve and deploy"
gh run watch $RUN --repo AirplaneMode-Labs/glyphsift
```

If the job refuses, it says why on its first failing step (a lock, a binding, the verification, the exact file set, the crate digests, the index check). Do not edit the workflow to get past a refusal; fix the cause and dispatch again.
If the two `cargo package --workspace --locked` runs ever give different bytes, or the bytes packaged with `--no-verify` differ from the verified ones (the rehearsal fails with "S1-126" or "S1-131"), the crates leave the signed set: they are then published from source at the tagged commit (`glyphsift-core`, then `glyphsift-cli`)
and this page and [release.md](release.md) say so before you release.

Why only you: the approval is the lock that makes you the only person who can publish, and the variable is the second.

### 15. Disarm, delete the secrets, revoke the tokens

As soon as the publish job ends, whether it succeeded or not:

```sh
gh variable delete RELEASE_PUBLISH_ARMED --env release --repo AirplaneMode-Labs/glyphsift
gh secret delete NPM_TOKEN --env release --repo AirplaneMode-Labs/glyphsift
gh secret delete CARGO_REGISTRY_TOKEN --env release --repo AirplaneMode-Labs/glyphsift
```

Then revoke both tokens on npmjs.com and crates.io (a 7-day token is a limit, not a reason to leave it alive), and check the registries list the new version.

Why only you: they are your credentials on your accounts.

### 16. Install from a clean machine, update the README, write it up

On a machine that has never seen this repository, with Wi-Fi on, run the registry commands and record the output. Then move the README Install section's "After the owner publishes" commands into the main text, mark the rows of [release.md](release.md)
that are now Done with the recorded output, finish the write-up from `docs/writeup-0.1.3-draft.md` (it waits for step 1's figure) and publish it.

```sh
python3 -m venv v && v/bin/pip install glyphsift==0.1.3 && v/bin/python -I -c "import glyphsift; print(glyphsift.score_ppm('कखग�'))"
mkdir t && cd t && npm init -y && npm i @airplanemode/glyphsift@0.1.3 && node -e 'console.log(require("@airplanemode/glyphsift").score_ppm("कखग�"))'
cargo install glyphsift-cli --locked && glyphsift --version
```

Why only you: it needs a registry that is not empty, a clean machine you control, and your name on the write-up; posting or announcing anything is yours.

## If a publish step fails

Do this yourself, in this order, whenever the publish job stops after its first registry step (the job log tells you which step stopped). You must never re-publish the version: a registry that has accepted a version keeps its name for good, so the fix is a new version.

In glyphsift's current step order npm is published before the crate comparison, so a refused crate comparison leaves the npm package published and the npm step of this section applies. (Reordering the workflow is deferred and not part of this release.)

```sh
cargo yank glyphsift-core@0.1.3
cargo yank glyphsift-cli@0.1.3
npm deprecate @airplanemode/glyphsift@0.1.3 "Published by mistake; do not use"
```

1. Yank each crate that was published: `glyphsift-core` and `glyphsift-cli` (only those the log shows as published).
2. On npm, run `npm deprecate` at once. `npm unpublish` is allowed only within 72 hours of the publish; if you unpublish, do it inside that window.
3. Now revoke both tokens on npmjs.com and crates.io, and delete the environment secrets as in step 15.
4. Disarm the workflow: `gh variable delete RELEASE_PUBLISH_ARMED --env release --repo AirplaneMode-Labs/glyphsift`.
5. Record the run id and the step that failed in your private notes, then fix forward with a new version.

Only you can do this because they are your accounts, your tokens and your decision to withdraw a version.

## Settings worth turning on

These are repository settings, so they are yours too; none blocks a release: a tag ruleset for `v*`, branch protection on `main`, secret-scanning push protection, private vulnerability reporting (the SECURITY.md contact is an email address until you turn it on),
and a `CODEOWNERS` file for `docs/release-keys.json`, `scripts/release/release-tool.mjs` and `.github/workflows/publish.yml`.

## What a release does not claim

glyphsift 0.1.3 checks structure on synthetic text only (the gate included: its default threshold was derived from synthetic noise, not from real documents): no real document has been scored, the weights are an author's judgement and were never tuned on the
benchmark, and the benchmark proves only that the score falls as injected structural damage rises. Nothing was measured on an 8 GB Windows no-GPU laptop (not measured on 8 GB), and nothing is signed until step 12. A release note should say so in the same words, and the
README Limitations section is the list.
