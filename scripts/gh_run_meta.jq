"gh_run_title=" + (.displayTitle // "" | @sh),
"gh_run_conclusion=" + (.conclusion // "" | @sh),
"gh_run_url=" + (.url // "" | @sh),
"gh_run_event=" + (.event // "" | @sh),
"gh_run_branch=" + (.headBranch // "" | @sh),
"gh_run_jobs=" + (
  [.jobs[] |
    "- \(.name): \(.conclusion // .status)" +
    (if .steps then
      "\n" + ([.steps[] |
        select(.conclusion != "success" and .conclusion != "skipped") |
        "    - Step \(.number) \(.name): \(.conclusion // .status)"
      ] | join("\n"))
    else "" end)
  ] | join("\n") | @sh)
