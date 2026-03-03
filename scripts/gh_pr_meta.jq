"_ctx_title=" + ((.title // "") | @sh),
"_ctx_head=" + ((.headRefName // "") | @sh),
"_ctx_body=" + ((.body // "") | @sh),
"_ctx_commits=" + (([(.commits // [])[] | "- " + .messageHeadline] | join("\n")) | @sh),
"_ctx_comments=" + (([(.comments // [])[].body] | join("\n---\n")) | @sh)
