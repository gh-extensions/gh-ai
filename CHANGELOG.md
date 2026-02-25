# Changelog

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
