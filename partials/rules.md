## Scope Rules

Read `guardian/config.yaml` for `rules.avoid` and `rules.focus` arrays.

**Rules to Avoid:**
Do NOT test these paths, subdomains, or methods. Skip any endpoint matching these patterns. If the avoid list is empty, no restrictions apply.

**Rules to Focus:**
PRIORITIZE these paths and subdomains. Test them first and most thoroughly. If the focus list is empty, test all in-scope endpoints equally.
