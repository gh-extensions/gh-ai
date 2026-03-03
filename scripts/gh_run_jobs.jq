[.jobs[] |
  "- \(.name): \(.conclusion // .status)" +
  (if .steps then
    "\n" + ([.steps[] |
      select(.conclusion != "success" and .conclusion != "skipped") |
      "    - Step \(.number) \(.name): \(.conclusion // .status)"
    ] | join("\n"))
  else "" end)
] | join("\n")
