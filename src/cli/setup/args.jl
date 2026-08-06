function show_requirements()
    print_help_chrome("DistSSHKit setup")
    print_help_lines(
        "Deploy and verify your Julia project on SSH hosts before `go` / `drive`.",
        "Default remote path: ~/Parent/RepoName (from local path), or set",
        "--remote-path / DISTRIBUTED_REMOTE_PROJECT_ROOT.",
    )
    print_help_blank()
    print_help_section("Prerequisites")
    print_help_lines(
        "  1. SSH key auth to all remote hosts (ssh-copy-id user@host)",
        "  2. Julia installed on all hosts (auto-detected, or --julia PATH)",
        "  3. Same repo layout on remotes, or set --remote-path /",
        "     DISTRIBUTED_REMOTE_PROJECT_ROOT (use the same ENV for drive/go too)",
        "  4. (git deploy only) Git remote access from all hosts",
    )
    print_help_blank()
    print_help_section("Recommended first-time setup (rsync)")
    print_help_lines(
        "  julia --project=. -m DistSSHKit setup --rsync host1 host2 host3",
        "  julia --project=. -m DistSSHKit setup --instantiate host1 host2 host3",
        "  julia --project=. -m DistSSHKit setup --check --ignore-julia-version host1 host2 host3",
        "  julia --project=. -m DistSSHKit go host1:1 host2:1 SCRIPT.jl",
        "  julia --project=. -m DistSSHKit drive host1:2 host2:2 SCRIPT.jl",
        "",
        "  After --rsync there is no remote .git/; that is fine — drive/go do not",
        "  require git parity by default. Use drive --require-git only on git remotes.",
    )
    print_help_blank()
    print_help_section("Optional git deploy")
    print_help_lines(
        "  julia --project=. -m DistSSHKit setup --clone host1 host2 host3",
        "  julia --project=. -m DistSSHKit setup --instantiate host1 host2 host3",
        "  julia --project=. -m DistSSHKit setup --check host1 host2 host3",
        "  # later updates:",
        "  julia --project=. -m DistSSHKit setup --sync host1 host2 host3",
    )
    print_help_blank()
    print_help_section("Deploy modes (pick one per invocation)")
    print_help_lines(
        "  --rsync  recommended: copy tree onto missing/empty path (no remote .git/;",
        "           run --delete first to replace)",
        "  --clone  git clone onto missing/empty path",
        "  --sync   git push (local) + git pull (remotes) — git workflows",
        "  --pull   git pull (local first, then remotes) — no push required",
        "",
        "  Existing remote files are never overwritten by --clone / --rsync.",
        "  To replace a tree: setup --delete HOST ..., then --clone or --rsync.",
    )
    print_help_blank()
    print_help_section("Custom clone URL or remote path")
    print_help_lines(
        "  julia --project=. -m DistSSHKit setup \\",
        "    --repo git@github.com:ORG/App.jl.git \\",
        "    --remote-path /data/shared/App.jl \\",
        "    --clone host1 host2",
        "  export DISTRIBUTED_REMOTE_PROJECT_ROOT=/data/shared/App.jl",
    )
    print_help_blank()
    print_help_section("Other useful commands")
    print_help_lines(
        "  --cleanup host...   kill stale Julia worker processes (local + remotes)",
        "  --delete host...    remove remote repo dirs via SSH (not drive/go `local`)",
        "  size                estimate worker counts from RAM/CPU",
        "                      (julia -m DistSSHKit size --help)",
        "",
        "Full option reference: julia --project=. -m DistSSHKit setup --help",
    )
end

