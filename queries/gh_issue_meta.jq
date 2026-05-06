"_ctx_title=" + ((.title // "") | @sh),
"_ctx_labels=" + (([(.labels // [])[].name] | join(", ")) | @sh),
"_ctx_body=" + ((.body // "") | @sh),
"_ctx_comments=" + (([(.comments // [])[].body] | join("\n---\n")) | @sh),
"_ctx_url=" + ((.url // "") | @sh),
"_ctx_updated_at=" + ((.updatedAt // "") | @sh)
