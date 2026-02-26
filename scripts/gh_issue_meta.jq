"gh_issue_title=" + (.title // "" | @sh),
"gh_issue_body=" + (.body // "" | @sh),
"gh_issue_labels=" + ([.labels[].name] | join(", ") | @sh),
"gh_issue_comments=" + ([.comments[].body] | join("\n---\n") | @sh)