function parse_setup_args(args::Vector{String})
    cli_session, args = DistSSHKit.peel_kit_cli_flags(args)
    mode = nothing
    julia_path = get(ENV, "JULIA_DISTRIBUTED_EXE", "auto")  # default to env or auto-detect
    repo_url = nothing
    remote_path_override = nothing
    hosts = String[]
    show_help = false
    ignore_julia_version = false

    c = DistSSHKit.CliCursor(args)
    while !DistSSHKit.cli_at_end(c)
        arg = DistSSHKit.cli_current(c)::String
        if arg == "--check"
            mode = :check
            DistSSHKit.cli_consume!(c)
        elseif arg == "--pull"
            mode = :pull
            DistSSHKit.cli_consume!(c)
        elseif arg == "--sync"
            mode = :sync
            DistSSHKit.cli_consume!(c)
        elseif arg == "--instantiate"
            mode = :instantiate
            DistSSHKit.cli_consume!(c)
        elseif arg == "--cleanup"
            mode = :cleanup
            DistSSHKit.cli_consume!(c)
        elseif arg == "--clone"
            mode = :clone
            DistSSHKit.cli_consume!(c)
        elseif arg == "--delete"
            mode = :delete
            DistSSHKit.cli_consume!(c)
        elseif arg == "--rsync"
            mode = :rsync_push
            DistSSHKit.cli_consume!(c)
        elseif arg == "--requirements"
            mode = :requirements
            DistSSHKit.cli_consume!(c)
        elseif arg == "--julia"
            julia_path = DistSSHKit.cli_take_value!(c, arg)
        elseif arg == "--repo"
            repo_url = String(strip(DistSSHKit.cli_take_value!(c, arg)))
        elseif arg in ("--remote-path", "--remote-dir")
            remote_path_override = String(strip(DistSSHKit.cli_take_value!(c, arg)))
        elseif arg == "--ignore-julia-version"
            ignore_julia_version = true
            DistSSHKit.cli_consume!(c)
        elseif DistSSHKit.cli_match(c, ["-h", "--help"])
            show_help = true
            DistSSHKit.cli_consume!(c)
        else
            push!(hosts, DistSSHKit.split_host_workers_spec(arg)[1])
            DistSSHKit.cli_consume!(c)
        end
    end

    DistSSHKit.append_hosts_file!(hosts, cli_session)
    DistSSHKit.apply_kit_cli_session!(cli_session)

    return (
        mode=mode,
        julia_path=julia_path,
        repo_url=repo_url,
        remote_path_override=remote_path_override,
        hosts=hosts,
        show_help=show_help,
        ignore_julia_version=ignore_julia_version,
        show_version=cli_session.show_version,
        cli_session=cli_session,
    )
end

