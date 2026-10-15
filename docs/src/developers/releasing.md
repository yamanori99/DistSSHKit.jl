# Releasing

DistSSHRun, DistSSHQueue, and DistSSHKit follow
[ColPrac](https://github.com/SciML/ColPrac). Below 1.0, a breaking change
raises the minor version (`x` in `0.x.y`). Anything else raises the patch
version (`y`). [Packages](packages.md) lists each package, what it
depends on, what it reexports, and which checks must be green before
register.

This page is the source for those rules. Do not keep a second copy in a
repository `CONTRIBUTING.md`.

## What is public

The same list applies to every package. DistSSHRun and DistSSHQueue are
installed on their own, so their public API is public whether or not
DistSSHKit reexports it.

- Exported names and names marked `public`: arguments, keywords, return
  types, and whether they throw.
- The CLI: command and subcommand names, flags and their meaning, whether
  a command asks for confirmation, exit codes, and what it deletes or
  changes.
- Environment variables and `config.toml` keys that users set, and the
  meaning of those keys.
- On-disk formats: `jobs.toml`, `run.toml`, and the `.distsshkit/` and
  `.distsshqueue/` layouts.
- Documented examples.

Not public: wording, layout, and color of output, the full `--help` text,
error message text, internal names (a leading `_`, or neither exported
nor `public`), and test-only variables (`DISTSSHKIT_TEST*`).

## Bug fix or breaking

Ask whether anyone relied on the old behavior and got a correct result.
Refusing to delete `~` is a fix: nobody relied on it. Making `-y` stop
deleting is breaking: scripts that passed `-y` worked. When unsure, treat
the change as breaking.

The `breaking` label is about the pull request's behavior, not about the
version number. A breaking pull request may merge without a version bump.
Do not cut a patch while that change is still on `main`. The release that
includes it raises the minor. While breaking changes wait on `main`, the
version may be `X.Y.0-DEV`. General does not take a prerelease. Drop
`-DEV` in the cut. See [Version cut](@ref version-cut) for how CI treats the hyphen.

## Layers

Read the dependency and reexport columns in [Packages](packages.md).

- When a package breaks something public, every package that reexports it
  raises its minor too. Today that is DistSSHKit for DistSSHRun and
  DistSSHQueue.
- A package that depends on it without reexporting raises only its
  compat, in a patch, unless the change leaks into its own public API.
  Today DistSSHQueue can stay on a patch when a DistSSHRun break does not
  leak.
- A change in an upper package never raises a lower one. A DistSSHKit-only
  change does not release DistSSHRun or DistSSHQueue.
- A breaking release of a package that many others depend on (a future
  DistSSHBase) is a release of all of them together. Keep such a package
  small and rarely breaking.

Below 1.0, a higher minor is a breaking bump, and a higher patch with the
same minor is not. A higher major, including the step from `0.x` to
`1.0.0`, is a breaking bump too. Rules for versions above `1.0` are not
decided. The NEWS check fails closed on those until this page says
otherwise.

## Pull requests

- A breaking change is its own pull request, with the `breaking` label.
  A branch named `breaking/…` or `break/…` adds that label. Do not mix it
  with a fix or a new feature.
- Put the NEWS entry under `### Breaking` in `## Unreleased`.
- Split a safety fix from the hardening that follows it. The fix is
  usually a patch. The hardening is often breaking.

A pull request needs one of `bug`, `enhancement`, `breaking`, or `chore`.
CI applies that from a closing issue, then the branch prefix
(`feat/`, `fix/`, `breaking/`, and `chore/` `docs/` `ci/` `test/` for
chore), then a Conventional Commit title (`fix:`, `feat:`, a `!` before
the colon, and `docs:` `test:` `ci:` `chore:`). `type(scope):` is
accepted. Otherwise it applies `chore` when the diff has no `src/`,
`ext/`, or root `Project.toml`. Anything else fails until someone adds
one of the four labels. Dependabot is exempt.

## Deprecation

1. Patch: keep the old behavior and warn. Use `Base.depwarn` for a Julia
   API. The default `--depwarn=no` hides it outside tests, so also write
   NEWS and the docs. For the CLI, print one line on stderr. Say what
   goes away, in which version, and what to use instead.
2. NEWS: `### Planned breaking (next minor)` under `## Unreleased`.
3. `AGENTS.md`: tell agents not to use the deprecated form.
4. The next minor may remove it. There is no minimum wait.

Name the version of the package whose text it is. When a lower package
is installed on its own, add that version in parentheses:
`DistSSHKit 0.11 (DistSSHRun 0.2)`. The DistSSHKit manual names
DistSSHKit versions. DistSSHRun docs name DistSSHRun versions.

When `-y` and `DISTSSHKIT_YES` stop authorizing `setup --delete`,
`setup --prune`, and `teardown`, `-y` without `--confirm-path` exits 1.
`teardown` with no delete request still prints `Would remove` and exits 0.

## When to cut

Not a calendar. Cut when `## Unreleased` has something General users
should get. Do not ship an empty cut. Do not automate the version bump
or `@JuliaRegistrator register`.

- A bug on the ordinary path ([Packages](packages.md)): cut that patch
  promptly.
- Opt-in flags, docs, CI, labels, and internal changes: when someone
  needs them on General, or when they have sat in Unreleased for two
  weeks. Docs-only changes do not get their own tag. They go out with
  the next release.
- Breaking changes wait and go out together. Do not promise a date.
  The open milestone named `X.Y.0`, with no due date, is that batch.
  One such milestone per repository. Do not register that version while
  an issue on it is open. Release DistSSHRun and DistSSHQueue first when
  both have a minor, then raise DistSSHKit once.

The GitHub Release is the notice for a patch. Do not open a Discussions
Announcement for a register. For a minor, also tell the lab what changed.

## Dependency floor

`[compat]` for our own packages is a lower bound up to the next breaking
release. `"0.1.6"` means `0.1.6` or newer, and older than `0.2`. A later
`0.1` patch installs without another release here. One exact version
would need a new cut for every upstream patch.

Raise the floor when an older release lacks a fix this package promises.
A fix reaches users on two paths. The CLI runs the upstream package, so
that path needs the floor to move. Names this package defines itself
need a release of this package. DistSSHKit and DistSSHQueue use
DistSSHRun's submodules (`DistSSHRun.DistSSHBase` and
`DistSSHRun.DistSSHUp`) instead of keeping their own copies.

