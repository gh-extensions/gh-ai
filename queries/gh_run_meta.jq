"_ctx_title=" + ((.displayTitle // "") | @sh),
"_ctx_conclusion=" + ((.conclusion // "") | @sh),
"_ctx_url=" + ((.url // "") | @sh),
"_ctx_event=" + ((.event // "") | @sh),
"_ctx_branch=" + ((.headBranch // "") | @sh),
"_ctx_head_sha=" + ((.headSha // "") | @sh),
"_ctx_jobs=" + (([(.jobs // [])[] |
  "- \(.name): \(.conclusion // .status)" +
  (if .steps then
    "\n" + ([.steps[] |
      select(.conclusion != "success" and .conclusion != "skipped") |
      "    - Step \(.number) \(.name): \(.conclusion // .status)"
    ] | join("\n"))
  else "" end)
] | join("\n")) | @sh)
