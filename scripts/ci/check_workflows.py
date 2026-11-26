#!/usr/bin/env python3
"""Workflow boundary checks for a public compat repository.

.github/workflows/ runs in the compat repository, which is public. Its
workflows build and test from source only, so each file must not:
  - read a secret (`secrets.`, `secrets: inherit`) or name an environment;
  - upload an artifact or use a cache (both are readable by anyone who can
    read the repository or open a pull request);
  - run on `pull_request_target`, `workflow_run` or `workflow_call`;
  - grant a `write` permission.

ci/trusted/ holds the trusted workflows, which run from the private
build-input repository (docs/development/CI.md). Each file there must:
  - run only on workflow_dispatch or workflow_call;
  - run the trusted-definition action, which refuses a public repository and
    a workflow file that differs from ci/trusted/;
  - guard every artifact upload with `github.event.repository.private`.

Usage: check_workflows.py [repo root]
Exit status 0 when clean, 1 otherwise. Standard library only; the checks are
line based and match how these files are written.
"""
import glob
import os
import re
import sys

PUBLIC_FORBIDDEN = [
    ("reads a secret", re.compile(r"\bsecrets\s*(\.|:\s*inherit)")),
    ("names an environment", re.compile(r"^\s*environment\s*:")),
    ("uploads an artifact", re.compile(r"actions/upload-artifact@")),
    ("uses a cache", re.compile(r"actions/cache(/[a-z]+)?@")),
    ("has a privileged trigger", re.compile(r"^\s*(pull_request_target|workflow_run|workflow_call)\s*:")),
    ("grants a write permission", re.compile(r"^\s*[a-z-]+\s*:\s*write\b")),
]
TRIGGERS = re.compile(r"^  (push|pull_request|pull_request_target|schedule|workflow_run|release|issues|issue_comment)\s*:")
GUARD = "github.event.repository.private"
UPLOAD = re.compile(r"actions/upload-artifact@")


def lines(path):
    with open(path, encoding="utf-8") as f:
        return f.read().splitlines()


def check_public(root):
    problems = []
    for path in sorted(glob.glob(os.path.join(root, ".github", "workflows", "*.y*ml"))):
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        for n, line in enumerate(lines(path), 1):
            code = line.split("#", 1)[0]
            for what, rule in PUBLIC_FORBIDDEN:
                if rule.search(code):
                    problems.append(f"{rel}:{n}: public workflow {what}: {line.strip()}")
    return problems


def check_trusted(root):
    problems = []
    files = sorted(glob.glob(os.path.join(root, "ci", "trusted", "*.yml")))
    if not files:
        problems.append("ci/trusted: no trusted workflows")
    for path in files:
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        text = lines(path)
        if not any("uses: ./.github/actions/trusted-definition" in l for l in text):
            problems.append(f"{rel}: does not run the trusted-definition action")
        for n, line in enumerate(text, 1):
            code = line.split("#", 1)[0]
            if TRIGGERS.match(code):
                problems.append(f"{rel}:{n}: trusted workflow has an event trigger: {line.strip()}")
            if UPLOAD.search(code):
                # The upload step's `if:` is on the line before or after `uses:`.
                window = " ".join(text[max(0, n - 3):n + 1])
                if GUARD not in window:
                    problems.append(f"{rel}:{n}: artifact upload without the private-repository guard")
    return problems


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    problems = check_public(root) + check_trusted(root)
    for p in problems:
        print(p)
    print(f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
