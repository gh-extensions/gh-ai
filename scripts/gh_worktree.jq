(if .name            then "gh_worktree_name="        + (.name        | @sh) else empty end),
(if .cwd             then "gh_worktree_cwd="         + (.cwd         | @sh) else empty end),
(if .session_id      then "gh_worktree_session_id="  + (.session_id  | @sh) else empty end),
(if .remote_ref      then "gh_worktree_remote_ref="  + (.remote_ref  | @sh) else empty end)
