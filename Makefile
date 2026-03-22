.PHONY: fmt lint validate test test-bash test-pwsh

SHELLCHECK ?= shellcheck
SHFMT ?= shfmt

SHELL_SCRIPTS := mtr-test-suite.sh scripts/ci-local.sh scripts/ci-install-tools.sh $(wildcard lib/*.sh)

fmt:
	$(SHFMT) -w -i 2 -ci $(SHELL_SCRIPTS)

lint:
	$(SHELLCHECK) -x $(SHELL_SCRIPTS)

validate:
	$(SHFMT) -d -i 2 -ci $(SHELL_SCRIPTS)
	$(SHELLCHECK) -x $(SHELL_SCRIPTS)

test-bash:
	tests/bats/bin/bats tests/

test-pwsh:
	pwsh -NoProfile -NonInteractive -Command "Invoke-Pester tests/ -CI"

test: test-bash test-pwsh
