# Changelog

## [0.13.1](https://github.com/gh-extensions/gh-ai/compare/v0.13.0...v0.13.1) (2026-03-04)


### Bug Fixes

* improve git default branch detection in worktree script ([45ab003](https://github.com/gh-extensions/gh-ai/commit/45ab003a5e4c167f6ce29b00d1054572320fbed0))

## [0.13.0](https://github.com/gh-extensions/gh-ai/compare/v0.12.0...v0.13.0) (2026-03-04)


### Features

* add agent option passthrough to chat commands ([364bc96](https://github.com/gh-extensions/gh-ai/commit/364bc96e0e9e75640fd350850b457d0f08042bc4))
* pre-trust project directory to skip Claude trust dialog ([4d7079b](https://github.com/gh-extensions/gh-ai/commit/4d7079b18eff3980ae13e49af080dd594b18e35e))

## [0.12.0](https://github.com/gh-extensions/gh-ai/compare/v0.11.0...v0.12.0) (2026-03-03)


### Features

* add logging for agent session lifecycle events ([de51d9a](https://github.com/gh-extensions/gh-ai/commit/de51d9ae3b22700085d494869801c1418ab01ba8))
* open chat bindings in tmux window for interactive fzf ([38c68f6](https://github.com/gh-extensions/gh-ai/commit/38c68f6e0f1da61c0fc5ec124f1c1425de037079))
* overhaul session management, worktree lifecycle, and context pipeline ([7155434](https://github.com/gh-extensions/gh-ai/commit/715543482f826533058420c57608012b45c4659c))


### Bug Fixes

* resolve gh_render.awk path using BASH_SOURCE instead of _gh_ai_source_dir ([690acdc](https://github.com/gh-extensions/gh-ai/commit/690acdcf4e2ad59618ea7341725248019c053d03))
* use actual default branch in worktree tests ([2067972](https://github.com/gh-extensions/gh-ai/commit/206797212e3901351338faff9fb1a5843ac6ac27))

## [0.11.0](https://github.com/gh-extensions/gh-ai/compare/v0.10.0...v0.11.0) (2026-03-02)


### Features

* add gh ai issue comment command ([eeb421b](https://github.com/gh-extensions/gh-ai/commit/eeb421b69047f37563b55ec63f11fd86ce5ee77a))
* add gh ai pr comment subcommand ([12a8067](https://github.com/gh-extensions/gh-ai/commit/12a8067380522e637e4c002a76f0762ddc7466e7))
* pin run chat sessions to exact commit that triggered failure ([a57c392](https://github.com/gh-extensions/gh-ai/commit/a57c392ef4c9290e5b7858f6705a31f6da6b38fd))


### Bug Fixes

* add validation for required variables in gh_pr and gh_run scripts ([b2a2fc4](https://github.com/gh-extensions/gh-ai/commit/b2a2fc46e00f4777a56fbd72933cba3f30afb316))
* drop worktree- prefix from local branch names ([2579e51](https://github.com/gh-extensions/gh-ai/commit/2579e5190efb23ece5a0eb7a35b00687c7fb732c))
* fetch remote branch before creating worktree ([f48f437](https://github.com/gh-extensions/gh-ai/commit/f48f4376bbc070965d66373a3102a96704af8a5e))
* replace cat with jq to avoid WorktreeCreate hook deadlock ([5a8e622](https://github.com/gh-extensions/gh-ai/commit/5a8e6220a58afd59d7cb296d4f11acca1b94d53b))
* reuse existing worktree in WorktreeCreate hook ([a9d01a4](https://github.com/gh-extensions/gh-ai/commit/a9d01a4ca313a6298ec4db7681384a21fd9c5cc9))
* set upstream tracking on newly created worktree branches ([4886d3f](https://github.com/gh-extensions/gh-ai/commit/4886d3f497fa15adee108e00a5cc23b8002b5c46))
* squeeze blank lines in preamble before passing to agent ([01a138b](https://github.com/gh-extensions/gh-ai/commit/01a138b9db8c70ea1a5a3574d223f5d458eb86d6))
* steer gh ai pr comment toward conversational output ([962429b](https://github.com/gh-extensions/gh-ai/commit/962429b12f443a23f519b6f18d4e333cd21de4cf))
* use URL-derived worktree name for run chat sessions ([972e7d4](https://github.com/gh-extensions/gh-ai/commit/972e7d44a4c04edc12b8e7d83ca74078e2f66227))
* wrap GH_PR_DESCRIPTION in &lt;description&gt; tag in pr create template ([faef97e](https://github.com/gh-extensions/gh-ai/commit/faef97e0f951fe80f5b83f360021550083037cf6))

## [0.10.0](https://github.com/gh-extensions/gh-ai/compare/v0.9.0...v0.10.0) (2026-03-01)


### Features

* use file-backed variables to bypass ARG_MAX limits ([b5f0c8d](https://github.com/gh-extensions/gh-ai/commit/b5f0c8df73bd39da5757fb6fce60e588df394f56))


### Bug Fixes

* use pipe-based file reading in awk to prevent hangs ([5364539](https://github.com/gh-extensions/gh-ai/commit/53645392c165c762c2cf74e49874f7468fabfab6))

## [0.9.0](https://github.com/gh-extensions/gh-ai/compare/v0.8.0...v0.9.0) (2026-03-01)


### Features

* add chat commands for interactive agent sessions ([2d5c26b](https://github.com/gh-extensions/gh-ai/commit/2d5c26b0153b1b83879fff82ef51975f0750526e))
* add chat subcommands for issue, pr, and run ([2e51030](https://github.com/gh-extensions/gh-ai/commit/2e51030511883d06b95ffe28b7ee0dde862b9a9f))
* add persistent session management for chat commands ([0814548](https://github.com/gh-extensions/gh-ai/commit/08145486e55437d07ff79da37336c06b0506ed6d))
* add safe worktree removal with auto-stash and unpushed warnings ([7d20549](https://github.com/gh-extensions/gh-ai/commit/7d205490b2bcf6f9d1c6dc9d7910e12b3b735e2f))
* capture current branch in pr and run chat templates ([edcdb83](https://github.com/gh-extensions/gh-ai/commit/edcdb831850d01752f8b89ec06c443478a6bf48b))
* **extras:** add gh-fzf keybindings for gh-ai integration ([16febbf](https://github.com/gh-extensions/gh-ai/commit/16febbf893ceab45f8130993998bf514ef424ec5))


### Bug Fixes

* add warning logs when --from-pr flag is used in chat ([c730bec](https://github.com/gh-extensions/gh-ai/commit/c730bec74eb9a213d481e0004886bc19464ef048))
* configure git identity in gh_worktree.bats setup for CI compatibility ([f81eb74](https://github.com/gh-extensions/gh-ai/commit/f81eb744c3cc87e5771bf3937d02a11508f61d2e))
* ensure preamble has trailing newlines before passing to claude ([cc9081e](https://github.com/gh-extensions/gh-ai/commit/cc9081e6a273fe2658e13615fe147e19b99bdd02))
* **extras:** preserve existing GH_FZF_*_OPTS environment variables ([5def927](https://github.com/gh-extensions/gh-ai/commit/5def92721ec3f79f70e44fe54de1c097692370b7))
* filter out --from-pr flag in _cmd_chat to prevent conflicts ([5dcea3f](https://github.com/gh-extensions/gh-ai/commit/5dcea3fe208a02a904a621616182cee20436fff7))
* **run:** include workflow run id in spinner messages ([0038fcc](https://github.com/gh-extensions/gh-ai/commit/0038fcc9c722ff93c220a3d4132b6853af9ab1de))
* use dynamic default branch in gh_worktree.bats setup() ([911d723](https://github.com/gh-extensions/gh-ai/commit/911d72326b569549e3fa553ff61f8c31051d0948))
* use printf -v to set preamble variable directly ([0705be9](https://github.com/gh-extensions/gh-ai/commit/0705be9e610ae81079d6e16df3231ea860492e24))


### Performance Improvements

* **run:** truncate workflow logs to prevent ARG_MAX overflow ([6ec04a3](https://github.com/gh-extensions/gh-ai/commit/6ec04a3633d864dde53e9735514f266435e49980))

## [0.8.0](https://github.com/gh-extensions/gh-ai/compare/v0.7.0...v0.8.0) (2026-02-27)


### Features

* strip leading # from issue and PR numbers in argument parsing ([2489b88](https://github.com/gh-extensions/gh-ai/commit/2489b887b50f0380ad79ab9a64e55ff644c0dc2e))

## [0.7.0](https://github.com/gh-extensions/gh-ai/compare/v0.6.0...v0.7.0) (2026-02-27)


### Features

* add optional description flag to issue plan command ([cbfa693](https://github.com/gh-extensions/gh-ai/commit/cbfa693309ea5be0493ffc13554df9c18144fad9))

## [0.6.0](https://github.com/gh-extensions/gh-ai/compare/v0.5.0...v0.6.0) (2026-02-27)


### Features

* add envsubst as a required dependency ([894b415](https://github.com/gh-extensions/gh-ai/commit/894b415f1e874cca754c67eb9c4d506d3ca5be5b))
* replace issue develop with plan command that prints to stdout ([936233e](https://github.com/gh-extensions/gh-ai/commit/936233e6bba929cb22e4441e10388acf834c64f2))

## [0.5.0](https://github.com/gh-extensions/gh-ai/compare/v0.4.0...v0.5.0) (2026-02-26)


### Features

* add --checkout option to gh ai issue develop ([#21](https://github.com/gh-extensions/gh-ai/issues/21)) ([bd53c16](https://github.com/gh-extensions/gh-ai/commit/bd53c16b088458db29e3da0943cf24a35649c4c1))
* add -d/--description flag to gh ai commit ([8e3eb2c](https://github.com/gh-extensions/gh-ai/commit/8e3eb2ce0f1d83af28f3dfd37edb74eb626a08ab)), closes [#17](https://github.com/gh-extensions/gh-ai/issues/17)
* add -d/--description flag to gh ai pr review ([e43aa2e](https://github.com/gh-extensions/gh-ai/commit/e43aa2e49819946e24c82e3f1746ae8f6fc9beee)), closes [#18](https://github.com/gh-extensions/gh-ai/issues/18)
* add jq dependency and version command ([692e430](https://github.com/gh-extensions/gh-ai/commit/692e43095cff5aa9162236cbd147c0d630ee02c9))
* update commit template to include optional description context ([340eb0f](https://github.com/gh-extensions/gh-ai/commit/340eb0ffd4073f8463e96bdd441f81163e2ff6d0))


### Bug Fixes

* add validation for required argument values in option parsing ([0fbec1d](https://github.com/gh-extensions/gh-ai/commit/0fbec1d7bf4719fd91ec982d2fc9c1fdb47de4b4))
* address review findings in --checkout implementation ([1e7e1a1](https://github.com/gh-extensions/gh-ai/commit/1e7e1a1c658edf1ea84235b8a27c7cdb42058c27))
* resolve nameref conflict and set -e leak in tests ([ad72e4e](https://github.com/gh-extensions/gh-ai/commit/ad72e4e0184f3cd50c65f460ee559fddfdacffad))

## [0.4.0](https://github.com/gh-extensions/gh-ai/compare/v0.3.0...v0.4.0) (2026-02-25)


### Features

* add gh ai issue develop command and improve CLI consistency ([345b612](https://github.com/gh-extensions/gh-ai/commit/345b61279c25be141015d3baf83ae319bf430baf)), closes [#9](https://github.com/gh-extensions/gh-ai/issues/9)
* add gh ai issue edit command for AI-assisted issue updates ([768d472](https://github.com/gh-extensions/gh-ai/commit/768d47240a73c7fc066ad0c9bc7cb4914d6ae276))
* add gh ai pr edit command and optional description for pr create ([4b0cb15](https://github.com/gh-extensions/gh-ai/commit/4b0cb15814665e82021d35d4dbe846caafeeaa77))
* add gh ai run explain command for GitHub Actions diagnostics ([4262832](https://github.com/gh-extensions/gh-ai/commit/42628328bbbd62d5f9e8859aa862dcaa500614be)), closes [#5](https://github.com/gh-extensions/gh-ai/issues/5)
* append markdownlint-disable directive to AI-generated bodies ([2b6207e](https://github.com/gh-extensions/gh-ai/commit/2b6207ec52e9676cd8c73d8f58cd14ae70f080cb))

## [0.3.0](https://github.com/gh-extensions/gh-ai/compare/v0.2.1...v0.3.0) (2026-02-25)


### Features

* add gh ai issue create command ([09a648e](https://github.com/gh-extensions/gh-ai/commit/09a648ebda8885c8b99d8c697daede442a796e6c))
* add gh ai pr explain command ([4c988a6](https://github.com/gh-extensions/gh-ai/commit/4c988a600cc2bfa50a0b6a8c887ba65ce16f2a2d))


### Bug Fixes

* preserve flag values when filtering issue create args ([f3cca86](https://github.com/gh-extensions/gh-ai/commit/f3cca86d091b0db548f2e05b2c7735df8ac5d81e))
* remove dead _show_issue_create_help and fix stale comments ([766950e](https://github.com/gh-extensions/gh-ai/commit/766950e82a78ea7f2239dbfff7cdbdf164b95b90))

## [0.2.1](https://github.com/gh-extensions/gh-ai/compare/v0.2.0...v0.2.1) (2026-02-25)


### Bug Fixes

* remove --comment flag from gh_pr_review filter ([7746d5e](https://github.com/gh-extensions/gh-ai/commit/7746d5e95a9f6aabd151c568771b1aa958ab086f))
* remove PR number from clean_args in gh_pr_review ([2788bb4](https://github.com/gh-extensions/gh-ai/commit/2788bb48b290e98ba97e9c4fabffe01690360aff))
* use git apply instead of gh pr diff for statistics ([5b22327](https://github.com/gh-extensions/gh-ai/commit/5b22327285942f2c00f3c3f89f6de3890df5197a))

## [0.2.0](https://github.com/gh-extensions/gh-ai/compare/v0.1.0...v0.2.0) (2026-02-25)


### Features

* add issue templates for github workflow ([7d66321](https://github.com/gh-extensions/gh-ai/commit/7d6632133d06daad8a7de57aac916f8699654273))
* **cli:** add --yes flag for non-interactive PR workflow ([5343878](https://github.com/gh-extensions/gh-ai/commit/53438788fc5acb9bc31110ea3359823bbae80a17))
* **cli:** add case-insensitive prompt matching ([346adc6](https://github.com/gh-extensions/gh-ai/commit/346adc6b5ee432a8365be5d7506bf77d70931bcc))
* **cli:** add gh-agent extension with commit message generation ([2059016](https://github.com/gh-extensions/gh-ai/commit/20590167ba8a84a8236eb368e32249a6da18fa6d))
* **cli:** add install command for configuration files ([e15983a](https://github.com/gh-extensions/gh-ai/commit/e15983afcd6c5edd894cbc28d9fc0933de126703))
* **cli:** add issue task management to gh assistant ([bf70a72](https://github.com/gh-extensions/gh-ai/commit/bf70a72253ab075963b78f7c9c4d2db5d476491b))
* **install:** add force flag to cp commands ([83ad5b7](https://github.com/gh-extensions/gh-ai/commit/83ad5b7b9c029ac20d6b8b4ebb54e43308b601c4))


### Bug Fixes

* **cli:** adjust PR task list filter parameter ([957ec5d](https://github.com/gh-extensions/gh-ai/commit/957ec5daf46c84efdf65b5204fae6a1483979c6e))
* **cli:** adjust PR task list filter regex ([1b7f234](https://github.com/gh-extensions/gh-ai/commit/1b7f234e53ec0debfe559829b8ad12d717082037))
* **cli:** improve temporary file path handling ([432f291](https://github.com/gh-extensions/gh-ai/commit/432f2911a691a700c9485b2c8ff80b4d6993ad41))
* **cli:** remove commented trap command ([ec214f3](https://github.com/gh-extensions/gh-ai/commit/ec214f315e4cc390e9a5e9cc459b769c6b48c4f2))
* **cli:** remove regex filter from PR task list command ([6eb0d5c](https://github.com/gh-extensions/gh-ai/commit/6eb0d5c7588bc31e24cc5f5208dcc0695f85af7f))
* **cli:** remove unnecessary backslash in gh api commands ([ccc216a](https://github.com/gh-extensions/gh-ai/commit/ccc216a58ed4f672ee549374f87bb9d325abbf7a))
