# Contributing to Sidekit

Thanks for your interest. Sidekit is two native apps that share one design — pick the platform you
want to work on. New to the codebase? Read **[STRUCTURE.md](STRUCTURE.md)** first; it maps the whole
repo and tells you where to start.

## Build & run

The shipped app is macOS — full instructions are in its README:

- **macOS** — [`mac/README.md`](mac/README.md). One command: `cd mac && ./Scripts/build-app.sh`.
  Needs an Apple Silicon Mac, macOS 14+, and Xcode command-line tools.

Windows is a [planned](vision/ROADMAP.md) future platform — there's no Windows code in the repo yet.

## Run the tests

Every change ships with tests. Run them before opening a pull request:

```sh
cd mac && swift test
```

## How we work: bricks

We build in **bricks** — one small, self-contained change at a time. The loop for every brick:

1. Make the smallest change that delivers one coherent piece of the goal.
2. Review the diff — every line should trace to the goal.
3. Test it (write the test first, then make it pass).
4. Verify the real behavior, not just that the tests are green.

Keep changes **surgical**: touch only what the change needs, and match the surrounding style. The
full engineering rules are in [`CLAUDE.md`](CLAUDE.md); the running build log is [`BRICKS.md`](BRICKS.md).

## Pull requests

- Keep each PR focused on one change — smaller is easier to review.
- Make sure the tests pass on the platform(s) you touched.
- Describe **what changed, why it matters, and how you verified it.**
- Found a bug or have an idea? Open an issue first, so we can agree on the approach before you build.

## A note on scope

Sidekit's non-negotiable is **on-device by default** — dictation, correction, and any drafting all
run locally; privacy is the product, not a setting. Changes that route user content to a cloud
service won't be accepted unless the feature is explicitly opt-in and clearly named.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
