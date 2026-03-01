"gh_pr_title=" + (.title // "" | @sh),
"gh_pr_body=" + (.body // "" | @sh),
"gh_pr_head=" + (.headRefName // "" | @sh),
"gh_pr_commits=" + ([.commits[]? | "- " + .messageHeadline] | join("\n") | @sh)
