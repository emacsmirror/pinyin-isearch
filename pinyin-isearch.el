;;; pinyin-isearch.el --- isearch mode for Chinese pinyin search.  -*- lexical-binding: t -*-

;; Copyright (c) 2023 Anoncheg1

;; Author: Anoncheg1
;; Keywords: chinese, pinyin, search
;; URL: https://github.com/Anoncheg1/pinyin-isearch
;; Version: 0.9
;; Package-Requires: ((emacs "27.2"))

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package modifies isearch mode to allow search pīnyīn with
;; pinyin (without tones).
;; Features:
;; - white spaces are ignored between syllables
;; - tone required only in first syllable in text: Zhēn de ma
;; To activate use:
;; (require 'pinyin-isearch)
;; M-x pinyin-isearch-mode
;; or
;; M-x pinyin-isearch-forward / pinyin-isearch-backward
;; C-u C-s for normal search

;;; Code:

;; How it works:
;; 1) we create list of ((\"zhuo\" . \"zhuō\")...) : pinyin-isearch-syllable-table
;; 2) we replace C-s function with our own: isearch-search-fun-function
;; 3) we find first longest syllable and very accurate do regex with tones "n\\([ūúǔùǖǘǚǜ]e\\|ü[ēéěè]\\)"
;;   for the rest of the line we apply rough regex for every vowel [eēéěè]

;; I was unable to determinate reason for this error
;; It occure only during loading and use case sensitivity in search.
;; used sisheng-regexp, sisheng-vowel-table and sisheng-syllable-table.
(condition-case nil
    (load "quail/sisheng") ; (quail-use-package "chinese-sisheng" "quail/sisheng")
  (args-out-of-range nil))


(defconst pinyin-isearch-vowel-table
  '(("a" "[āáǎà]")
    ("e" "[ēéěè]")
    ("i" "[īíǐì]")
    ("o" "[ōóǒò]")
    ("u" "[ūúǔùǖǘǚǜ]")
    ("v" "[ūúǔùǖǘǚǜ]")
    ("ue" "ü[ēéěè]")
    ("ve" "ü[ēéěè]")))

(defconst pinyin-isearch-vowel-table-normal
  '(("a" "[aāáǎà]")
    ("e" "[eēéěè]")
    ("i" "[iīíǐì]")
    ("o" "[oōóǒò]")
    ("u" "[uūúǔùǖǘǚǜ]")
    ("ue" "[uü][eēéěè]")
    ("ve" "[uü][eēéěè]")))

(defconst pinyin-isearch-message-prefix
        (concat (propertize "[pinyin]" 'face 'bold) " ")
"Used when `pinyin-isearch-mode' is activated only.")

(defun pinyin-isearch--make-sisheng-to-regex (syllable)
  "Convert SYLLABLE \"zhuō\" to \"zhu[...]\".
Used to create final regex."
  (string-match sisheng-regexp syllable)
  (let* (
         (vowel-match (downcase (match-string 0 syllable)))
         (vowel-list
          (cdr (assoc-string vowel-match sisheng-vowel-table)))
         (input-vowel (car vowel-list))
         (regex (car (cdr (assoc-string input-vowel pinyin-isearch-vowel-table)))))
    ;; replace ō with [ōóǒò]
    (replace-match regex nil nil syllable)))


(defun pinyin-isearch--get-position-first-syllable(string)
  "Get position of first syllable in query STRING."
  (let ((pos 0)
        (first-chars)
         (num 0)
         (syl)
         (len (length string)))
    (while (< num (1- (length string) ))
      (setq pos (- len num))
      ;; cut first chars
      (setq first-chars (substring string 0 pos))
      ;; find it in table
      (setq syl (cdr (assoc first-chars pinyin-isearch-syllable-table)))
      ;; break
      (setq num (if syl 999 (1+ num))))
    (if syl pos
      nil) ; else nil
    ))


