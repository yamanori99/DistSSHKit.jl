# [paths](@id Manual-paths)

Scripts should use [`ns_path`](@ref) so the same relative name resolves on
the kit parent and on workers.

- If `DISTRIBUTED_OUTPUT_DIR` is set (go slot / drive result root), that
  join wins when the file exists, and is the default for new writes
- Otherwise the path is under the project root (the tree `setup --rsync`
  already copies, minus `.distsshkit/`)

[`cache_file`](@ref) stores a blob at
`.distsshkit/cache/sha256/<sha256>` keyed by [`file_sha256`](@ref).
Identical contents share one file. Project `setup --rsync` still excludes
`.distsshkit/`. Call [`push_cache!`](@ref) to rsync those blobs onto SSH
hosts (no `--delete`; extra remote hashes stay). Optional `hashes=` limits
the list. Empty local cache is a no-op success.

Also: [go](@ref Manual-go), [drive](@ref Manual-drive), [`ns_path`](@ref).
