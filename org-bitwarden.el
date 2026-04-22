;;; org-bitwarden.el --- Bitwarden secret helper for Org Babel (Library of Babel) -*- lexical-binding: t; -*-

;; Version: 2026.4.22
;; Package-Requires: ((emacs "27.1"))
;; URL: https://codeberg.org/useless-utils/org-bitwarden
;; Keywords: org, babel, bitwarden, secrets

;;; Commentary:
;;
;; `org-bitwarden' registers a `bw' Library of Babel named block so Org Babel
;; workflows can retrieve Bitwarden secrets through it or the underlying Elisp
;; function.
;;
;; Basic use:
;;
;;   #+begin_src sh :noweb yes
;;   echo <<bw(item="3e8a1f42-dc4b-4f2a-b7e1-0c9a3d7b2e15", field="password")>>
;;   #+end_src
;;
;; Setup:
;;
;;   (require 'org-bitwarden)
;;
;; Backend selection:
;;
;;   (setq org-bitwarden-backend 'rbw) ; default, supports custom fields
;;   (setq org-bitwarden-backend 'bw)  ; official CLI, standard fields only
;;
;; Custom backend registration:
;;
;;   (org-bitwarden-register-backend 'my-backend #'my-getter-fn)
;;   ;; my-getter-fn signature: (item field) -> string
;;
;; Noweb arguments inside quoted strings:
;;
;;   Noweb call like <<bw(item=..., field=...)>> can be awkward inside quoted
;;   JSON string. Also, forms such as `item=id' do not mean "use current
;;   block variable named id". During noweb evaluation Org resolves bare names
;;   as references, so this commonly fails with a "Reference not found" error.
;;
;;   Minimal example of failing pattern:
;;
;;     #+begin_src json-ts :noweb tangle :var id="..." fieldname="token"
;;     { "url": "<<bw(item=id, field=fieldname)>>" }
;;     #+end_src
;;
;;   Reliable workaround is intermediate block that performs Babel call
;;   explicitly and is then expanded without inline arguments:
;;
;;     #+NAME: my-token
;;     #+begin_src emacs-lisp :var item="3e8a1f42-dc4b-4f2a-b7e1-0c9a3d7b2e15" field="token1" :results none :exports none :eval never-export
;;     (org-bitwarden-get item field)
;;     #+end_src
;;
;;     #+begin_src json-ts :noweb tangle
;;     { "url": "<<my-token()>>" }
;;     #+end_src
;;
;;       *NOTE* the use of `:noweb tangle' on the helper block.
;;
;; Safety:
;;
;;   This package only helps retrieve secrets for Org Babel. It does not
;;   provide secure secret handling. Once a secret is fetched, it exists as a
;;   normal Emacs Lisp string, and if noweb expansion or tangling writes it to
;;   a file then that file will contain the plaintext secret by design.
;;
;;   In other words: this package is convenience layer, not vault, not
;;   sandbox, and not guarantee against leaks caused by local compromise,
;;   backups, version control mistakes, crash dumps, autosaves, or plaintext
;;   tangled output.
;;
;; Babel evaluation confirmation prompt:
;;
;;   Babel evaluation confirmation can be disabled per file with local variables:
;;
;;     # Local Variables:
;;     # org-confirm-babel-evaluate: nil
;;     # End:
;;
;; Recommended practice:
;;
;;   Keep secret-producing helper blocks at `:exports none', avoid inserting
;;   results back into Org buffers, and do not commit tangled secret-bearing
;;   files to version control.

;;; Code:

(require 'org)
(require 'ob-core)
(require 'ob-lob)
(require 'subr-x)

(defgroup org-bitwarden nil
  "Bitwarden secret retrieval for Org Babel."
  :group 'org-babel
  :prefix "org-bitwarden-")

(defvar org-bitwarden--backends nil
  "Alist of (SYMBOL . FUNCTION) backend entries.
Each function must accept (item field) and return a string.
Use `org-bitwarden-register-backend' to add entries.")

(defcustom org-bitwarden-backend 'rbw
  "Backend used to retrieve Bitwarden secrets.

Built-in values:
  `rbw'  - unofficial Rust client with background daemon (recommended)
  `bw'   - official Bitwarden Node.js CLI

Custom backends can be added via `org-bitwarden-register-backend'."
  :type '(symbol)
  :group 'org-bitwarden)

(defcustom org-bitwarden-allow-empty nil
  "If non-nil, allow backends to return empty strings."
  :type 'boolean
  :group 'org-bitwarden)

(defconst org-bitwarden--bw-fields
  '("password" "username" "uri" "notes" "name")
  "Fields supported by official `bw get' subcommands.")

(defun org-bitwarden-register-backend (name fn)
  "Register Bitwarden retrieval backend.

NAME is symbol identifying backend (e.g. \\='my-backend).
FN is function of two string arguments (ITEM FIELD)
that returns secret as string, or signals error.

Example:
  (org-bitwarden-register-backend
   \\='my-backend
   (lambda (item field)
     (my-vault-get item field)))

After registering, select it with:
  (setq org-bitwarden-backend \\='my-backend)"
  (unless (symbolp name)
    (error "org-bitwarden: backend name must be a symbol, got %S" name))
  (unless (functionp fn)
    (error "org-bitwarden: backend function must be callable, got %S" fn))
  (setf (alist-get name org-bitwarden--backends) fn))

(defun org-bitwarden--call-process (program &rest args)
  "Run PROGRAM with ARGS and return trimmed stdout.
Signal error if PROGRAM exits non-zero."
  (with-temp-buffer
    (let ((status (apply #'process-file program nil (current-buffer) nil args)))
      (if (eq status 0)
          (string-trim (buffer-string))
        (error "org-bitwarden: command `%s' failed" program)))))

(defun org-bitwarden--rbw-get (item field)
  "Retrieve FIELD from Bitwarden item ITEM using rbw."
  (unless (executable-find "rbw")
    (error "org-bitwarden: `rbw' not found in PATH"))
  (org-bitwarden--call-process "rbw" "get" "--field" field item))

(defun org-bitwarden--bw-get (item field)
  "Retrieve FIELD from Bitwarden item ITEM using official bw CLI."
  (unless (executable-find "bw")
    (error "org-bitwarden: `bw' not found in PATH"))
  (unless (getenv "BW_SESSION")
    (error (concat "org-bitwarden: BW_SESSION not set - "
                   "run `bw unlock' and export session token")))
  ;; `bw get' uses positional subcommands for standard fields only.
  (let ((subcmd (if (member field org-bitwarden--bw-fields)
                    field
                  (error (concat "org-bitwarden: `bw' backend does not support "
                                 "custom field %S - use `rbw' instead")
                         field))))
    (org-bitwarden--call-process "bw" "get" subcmd item)))

(org-bitwarden-register-backend 'rbw #'org-bitwarden--rbw-get)
(org-bitwarden-register-backend 'bw #'org-bitwarden--bw-get)

;;;###autoload
(defun org-bitwarden-get (item field)
  "Retrieve FIELD from Bitwarden item ITEM using `org-bitwarden-backend'.

ITEM is Bitwarden item UUID (preferred) or item name.
FIELD is field name: \"password\" (default), \"username\",
or any custom field name defined on item.

Signals error if backend fails or returns non-string.
Signals error for empty strings unless `org-bitwarden-allow-empty' is non-nil."
  (let ((fn (alist-get org-bitwarden-backend org-bitwarden--backends)))
    (unless fn
      (error "org-bitwarden: unknown backend `%s' - register it with \
`org-bitwarden-register-backend'" org-bitwarden-backend))
    (let ((val (funcall fn item field)))
      (cond
       ((not (stringp val))
        (error "org-bitwarden: backend returned non-string %S" val))
       ((and (not org-bitwarden-allow-empty) (string-empty-p val))
        (error "org-bitwarden: empty result for field %S on item %S" field item))
       (t val)))))

;;; Library of Babel

(defconst org-bitwarden--lob-source
  "
#+NAME: bw
#+begin_src emacs-lisp :var item=\"\" field=\"password\" :tangle no :exports none
(org-bitwarden-get item field)
#+end_src
"
  "Org source for `bw' Library of Babel block.
Calls `org-bitwarden-get' which dispatches to `org-bitwarden-backend'.")

(defun org-bitwarden-lob-ingest ()
  "Idempotently register `bw' block in Org Library of Babel."
  (unless (assq 'bw org-babel-library-of-babel)
    (with-temp-buffer
      (insert org-bitwarden--lob-source)
      (org-mode)
      (org-babel-lob-ingest))))

(defun org-bitwarden-unload-function ()
  "Clean up LOB entry when package is unloaded via `unload-feature'."
  (setq org-babel-library-of-babel
        (assq-delete-all 'bw org-babel-library-of-babel))
  nil)

;; Init
(org-bitwarden-lob-ingest)

(provide 'org-bitwarden)
;;; org-bitwarden.el ends here