function setup_help_text()::String
    """
Usage:
  julia --project=. -m DistSSHKit setup
  julia --project=. -m DistSSHKit setup --rsync hosts...
  julia --project=. -m DistSSHKit setup --clone hosts...
  julia --project=. -m DistSSHKit setup --check hosts...
  julia --project=. -m DistSSHKit setup --sync hosts...

Commands:
  (none), --requirements  Show prerequisites and quick-start workflow
  --rsync         rsync local tree to hosts (refuses nonempty path; recommended deploy)
  --clone         git clone on each remote (refuses if path already has files)
  --instantiate   Pkg.instantiate on remotes (--project=remote path)
  --check         Verify SSH, Julia, Project.toml, deps; git commit parity when .git/ exists
  --pull          git pull on localhost, then git pull on each remote
  --sync          git push from localhost, then git pull on each remote
  --cleanup       Kill stale Julia worker processes (localhost + remotes)
  --delete        Remove remote repository directories (destructive; confirmation)

Workflow (recommended):
  1. --rsync         deploy tree onto empty/missing remote path
  2. --instantiate   install deps from Manifest.toml on remotes
  3. --check         confirm remotes are ready (--ignore-julia-version if needed)
  4. `go` / `drive`  run (no silent git sync; no git parity unless drive --require-git)
  To replace an existing remote tree: --delete, then --rsync or --clone

  Optional git workflow: --clone → --instantiate → --check → daily --sync / --pull

  Remote path resolution (first match wins):
    --remote-path PATH  →  \$DISTRIBUTED_REMOTE_PROJECT_ROOT  →  ~/Parent/RepoName

What --check verifies:
  Local:  git working tree (warn if dirty), Project.toml, deps resolve, short git commit hash
  Each host: SSH, Julia (version match; patch-only mismatch warns), Project.toml
             at remote path, deps resolve; git commit matches local when remotes have .git/

--pull vs --sync vs --rsync:
  --rsync  Recommended first deploy: copies the working tree via rsync onto a
           **missing or empty** remote path only. If anything already exists there,
           refuses and asks you to `setup --delete` first (no silent overwrite).
           Excludes .git/, honors .gitignore, mirrors deletions. Remotes have no .git/;
           that is fine — `go` / `drive` do not pre-run sync or require git parity by
           default. Re-run setup --rsync when the tree changes. Optional:
           `drive --require-git` only for git-managed remotes.
  --sync   Git workflow: commit locally, push, pull on remotes. Requires push access
           and a clean local tree (uncommitted changes fail the pre-check). Opt-in on
           `go --sync` / `drive --sync` / `pipeline!` if you want a pre-run pull.
  --pull   Mini/headless workflow: pull on localhost first (self-update), then remotes.
           No push from your machine. Allows dirty local tree (warn only).

Confirmation prompts (type keyword or y/N; skip with -y / DISTSSHKIT_YES):
  --clone, --instantiate   Proceed? [y/N]
  --delete                 Type 'delete' to confirm
  --rsync                  Type 'rsync' to confirm

Options:
  --repo URL              Clone URL (default: local git `origin`; HTTPS GitHub → SSH)
  --remote-path PATH      Repo root on remotes (default: ~/Parent/Name, or
                          \$DISTRIBUTED_REMOTE_PROJECT_ROOT). Alias: --remote-dir
  --julia PATH            Julia on remotes (default: \$JULIA_DISTRIBUTED_EXE or auto-detect)
  --ignore-julia-version  Don't fail --check on major.minor Julia mismatch (warns instead; hidden under -q / --progress)
  -q, --quiet             Suppress terminal detail (kit log under .distsshkit/setup/)
  $(DistSSHKit.KIT_PROGRESS_FLAG_HELP)
  -y, --yes               Non-interactive: accept destructive/setup confirmation prompts
  --hosts-file PATH       Append hosts from a line-oriented file (`#` comments allowed)
  --version, -v           Print DistSSHKit version and exit
  -h, --help              Show this help

Arguments:
  hosts...        SSH hosts only (`user@host` or SSH config alias; `:N` ignored).
                  Not drive/go `local` / `localhost`. Not a local `.jl` path.

Environment:
  JULIA_DISTRIBUTED_EXE             Default Julia path for remote hosts
  DISTRIBUTED_PROJECT_ROOT          Local project root override (absolute path)
  DISTRIBUTED_REMOTE_PROJECT_ROOT   Repo root on SSH hosts (setup + drive).
                                    setup: `~` OK (expanded per remote shell).
                                    drive collect / addprocs: prefer absolute remote path.
  DISTRIBUTED_SSH_OPTS              SSH options override (space-separated)
  $(DistSSHKit.KIT_QUIET_ENV_HELP)
  $(DistSSHKit.KIT_PROGRESS_ENV_HELP)
  DISTSSHKIT_YES                    Same as --yes
  DISTSSHKIT_HOSTS_FILE             Default --hosts-file path

Prerequisites:
  - SSH key authentication to remote hosts
  - Julia on all hosts (auto-detected in common paths, or --julia / ENV)
  - Same project layout on remotes, or set --remote-path / ENV consistently for drive/go
  - (git deploy) Git read access from remotes; write access for --sync push

Examples:
  # Quick start (no hosts = show workflow)
  julia --project=. -m DistSSHKit setup

  # Recommended first deploy (rsync)
  julia --project=. -m DistSSHKit setup --rsync host1 host2
  julia --project=. -m DistSSHKit setup --instantiate host1 host2
  julia --project=. -m DistSSHKit setup --check --ignore-julia-version host1 host2
  julia --project=. -m DistSSHKit go host1:1 host2:1 SCRIPT.jl
  julia --project=. -m DistSSHKit drive host1:4 script.jl

  # Optional git first-time
  julia --project=. -m DistSSHKit setup --clone host1 host2
  julia --project=. -m DistSSHKit setup --instantiate host1 host2
  julia --project=. -m DistSSHKit setup --check host1 host2

  # Fork or shared filesystem path
  julia --project=. -m DistSSHKit setup --repo git@github.com:ORG/App.jl.git --clone host1
  julia --project=. -m DistSSHKit setup --remote-path ~/work/App.jl --clone host1 host2
  export DISTRIBUTED_REMOTE_PROJECT_ROOT=~/work/App.jl

  # Git updates then run (opt-in sync on go/drive if desired)
  julia --project=. -m DistSSHKit setup --sync host1 host2
  julia --project=. -m DistSSHKit drive local:4 host1:8 host2:8 scripts/jobs.jl

  # Pull-only (no push from laptop)
  julia --project=. -m DistSSHKit setup --pull host1 host2

  # Maintenance
  julia --project=. -m DistSSHKit setup --cleanup host1 host2
  julia --project=. -m DistSSHKit setup --check --ignore-julia-version host1

See also: `julia -m DistSSHKit drive --help`, `julia -m DistSSHKit size --help`
"""
end

function show_usage()
    DistSSHKit.print_help_document("DistSSHKit setup", setup_help_text())
end