(defun pinyin-isearch--brute-replace (st &optional &key normal)
  "Replace every vowels in 'ST' with wide range regex.
if 'NORMAL' add normal to regex."
  (let* (
           ;; ignore white spaces if query is more than 2 characters
         (st (if (> (length st) 1)
                 ;; then
                 (concat (substring st 0 2)
                         (mapconcat (lambda (x) (concat "\\s-*" x))
                                    (nthcdr 2 (split-string st "" t))))
               ;; else
               st)))
    ;; ignore tones, based on lisp/leim/quail/sisheng.el
    (if normal
        (dolist ( c (split-string "aeiou" "" t))
          (let ((vowel-list-regex
                 (car (cdr (assoc-string c pinyin-isearch-vowel-table-normal))) ))
            (setq st (string-replace c vowel-list-regex st))))
      ;; else
      (dolist ( c (split-string "aeiou" "" t))
          (let ((vowel-list-regex
                 (car (cdr (assoc-string c pinyin-isearch-vowel-table))) ))
            (setq st (string-replace c vowel-list-regex st)))))
    st))

(defun pinyin-isearch--prepare-query (string)
  "Main function to convert query 'STRING' to regex for isearch."
  (let* ((st (regexp-quote string))
         ;; save length
         (len (length st))
         ;; get first longest syllable
         (first-syllable-pos (if (> (length st) 1)
                                 (pinyin-isearch--get-position-first-syllable st)
                               ;; else
                               nil)))

    ;; accurate regex for first syllable and brute for other
    (if first-syllable-pos
        ;; cut first sullable
        (let* ((first-syllable (substring string 0 first-syllable-pos))

               (first-syllable
                       (cdr (assoc first-syllable pinyin-isearch-syllable-table)))

               (first-syllable (pinyin-isearch--make-sisheng-to-regex first-syllable))
               ;; if others is not null
               (others (if (< first-syllable-pos len)
                           ;; others
                       (concat "\\s-*" (pinyin-isearch--brute-replace
                                        (substring st first-syllable-pos len)
                                        :normal t))
                       ;; else
                       nil)))
          (concat first-syllable others))
         st)))

(defun pinyin-isearch--sisheng-to-normal (syllable)
  "Convert \"zhuō\" 'SYLLABLE' to \"zhuo\". Used to create list from original."
  (let ((vowel-match) (vowel-list) (base-key))
    (string-match sisheng-regexp syllable)
    ;; fin vowel
    (setq vowel-match (downcase (match-string 0 syllable)))
    (setq vowel-list
          (cdr (assoc-string vowel-match sisheng-vowel-table)))
    (setq input-vowel (car vowel-list))
    (setq base-key (nth 0 vowel-list))
    ;; fix for sisheng, we don't need "v"
    (setq base-key (if (equal base-key "v") "u"
                     ;; else
                     (if (equal base-key "ve") "ue" base-key)))
    (replace-match base-key nil nil syllable)))


