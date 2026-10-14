# bounty-docs

Methodology, templates, and tooling for **authorized** security research run through bug-bounty
programs. This repository is deliberately **program-agnostic and target-free**: it carries the method
and the machinery, never an engagement's data.

## What is here

| Path | What it is |
| --- | --- |
| `METHODOLOGY.md` | the working method: scope discipline, evidence rules, how a round is written and graded |
| `templates/program/` | the skeleton every engagement is instanced from — scope, plan, findings, state, rounds |
| `tools/scan-secrets.sh` | the publish gate: derives its patterns from a vault at run time and refuses on any hit in the tree or the history |
| `tools/check-conformance.sh` | structural check of a program tree (required documents, live references, generated indexes, producer tests) |
| `tools/build-rounds.sh` | regenerates the round index from the round files themselves |
| `tools/mailctl.py` | reads a mailbox configured per account, for registration/verification loops on authorized targets |
| `tools/android/` | headless emulator helpers for mobile-app review of programs that ship an app |

## What is deliberately NOT here

Engagement records. Per-program scope, targets, requests, responses, candidates, findings and evidence are
**not published**: program rules routinely forbid discussing a program outside it, and an unpatched
vulnerability in a public repository is a disclosure, not documentation. If you want an example, the
templates are the shape of that record — not its content.

## Rules this tooling enforces

- **Never commit a credential**, a personal address, or third-party data. `tools/scan-secrets.sh` is the
  gate and it runs before anything is published.
- **Keep a session's material out of the record**: values are cited as a digest (`<redacted:…>`), never as
  the value.
- **Only act inside authorized scope.** Out-of-scope material is documented, never probed.
- **A finding is cited, never asserted**: every claim carries the artefact that produced it.

## Using the templates

```sh
cp -r templates/program ~/work/<program>
$EDITOR ~/work/<program>/SCOPE.md   # scope first: nothing is sent before it is written down
```

Each template file documents what belongs in it and what does not. `STATE.json` is machine-readable and is
written as data by a writer script, never spliced as text.

## License

No license is granted for the engagement content (absent by design). The tooling is provided as-is for
authorized research.
