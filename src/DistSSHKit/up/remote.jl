"""Shell that finds the juliaup binary and refuses a build older than [`JULIAUP_MIN`](@ref)."""
function _juliaup_locate_sh(candidates::Vector{String})::String
    words = join(_juliaup_candidate_sh_word.(candidates), " ")
    tried = join(candidates, ", ")
    floor_major = JULIAUP_MIN.major
    floor_minor = JULIAUP_MIN.minor
    floor = "$(floor_major).$(floor_minor)"
    return """
    JU=\"\"
    for c in $words; do
      if [ -x \"\$c\" ]; then
        JU=\"\$c\"
        break
      fi
    done
    if [ -z \"\$JU\" ]; then
      echo \"juliaup not found (tried: $tried)\" >&2
      exit 127
    fi
    ver=\$( \"\$JU\" --version 2>/dev/null | head -n 1 )
    case \"\$ver\" in
      \"Juliaup \"[0-9]*)
        ;;
      *)
        echo \"juliaup --version unreadable: \$ver\" >&2
        exit 1
        ;;
    esac
    num=\${ver#Juliaup }
    num=\${num%%[!0-9.]*}
    major=\${num%%.*}
    rest=\${num#*.}
    minor=\${rest%%.*}
    if [ \"\$major\" -gt $floor_major ] || { [ \"\$major\" -eq $floor_major ] && [ \"\$minor\" -ge $floor_minor ]; }; then
      :
    else
      echo \"juliaup \$num is older than $floor\" >&2
      exit 1
    fi
    """
end

"""SSH body: add / update / default `channel` with remote juliaup."""
function _juliaup_align_remote_sh(
        channel::AbstractString;
        candidates::Vector{String} = remote_juliaup_candidates(),
    )::String
    ch = String(channel)
    cq = _remote_sh_quote(ch)
    return """
    $(_juliaup_locate_sh(candidates))
    default=\$( \"\$JU\" status 2>/dev/null | awk '\$1==\"*\" { print \$2; exit }' )
    if [ \"\$default\" = $cq ]; then
      echo already
      exit 0
    fi
    if ! \"\$JU\" add $cq; then
      if ! \"\$JU\" status 2>/dev/null | grep -F -q $cq; then
        # `$cq` (not raw `$ch`): channel may come from the API; keep it shell-safe.
        printf 'juliaup add %s failed\\n' $cq >&2
        exit 1
      fi
    fi
    \"\$JU\" update $cq || exit \$?
    \"\$JU\" default $cq || exit \$?
    echo ok
    """
end

"""SSH body: `juliaup update` (all installed channels; does not `default`)."""
function _juliaup_update_remote_sh(
        candidates::Vector{String} = remote_juliaup_candidates(),
    )::String
    return """
    $(_juliaup_locate_sh(candidates))
    \"\$JU\" update || exit \$?
    echo ok
    """
end

"""SSH body: `juliaup add` `channel`. Already installed counts as success."""
function _juliaup_add_remote_sh(
        channel::AbstractString;
        candidates::Vector{String} = remote_juliaup_candidates(),
    )::String
    cq = _remote_sh_quote(String(channel))
    return """
    $(_juliaup_locate_sh(candidates))
    if ! \"\$JU\" add $cq; then
      if ! \"\$JU\" status 2>/dev/null | grep -F -q $cq; then
        printf 'juliaup add %s failed\\n' $cq >&2
        exit 1
      fi
    fi
    echo ok
    """
end

"""SSH body: `juliaup default` `channel`. Missing channel fails."""
function _juliaup_default_remote_sh(
        channel::AbstractString;
        candidates::Vector{String} = remote_juliaup_candidates(),
    )::String
    cq = _remote_sh_quote(String(channel))
    return """
    $(_juliaup_locate_sh(candidates))
    \"\$JU\" default $cq || exit \$?
    echo ok
    """
end

"""SSH body: `juliaup update` for one channel. Does not `default`."""
function _juliaup_update_channel_remote_sh(
        channel::AbstractString;
        candidates::Vector{String} = remote_juliaup_candidates(),
    )::String
    cq = _remote_sh_quote(String(channel))
    return """
    $(_juliaup_locate_sh(candidates))
    \"\$JU\" update $cq || exit \$?
    echo ok
    """
end
