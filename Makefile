.PHONY: fmt lint validate

SHELL_SCRIPTS := mtr-test-suite.sh mtr-tests-enhanced.sh mtr-test-suite_min-comments.sh

fmt:
	shfmt -w -i 2 -ci $(SHELL_SCRIPTS)

lint:
	shellcheck -x $(SHELL_SCRIPTS)

validate:
	shfmt -d -i 2 -ci $(SHELL_SCRIPTS)
	shellcheck -x $(SHELL_SCRIPTS)
