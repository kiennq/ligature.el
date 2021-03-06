;;; ligature.el --- display typographical ligatures in major modes  -*- lexical-binding: t; -*-

;; Copyright (C) 2020  Mickey Petersen

;; Author: Mickey Petersen <mickey@masteringemacs.org>
;; Keywords: tools faces
;; Homepage: https://www.github.com/mickeynp/ligature.el
;; Package-Requires: ((emacs "27.1"))
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package converts graphemes (characters) present in major modes
;; of your choice to the stylistic ligatures present in your frame's
;; font.
;;
;; For this to work, you must meet several criteria:
;;
;;  1. You must use Emacs 27.1 or later;
;;
;;     WARNING: Some issues report crash issues with Emacs versions
;;              Emacs 27.1. This is fixed in an upstream version
;;              currently only available in the master branch.
;;
;;  2. Your Emacs must be built with Harfbuzz enabled -- this is the
;;     default as of Emacs 27.1, but obscure platforms may not support
;;     it;
;;
;;  3. You must have a font that supports the particular typographical
;;     ligature you wish to display.  Emacs should skip the ones it does
;;     not recognize, however;
;;
;;  4. Ideally, your Emacs is built with Cairo support.  Without it,
;;     you may experience issues;
;;
;;     a. Older versions of Cairo apparently have some
;;     issues.  `cairo-version-string' should say "1.16.0" or later.
;;
;;
;; If you have met these criteria, you can now enable ligature support
;; per major mode.  Why not globally? Well, you may not want ligatures
;; intended for one thing to display in a major mode intended for
;; something else.  The other thing to consider is that without this
;; flexibility, you would be stuck with whatever style categories the
;; font was built with; in Emacs, you can pick and choose which ones
;; you like.  Some fonts ship with rather unfashionable ligatures.  With
;; this package you will have to tell Emacs which ones you want.
;;
;;
;;
;; GETTING STARTED
;; ---------------
;;
;; To install this package you should use `use-package', like so:
;;
;; (use-package ligature
;;   :config
;;   ;; Enable the "www" ligature in every possible major mode
;;   (ligature-set-ligatures 't '("www"))
;;   ;; Enable traditional ligature support in eww-mode, if the
;;   ;; `variable-pitch' face supports it
;;   (ligature-set-ligatures 'eww-mode '("ff" "fi" "ffi"))
;;   ;; Enable all Cascadia Code ligatures in programming modes
;;   (ligature-set-ligatures 'prog-mode '("|||>" "<|||" "<==>" "<!--" "####" "~~>" "***" "||=" "||>"
;;                                        ":::" "::=" "=:=" "===" "==>" "=!=" "=>>" "=<<" "=/=" "!=="
;;                                        "!!." ">=>" ">>=" ">>>" ">>-" ">->" "->>" "-->" "---" "-<<"
;;                                        "<~~" "<~>" "<*>" "<||" "<|>" "<$>" "<==" "<=>" "<=<" "<->"
;;                                        "<--" "<-<" "<<=" "<<-" "<<<" "<+>" "</>" "###" "#_(" "..<"
;;                                        "..." "+++" "/==" "///" "_|_" "www" "&&" "^=" "~~" "~@" "~="
;;                                        "~>" "~-" "**" "*>" "*/" "||" "|}" "|]" "|=" "|>" "|-" "{|"
;;                                        "[|" "]#" "::" ":=" ":>" ":<" "$>" "==" "=>" "!=" "!!" ">:"
;;                                        ">=" ">>" ">-" "-~" "-|" "->" "--" "-<" "<~" "<*" "<|" "<:"
;;                                        "<$" "<=" "<>" "<-" "<<" "<+" "</" "#{" "#[" "#:" "#=" "#!"
;;                                        "##" "#(" "#?" "#_" "%%" ".=" ".-" ".." ".?" "+>" "++" "?:"
;;                                        "?=" "?." "??" ";;" "/*" "/=" "/>" "//" "__" "~~" "(*" "*)"
;;                                        "\\" "://"))
;;   ;; Enables ligature checks globally in all buffers.  You can also do it
;;   ;; per mode with `ligature-mode'.
;;   (global-ligature-mode t))
;;
;;
;; EXAMPLES
;; --------
;;
;; Map two ligatures in `web-mode' and `html-mode'.  As they are simple
;; (meaning, they do not require complex regular expressions to ligate
;; properly) using their simplified string forms is enough:
;;
;;
;;
;; This example creates regexp ligatures so that `=' matches against
;; zero-or-more of `=' characters that may or may not optionally end
;; with `>' or `<'.
;;
;; (ligature-set-ligatures 'markdown-mode `((?= . ,(rx (+ "=") (? (| ">" "<"))))
;;                                          (?- . ,(rx (+ "-")))))
;;
;; LIMITATIONS
;; -----------
;;
;; You can only have one character map to a regexp of ligatures that
;; must apply.  This is partly a limitation of Emacs's
;; `set-char-table-range' and also of this package.  No attempt is made
;; to 'merge' groups of regexp.  This is only really going to cause
;; issues if you rely on multiple mode entries in
;; `ligature-composition-table' to fulfill all the desired ligatures
;; you want in a mode, or if you indiscriminately call
;; `ligature-set-ligatures' against the same collection of modes with
;; conflicting ligature maps.
;;
;; OUTSTANDING BUGS
;; ----------------
;;
;; Yes, most assuredly so.


;;; Code:

(require 'cl-lib)

(defgroup ligature nil
  "Typographic Ligatures in Emacs"
  :group 'faces
  :prefix "ligature-")

(defcustom ligature-ignored-major-modes '(minibuffer-inactive-mode)
  "Major modes that will never have ligatures applied to them.

Unlike `ligature-generate-ligatures' the ignored major modes are only checked
when the minor mode command `ligature-mode' is enabled."
  :type '(repeat symbol)
  :group 'ligature)

(defvar ligature-composition-table nil
  "Alist of ligature compositions.

Each element in the alist is made up of (MODES . LIGATURE-MAPPINGS) where
LIGATURE-MAPPINGS is an alist of (CHAR . LIGATURE-PATTERN) and MODES is either:

  a. A major mode, such as `prog-mode' or `c-mode';

  b. A list of major modes, such as (`prog-mode' `c-mode');

  c. The value t, indicating the associated ligature mappings must apply to
  _all_ modes, even internal ones.

A CHAR is a _single_ character that defines the beginning of a ligature.  The
LIGATURE-PATTERN is a regexp that should match all the various ligatures that
start with STR-CHAR.  For instance, `!' as a STR-CHAR may have a two ligatures
`=' and `==' that together form `!=' and `!=='.")

(defvar ligature--generated-char-tables nil
  "Plist from `major-mode' to its generated `composition-function-table'.")

;;;###autoload
(defun ligature-set-ligatures (modes ligatures)
  "Replace LIGATURES in MODES.

Converts a list of LIGATURES, where each element is either a cons cell of `(CHAR
. REGEXP)' or a string to ligate, for all modes in MODES.  As there is no easy
way of computing which ligatures were already defined, this function will
replace any existing ligature definitions in `ligature-composition-table' with
LIGATURES for MODES.


Some ligatures are variable-length, such as arrows and borders, and need a
regular expression to accurately represent the range of characters needed to
ligate them.  In that case, you must use a cons cell of `(CHAR . REGEXP)' where
`CHAR' is the first character in the ligature and `REGEXP' is a regular
expression that matches the _rest_ of the ligature range.

For examples, see the commentary in `ligature.el'."
  ;; clear the cached table
  (setq ligature--generated-char-tables nil)
  (let (grouped-ligatures)
    (dolist (ligature ligatures)
      (cond
       ;; the simplest case - we have a string we wish to ligate
       ((stringp ligature)
        (if (< (length ligature) 2)
            (error "Ligature `%s' must be 2 characters or longer" ligature)
          (let ((char (elt ligature 0)))
            (push (list 'literal ligature)
                  (alist-get char grouped-ligatures nil nil #'equal)))))
       ;; cons of (CHAR . REGEXP)
       ((consp ligature)
        (let ((char (car ligature))
              (ligature-regexp (cdr ligature)))
          (push (list 'regex
                      ;; we can supply either a regexp string _or_ an unexpanded `rx' macro.
                      (if (stringp ligature-regexp) ligature-regexp
                        (macroexpand ligature-regexp)))
                (alist-get char grouped-ligatures nil nil #'equal))))))
    ;; given a grouped alist of ligatures, we enumerate each group and update
    ;; the `ligature-composition-table'.
    (dolist (group grouped-ligatures)
      ;; Sort the grouped ligatures - containing lists of either `literal' or
      ;; `regex' as the car of the type of atom in the cdr - as we want the
      ;; literal matchers _after_ the regex matchers. It's likely the regex
      ;; matchers supercede anything the literal matchers may encapsulate, so we
      ;; must ensure they are checked first.
      (let ((regexp-matchers (cl-remove-if (apply-partially 'equal 'literal) (cdr group) :key #'car))
            ;; Additionally we need to ditch the `literal' symbol (and just
            ;; keep the cdr, which is the string literal), even though it's a
            ;; legitimate `rx' form, because `(group (| (literal "a") (literal
            ;; "aa") ...)' will NOT yield the same automatic grouping of
            ;; shortest-to-longest matches like the canonical version that does
            ;; _not_ use literal.
            (literal-matchers (mapcan 'cdr (cl-remove-if (apply-partially 'equal 'regex)
                                                         (cdr group)
                                                         :key #'car))))
        (setf (alist-get (car group)
                         (alist-get modes ligature-composition-table nil 'remove #'equal))
              (macroexpand
               `(rx (|
                     ;; `rx' does not like nils so we have to filter them
                     ;; manually. Furthermore, we prefer regexp to literal
                     ;; matches and want them to appear first.
                     ,@(cl-remove-if 'null (list
                                            (when regexp-matchers `(group ,(car group) (| ,@regexp-matchers)))
                                            (when literal-matchers `(group (| ,@literal-matchers)))))))))))))

;;;###autoload
(defun ligature-generate-ligatures ()
  "Ligate the current buffer using its major mode to determine ligature sets.

The ligature generator traverses `ligature-composition-table' and applies every
ligature definition from every mode that matches either t (indicating that a
ligature mapping always applies); or a major mode or list of major mode symbols
that are `derived-mode-p' of the current buffer's major mode.

The changes are then made buffer-local."
  (interactive)
  (let ((table (plist-get ligature--generated-char-tables major-mode)))
    (unless table
      (setq table (make-char-table nil))
      (dolist (ligature-table ligature-composition-table)
        (let ((modes (car ligature-table)) ; `rst-mode', `html-mode', etc.
              (rules (cdr ligature-table))) ; alist of rules mapping a character to a regexp.
          ;; If `mode' is t we always apply the rules, regardless of
          ;; whether `derived-mode-p' matches or not.
          (when (or (equal modes t)
                    (cl-remove-if 'null (mapcar 'derived-mode-p
                                                (if (listp modes) modes (list modes)))))
            (dolist (rule rules)
              (set-char-table-range table (car rule)
                                    ;; in order for Emacs to properly
                                    ;; understand the ligature mappings we
                                    ;; must include either a generic "match
                                    ;; any" metacharacter to represent the
                                    ;; character that we use to define the
                                    ;; beginning of a character table
                                    ;; range.
                                    `([,(cdr rule) 0 font-shape-gstring]))))))
      (setq ligature--generated-char-tables
            (plist-put ligature--generated-char-tables major-mode table)))
    (unless (eq table composition-function-table)
      (set-char-table-parent table composition-function-table)
      (setq-local composition-function-table table))))

;;;###autoload
(define-minor-mode ligature-mode "Enables typographic ligatures"
  :init-value nil :lighter nil :keymap nil
  (if (not ligature-mode)
      (setq-local composition-function-table (default-value 'composition-function-table))
    (unless (memq major-mode ligature-ignored-major-modes)
      (ligature-generate-ligatures))))

(defun turn-on-ligature-mode ()
  "Turn on command `ligature-mode'."
  (ligature-mode t))

(define-globalized-minor-mode global-ligature-mode ligature-mode turn-on-ligature-mode)


(provide 'ligature)
;;; ligature.el ends here
