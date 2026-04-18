;;; org-bitwarden-test.el --- Tests for org-bitwarden -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'org-bitwarden)

(ert-deftest org-bitwarden-register-backend-stores-function ()
  (let ((org-bitwarden--backends nil)
        (fn (lambda (_item _field) "ok")))
    (org-bitwarden-register-backend 'test-backend fn)
    (should (eq (alist-get 'test-backend org-bitwarden--backends) fn))))

(ert-deftest org-bitwarden-get-errors-on-unknown-backend ()
  (let ((org-bitwarden-backend 'missing)
        (org-bitwarden--backends nil))
    (should-error (org-bitwarden-get "item" "password")
                  :type 'error)))

(ert-deftest org-bitwarden-get-errors-on-non-string-result ()
  (let ((org-bitwarden-backend 'test)
        (org-bitwarden--backends
         (list (cons 'test (lambda (_item _field) 42)))))
    (should-error (org-bitwarden-get "item" "password")
                  :type 'error)))

(ert-deftest org-bitwarden-get-errors-on-empty-string-by-default ()
  (let ((org-bitwarden-backend 'test)
        (org-bitwarden-allow-empty nil)
        (org-bitwarden--backends
         (list (cons 'test (lambda (_item _field) "")))))
    (should-error (org-bitwarden-get "item" "password")
                  :type 'error)))

(ert-deftest org-bitwarden-get-allows-empty-string-when-configured ()
  (let ((org-bitwarden-backend 'test)
        (org-bitwarden-allow-empty t)
        (org-bitwarden--backends
         (list (cons 'test (lambda (_item _field) "")))))
    (should (equal (org-bitwarden-get "item" "password") ""))))

(ert-deftest org-bitwarden-rbw-get-errors-when-executable-missing ()
  (cl-letf (((symbol-function 'executable-find) (lambda (_name) nil)))
    (should-error (org-bitwarden--rbw-get "item" "password")
                  :type 'error)))

(ert-deftest org-bitwarden-bw-get-rejects-custom-fields ()
  (cl-letf (((symbol-function 'executable-find) (lambda (_name) t))
            ((symbol-function 'getenv) (lambda (_name) "session")))
    (should-error (org-bitwarden--bw-get "item" "token1")
                  :type 'error)))

(ert-deftest org-bitwarden-lob-ingest-is-idempotent ()
  (let ((org-babel-library-of-babel nil))
    (org-bitwarden-lob-ingest)
    (org-bitwarden-lob-ingest)
    (should (= 1 (cl-count-if (lambda (entry) (eq (car entry) 'bw))
                              org-babel-library-of-babel)))))

(ert-deftest org-bitwarden-unload-function-removes-bw-entry ()
  (let ((org-babel-library-of-babel '((bw . t) (other . t))))
    (should-not (org-bitwarden-unload-function))
    (should-not (assq 'bw org-babel-library-of-babel))
    (should (assq 'other org-babel-library-of-babel))))

;;; org-bitwarden-test.el ends here
