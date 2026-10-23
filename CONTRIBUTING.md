# Contributing

Thanks for your interest in Invariant. Issues and pull requests are welcome.

## Developer Certificate of Origin (DCO)

All contributions are accepted under the [Apache License 2.0](LICENSE) and
must be signed off under the [Developer Certificate of Origin 1.1](https://developercertificate.org/).
There is no CLA.

Signing off means adding a line like this to every commit message:

```
Signed-off-by: Your Name <your.email@example.com>
```

Git adds it for you with `git commit -s`. The name and email must match the
commit author. A check on every pull request blocks commits without it; to fix
an existing branch, run `git rebase --signoff <base>` and force-push.

## Pull requests

- Open the pull request against the `main` branch.
- Keep changes focused, and add or update tests for behavior changes.
- The scripts in `tests/` must pass locally (see the README).

## Security issues

Please do not open public issues for vulnerabilities. Use GitHub's
"Report a vulnerability" (private security advisory) on this repository.
