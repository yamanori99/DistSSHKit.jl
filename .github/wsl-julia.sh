#!/usr/bin/env bash
# Julia inside WSL2. The caller is wsl-bash and cwd is the Actions checkout.
# The workflow's actions/cache restores .ci-cache/wsl-julia (one channel per key).
#
#   ./.github/wsl-julia.sh <juliaup-channel> <command...>
set -euo pipefail

channel="$1"
shift

src="$(pwd)"
dest="$HOME/DistSSHKit.jl"
cache="$src/.ci-cache/wsl-julia"
mkdir -p "$cache"
rm -rf "$dest"
git clone "$src" "$dest"
# juliaup does not retry its own download of a nightly tarball. The curl
# retries cover only https://install.julialang.org.
install_julia() {
  local attempt
  for attempt in 1 2 3; do
    rm -rf "$HOME/.juliaup" "$HOME/.julia"
    if curl --retry 5 --retry-delay 5 --retry-connrefused --connect-timeout 10 \
      -fsSL https://install.julialang.org | sh -s -- --yes --default-channel "$channel"
    then
      return 0
    fi
    echo "Julia install attempt ${attempt} failed" >&2
    sleep $((attempt * 10))
  done
  echo "Julia install failed after 3 attempts" >&2
  return 1
}
if [[ -f "$cache/julia.tgz" ]]; then
  tar -xzf "$cache/julia.tgz" -C "$HOME"
else
  install_julia
fi
export PATH="$HOME/.juliaup/bin:$PATH"
cd "$dest"
"$@"
if [[ -d "$HOME/.julia" ]]; then
  tar -czf "$cache/julia.tgz" -C "$HOME" .juliaup .julia
else
  tar -czf "$cache/julia.tgz" -C "$HOME" .juliaup
fi