Register the upstream release on General first. Then cut this package and
set the new floor in the same `Project.toml` change, in every file
[Packages](packages.md) lists. The floor does not rewrite an existing
Manifest. When the user updates, the dependency rises to at least that
floor. Leave older releases on General.

A patch never widens compat to the next minor of a package it reexports.
Dependabot ignores `DistSSH*` so it does not open that pull request.
Raise our floors by hand.

## Cutting

Below 1.0, compare the old and new `Project.toml` versions. A higher
minor is a breaking bump. A higher patch with the same minor is a patch.
Dropping `-DEV` from `X.Y.0-DEV` is a breaking cut. Dropping `-DEV` from
a patch prerelease (`0.1.7-DEV` to `0.1.7`) is a patch cut.

Patch:

1. Rename `## Unreleased` to `## X.Y.Z`. Leave
   `### Planned breaking (next minor)` under a new `## Unreleased`.
   The release section has no `### Breaking` heading. The warning you
   added in this patch is a normal bullet in the release section.
2. Raise `version` in `Project.toml`, and compat floors when
   [Dependency floor](@ref) says to.
3. Keep the cut commit to `Project.toml`, `NEWS.md`, and the compat
   files. No workflow files.

Minor:

1. The release section has a `### Breaking` heading and lists every
   breaking change. Move the items you carried out from
   `### Planned breaking (next minor)`.
2. Release in the order on [Packages](packages.md). Wait for General
   between steps. A package that reexports the broken API raises its
   minor. A package that only depends on it, and does not leak the
   change, raises a patch and its compat floor.
3. In the DistSSHKit manual, change deprecation notes that named this
   minor to say the old form is gone.