(defun pinyin-isearch--isearch-search-fun-function ()
  "Replacement for `isearch-search-fun-function'.
It modifies search query string and call isearch with regex."
  (if isearch-regexp
      ;; normal execution if it is regex search
      (funcall pinyin-isearch--original-isearch-search-fun-function)
  ;; else
  (lambda (string &optional bound noerror count)
    (let ((regexp (pinyin-isearch--prepare-query string)))
      (funcall
       (if isearch-forward #'re-search-forward #'re-search-backward)
       regexp bound noerror count)))))


(defconst pinyin-isearch-syllable-table
    (mapcar (lambda (arg)
              (cons (pinyin-isearch--sisheng-to-normal arg) arg))
            sisheng-syllable-table) ;; sequence
    "Initialize syllable's table ((\"zhuo\" . \"zhuō\")...).")

(defvar-local pinyin-isearch--original-isearch-search-fun-function isearch-search-fun-function)

;;;###autoload
(define-minor-mode pinyin-isearch-simple-mode
  "Modifies function `isearch-forward'.
Allow with query {pinyin} to find {pīnyīn}."
  :lighter " p-isearch" :global nil :group 'isearch :version "29.1"
  ;; save
  (if pinyin-isearch-mode
      (setq-local pinyin-isearch--original-isearch-search-fun-function isearch-search-fun-function))
  ;; remap
  (setq-local isearch-search-fun-function 'pinyin-isearch--isearch-search-fun-function)
  ;; disable
  (if (not pinyin-isearch-mode)
      (setq-local isearch-search-fun-function pinyin-isearch--original-isearch-search-fun-function)))


;;;###autoload
(define-minor-mode pinyin-isearch-mode
  "Replace key bindings for functions `isearch-forward' and `isearch-backward'.
Allow with query {pinyin} to find {pīnyīn}.  \\C-\\u \\C-\\s used for
normal search."
  :lighter " p-isearch" :global nil :group 'isearch :version "29.1"
  :keymap (let ((map (make-sparse-keymap)))
            (define-key map (kbd "C-s") #'pinyin-isearch-forward)
            (define-key map (kbd "C-r") #'pinyin-isearch-backward)
            map))


(defadvice isearch-message-prefix (after pinyin-isearch-message-prefix activate)
  "Add prefix to isearch prompt."
  (if (and (equal isearch-search-fun-function #'pinyin-isearch--isearch-search-fun-function)
           (not isearch-regexp))
      (setq ad-return-value (concat pinyin-isearch-message-prefix ad-return-value))
    ;; else
    ad-return-value))


(defvar-local pinyin-isearch--original-isearch-search-fun-function nil
  "Place to save `isearch-search-fun-function'.")

(defun pinyin-isearch--isearch-restore ()
  "Used for hook: `isearch-mode-end-hook'."
  (setq-local isearch-search-fun-function pinyin-isearch--original-isearch-search-fun-function))


;;;###autoload
(defun pinyin-isearch-forward (&optional regexp-p no-recursive-edit)
  "Veriant of function `isearch-forward' to search with pinyin.
Just like in `pinyin-isearch-mode'.  Optional argument ARG
arguments for function `isearch-forward'.  \\C-\\u \\C-\\s used for
normal search.
Optional argument REGEXP-P isearch.
Optional argument NO-RECURSIVE-EDIT isearch."
  (interactive "P\np")
  (if (eq no-recursive-edit 4) ;; C-u M-x
      (funcall-interactively #'isearch-forward nil 1)
    ;; else
    (progn
      ;; make isearch our's
      (setq-local pinyin-isearch--original-isearch-search-fun-function isearch-search-fun-function)
      (setq-local isearch-search-fun-function 'pinyin-isearch--isearch-search-fun-function)
      ;
      (if (called-interactively-p "any")
          (funcall-interactively #'isearch-forward regexp-p no-recursive-edit)
        ;; else
        (apply #'isearch-forward '(regexp-p no-recursive-edit)))
      (add-hook 'isearch-mode-end-hook #'pinyin-isearch--isearch-restore))))


;;;###autoload
(defun pinyin-isearch-backward (&optional regexp-p no-recursive-edit)
  "Pinyin veriant of `isearch-backward', just like in `pinyin-isearch-mode'.
Optional argument ARG arguments of `isearch-backward'.  \\C-\\u
\\C-\\s used for normal search.
Optional argument REGEXP-P isearch.
Optional argument NO-RECURSIVE-EDIT isearch."
  (interactive "P\np")
  (if (eq no-recursive-edit 4) ;; C-u M-x
      (funcall-interactively #'isearch-backward nil 1)
    ;; else
    (progn
      ;; make isearch our's
      (setq-local pinyin-isearch--original-isearch-search-fun-function isearch-search-fun-function)
      (setq-local isearch-search-fun-function 'pinyin-isearch--isearch-search-fun-function)

      (if (called-interactively-p "any")
          (funcall-interactively #'isearch-forward regexp-p no-recursive-edit)
        ;; else
        (apply #'isearch-backward '(regexp-p no-recursive-edit)))

      (add-hook 'isearch-mode-end-hook #'pinyin-isearch--isearch-restore))))



(provide 'pinyin-isearch)
;;; pinyin-isearch.el ends here
