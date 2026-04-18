EMACS ?= emacs

check:
	$(EMACS) -Q --batch \
	  -L . -L test \
	  -l ert \
	  -l org-bitwarden.el \
	  -l test/org-bitwarden-test.el \
	  -f ert-run-tests-batch-and-exit