On a version-cut pull request, the `Release NEWS` workflow reads the new
`## X.Y.Z` section (from that heading to the next level-2 heading). A missing
section fails. A patch fails if the section contains a heading that is
exactly `### Breaking`. A breaking bump fails if that heading is missing.
`### Planned breaking (next minor)` is not that heading. The check warns
if a commit since the previous `v*` tag names a pull request labeled
`breaking`. The warning does not fail the job. A reverted pull request
stays in the history, so the warning is not a failure. If the GitHub API
call fails, there is no warning.

Do not lower `version`. General never takes a version down. Do not skip
a version number (`0.1.6` then `0.1.8`). A version held by `cut-hold` is
registered after the hold lifts. Register that version. Do not publish
a later number in its place.

If a release broke compatibility by mistake, revert the pull request,
ship the repair as a patch, and then either redo the work in a compatible
way or cut a minor. Decide separately whether to yank the bad version
from General.

## After a cut merges

1. Register when the checks named for this package on
   [Packages](packages.md) are green. DistSSHRun and DistSSHQueue also
   wait until `cut-hold` is clear. They do not wait for the next E2E
   weekly. DistSSHKit does not wait on DistSSHRun's E2E. DistSSHRun also
   waits, on a version-cut pull request, for `Downstream SSH E2E
   (DistSSHQueue, 1.13)`. Do not register that DistSSHRun version while
   the job is red. If the cause is DistSSHQueue, open a DistSSHQueue
   issue.
2. Comment on the merge commit, not the pull request body. Write the
   release notes under `Release notes:`. They are often shorter than
   the NEWS section, and they stand on their own. `## X.Y.Z` stays in
   `NEWS.md`.

   ```text
   @JuliaRegistrator register

   Release notes:

   ...the notes...
   ```

   A breaking release needs the word `breaking` in those notes. That
   is what General's AutoMerge looks for. The `### Breaking` items in
   NEWS are what those notes describe.
3. TagBot tags once General has the release.

TagBot uses the SSH deploy key secret `DOCUMENTER_KEY` (a write deploy
key on this repository) so the `vX.Y.Z` tag starts Docs and `stable`
updates. Docs still deploy with `GITHUB_TOKEN`. Do not add a `+doc1` tag
unless that path failed. Manual rebuild:
`gh workflow run Docs --ref vX.Y.Z`.

GitHub Releases need a token that can `POST /repos/.../releases`
(`Contents: write`). `GITHUB_TOKEN` returned 403 on v0.7.1 even though
that commit did not touch `.github/workflows`. Keep cut commits to
`Project.toml`, `NEWS.md`, and compat files. For Releases, set the
repository secret `TAGBOT_PAT`: a fine-grained personal access token for
this repository only, Contents read/write, Issues read/write. Add
Workflows read/write only when the tagged commit changes
`.github/workflows` (GitHub then requires it). TagBot reads General with
`GITHUB_TOKEN` (`registry_token`). A this-repository-only token returns
401 on `GET JuliaRegistries/General`. An empty `TAGBOT_PAT` still falls
back to `GITHUB_TOKEN` for `token`. Do not put `permissions:` on
`.github/workflows/TagBot.yml` (TagBot's defaults). If TagBot opens
`TagBot: Manual intervention needed for releases`, the tag may already
exist. Create the Release only
(`gh release create vX.Y.Z --verify-tag --notes "…"`), then close the
Issue. `--verify-tag` fails if the tag is missing. A plain
`gh release create` would mint the tag from the default branch.

Repository Settings → Actions → Workflow permissions: Read and write
(`GITHUB_TOKEN`).

## [Version cut](@id version-cut)

A version cut is a pull request whose `Project.toml` `version` went up.
CI compares that file with the base (`.github/version-cut.sh`). Other
`Project.toml` edits are not a cut. The `cut` label is added on that
rise. Removing the label sticks until the next rise. CI reads the file,
not the label.

A new version that contains a hyphen (a prerelease, such as `0.2.0-DEV`)
is not a cut, so it does not run the heavy suite or the NEWS check. The
same numbers with the prerelease removed (`0.2.0-DEV` to `0.2.0`) is a
cut.
