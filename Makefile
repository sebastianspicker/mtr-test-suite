.PHONY: fmt lint validate

SHELLCHECK ?= shellcheck
SHFMT ?= shfmt

SHELL_SCRIPTS := mtr-test-suite.sh mtr-tests-enhanced.sh mtr-test-suite_min-comments.sh scripts/ci-local.sh scripts/ci-install-tools.sh

fmt:
	$(SHFMT) -w -i 2 -ci $(SHELL_SCRIPTS)

lint:
	$(SHELLCHECK) -x $(SHELL_SCRIPTS)

validate:
	$(SHFMT) -d -i 2 -ci $(SHELL_SCRIPTS)
	$(SHELLCHECK) -x $(SHELL_SCRIPTS)
