;;; org-dailies.el --- Daily-notes for Org -*- coding: utf-8; lexical-binding: t; -*-
;;;
;; Copyright © 2020-2022 Jethro Kuan <jethrokuan95@gmail.com>
;; Copyright © 2020 Leo Vivier <leo.vivier+dev@gmail.com>
;; Copyright © 2022 Nicolas Graves <ngraves@ngraves.fr>

;; Maintainer: Nicolas Graves <ngraves@ngraves.fr>
;; URL: https://git.sr.ht/~ngraves/org-dailies
;; Keywords: org-mode, convenience
;; Version: 2.2.2
;; Package-Requires: ((emacs "26.1") (dash "2.13"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; This extension provides functionality for creating daily-notes, or shortly
;; "dailies".  Dailies implemented here as a unique node per unique file, where
;; each file named after certain date and stored in `org-dailies-directory'.
;;
;; One can use dailies for various purposes, e.g. journaling, fleeting notes,
;; scratch notes or whatever else you can think of.
;;
;; This package is an org-roam free copy of org-roam-dailies
;; extension, to avoid cluttering my database with journal notes.

;;; Code:
(require 'cl-lib)
(require 'org)
(require 'org-capture)

;;; Group
(defgroup org-dailies nil
  "Simple org daily notes without org-roam."
  :group 'org
  :prefix "org-dailies-")

;;; Faces
(defface org-dailies-calendar-note
  '((t :inherit (org-link) :underline nil))
  "Face for dates with a daily-note in the calendar."
  :group 'org-roam-faces)

;;; Options
(defcustom org-dailies-directory "daily/"
  "Path to daily-notes.
This path is absolute or relative to `org-directory'."
  :group 'org-dailies
  :type 'string)

(defun org-dailies-directory ()
  "Return the absolute diretory name of the variable `org-dailies-directory'."
  (if (file-name-absolute-p org-dailies-directory)
      org-dailies-directory
      (expand-file-name org-dailies-directory org-directory)))

(defcustom org-dailies-file-extensions (list "org")
  "File extensions of daily-notes."
  :group 'org-dailies
  :type 'list)

(defcustom org-dailies-key "C-c d"
  "String setting the variable `org-dailies-map' key."
  :group 'org-dailies
  :type 'string)

(defcustom org-dailies-find-file-hook nil
  "Hook that is run right after navigating to a daily-note."
  :group 'org-dailies
  :type 'hook)

(defcustom org-dailies-capture-templates
  `(("d" "default" entry
     "* %?"
     :target (file+head "%<%Y-%m-%d>.org"
                        "#+title: %<%Y-%m-%d>\n")))
  "Capture templates for daily-notes in Org-roam.
Note that for daily files to show up in the calendar, they have to be of format
\"org-time-string.org\".
See `org-capture-templates' for the template documentation."
  :group 'org-dailies
  :type '(repeat
          (choice (list :tag "Multikey description"
                        (string :tag "Keys       ")
                        (string :tag "Description"))
                  (list :tag "Template entry"
                        (string :tag "Keys           ")
                        (string :tag "Description    ")
                        (choice :tag "Capture Type   " :value entry
                                (const :tag "Org entry" entry)
                                (const :tag "Plain list item" item)
                                (const :tag "Checkbox item" checkitem)
                                (const :tag "Plain text" plain)
                                (const :tag "Table line" table-line))
                        (choice :tag "Template       "
                                (string)
                                (list :tag "File"
                                      (const :format "" file)
                                      (file :tag "Template file"))
                                (list :tag "Function"
                                      (const :format "" function)
                                      (function :tag "Template function")))
                        (plist :inline t
                               ;; Give the most common options as checkboxes
                               :options (((const :format "%v " :target)
                                          (choice :tag "Node location"
                                                  (list :tag "File"
                                                        (const :format "" file)
                                                        (string :tag "  File"))
                                                  (list :tag "File & Head Content"
                                                        (const :format "" file+head)
                                                        (string :tag "  File")
                                                        (string :tag "  Head Content"))
                                                  (list :tag "File & Outline path"
                                                        (const :format "" file+olp)
                                                        (string :tag "  File")
                                                        (list :tag "Outline path"
                                                              (repeat (string :tag "Headline"))))
                                                  (list :tag "File & Head Content & Outline path"
                                                        (const :format "" file+head+olp)
                                                        (string :tag "  File")
                                                        (string :tag "  Head Content")
                                                        (list :tag "Outline path"
                                                              (repeat (string :tag "Headline"))))))
                                         ((const :format "%v " :prepend) (const t))
                                         ((const :format "%v " :immediate-finish) (const t))
                                         ((const :format "%v " :jump-to-captured) (const t))
                                         ((const :format "%v " :empty-lines) (const 1))
                                         ((const :format "%v " :empty-lines-before) (const 1))
                                         ((const :format "%v " :empty-lines-after) (const 1))
                                         ((const :format "%v " :clock-in) (const t))
                                         ((const :format "%v " :clock-keep) (const t))
                                         ((const :format "%v " :clock-resume) (const t))
                                         ((const :format "%v " :time-prompt) (const t))
                                         ((const :format "%v " :tree-type) (const week))
                                         ((const :format "%v " :unnarrowed) (const t))
                                         ((const :format "%v " :table-line-pos) (string))
                                         ((const :format "%v " :kill-buffer) (const t))))))))

;;; Commands
;;;; Today
;;;###autoload
(defun org-dailies-capture-today (&optional goto keys)
  "Create an entry in the daily-note for today.
When GOTO is non-nil, go the note without creating an entry.

ELisp programs can set KEYS to a string associated with a template.
In this case, interactive selection will be bypassed."
  (interactive "P")
  (org-dailies--capture (current-time) goto keys))

;;;###autoload
(defun org-dailies-goto-today (&optional keys)
  "Find the daily-note for today, creating it if necessary.

ELisp programs can set KEYS to a string associated with a template.
In this case, interactive selection will be bypassed."
  (interactive)
  (org-dailies-capture-today t keys))

;;;; Tomorrow
;;;###autoload
(defun org-dailies-capture-tomorrow (n &optional goto keys)
  "Create an entry in the daily-note for tomorrow.

With numeric argument N, use the daily-note N days in the future.

With a `C-u' prefix or when GOTO is non-nil, go the note without
creating an entry.

ELisp programs can set KEYS to a string associated with a template.
In this case, interactive selection will be bypassed."
  (interactive "p")
  (org-dailies--capture (time-add (* n 86400) (current-time)) goto keys))

;;;###autoload
(defun org-dailies-goto-tomorrow (n &optional keys)
  "Find the daily-note for tomorrow, creating it if necessary.

With numeric argument N, use the daily-note N days in the
future.

ELisp programs can set KEYS to a string associated with a template.
In this case, interactive selection will be bypassed."
  (interactive "p")
  (org-dailies-capture-tomorrow n t keys))

;;;; Yesterday
;;;###autoload
(defun org-dailies-capture-yesterday (n &optional goto keys)
  "Create an entry in the daily-note for yesteday.

With numeric argument N, use the daily-note N days in the past.

When GOTO is non-nil, go the note without creating an entry.

ELisp programs can set KEYS to a string associated with a template.
In this case, interactive selection will be bypassed."
  (interactive "p")
  (org-dailies-capture-tomorrow (- n) goto keys))

;;;###autoload
(defun org-dailies-goto-yesterday (n &optional keys)
  "Find the daily-note for yesterday, creating it if necessary.

With numeric argument N, use the daily-note N days in the
future.

ELisp programs can set KEYS to a string associated with a template.
In this case, interactive selection will be bypassed."
  (interactive "p")
  (org-dailies-capture-tomorrow (- n) t keys))

;;;; Date
;;;###autoload
(defun org-dailies-capture-date (&optional goto prefer-future keys)
  "Create an entry in the daily-note for a date using the calendar.
Prefer past dates, unless PREFER-FUTURE is non-nil.
With a `C-u' prefix or when GOTO is non-nil, go the note without
creating an entry.

ELisp programs can set KEYS to a string associated with a template.
In this case, interactive selection will be bypassed."
  (interactive "P")
  (let ((time (let ((org-read-date-prefer-future prefer-future))
                (org-read-date nil t nil (if goto
                                             "Find daily-note: "
                                           "Capture to daily-note: ")))))
    (org-dailies--capture time goto keys)))

;;;###autoload
(defun org-dailies-goto-date (&optional prefer-future keys)
  "Find the daily-note for a date using the calendar, creating it if necessary.
Prefer past dates, unless PREFER-FUTURE is non-nil.

ELisp programs can set KEYS to a string associated with a template.
In this case, interactive selection will be bypassed."
  (interactive)
  (org-dailies-capture-date t prefer-future keys))

;;;; Navigation
(defun org-dailies-goto-next-note (&optional n)
  "Find next daily-note.

With numeric argument N, find note N days in the future.  If N is
negative, find note N days in the past."
  (interactive "p")
  (unless (org-dailies--daily-note-p)
    (user-error "Not in a daily-note"))
  (setq n (or n 1))
  (let* ((dailies (org-dailies--list-files))
         (position
          (cl-position-if (lambda (candidate)
                            (string= (buffer-file-name (buffer-base-buffer)) candidate))
                          dailies))
         note)
    (unless position
      (user-error "Can't find current note file - have you saved it yet?"))
    (pcase n
      ((pred (natnump))
       (when (eq position (- (length dailies) 1))
         (user-error "Already at newest note")))
      ((pred (integerp))
       (when (eq position 0)
         (user-error "Already at oldest note"))))
    (setq note (nth (+ position n) dailies))
    (find-file note)
    (run-hooks 'org-dailies-find-file-hook)))

(defun org-dailies-goto-previous-note (&optional n)
  "Find previous daily-note.

With numeric argument N, find note N days in the past.  If N is
negative, find note N days in the future."
  (interactive "p")
  (let ((n (if n (- n) -1)))
    (org-dailies-goto-next-note n)))

(defun org-dailies--list-files (&rest extra-files)
  "List all files in the call to function `org-dailies-directory'.
EXTRA-FILES can be used to append extra files to the list."
  (let ((dir (org-dailies-directory))
        (regexp (rx-to-string `(and "." (or ,@org-dailies-file-extensions)))))
    (append (seq-remove (lambda (it)
                          (let ((file (file-name-nondirectory it)))
                            (when (or (auto-save-file-name-p file)
                                      (backup-file-name-p file)
                                      (string-match "^\\." file))
                              it)))
                      (directory-files-recursively dir regexp))
            extra-files)))

(defun org-dailies--daily-note-p (&optional file)
  "Return t if FILE is an Org daily-note, nil otherwise.
If FILE is not specified, use the current buffer's file-path."
  (when-let ((path (expand-file-name
                    (or file
                        (buffer-file-name (buffer-base-buffer)))))
             (directory (org-dailies-directory))
             (date (file-name-base file)))
    (setq path (expand-file-name path))
    (save-match-data
      (and
       (file-readable-p (concat directory date (file-name-extension path)))
       (string-equal date (org-get-title path))))))

;;;###autoload
(defun org-dailies-find-directory ()
  "Find and open the call to function `org-dailies-directory'."
  (interactive)
  (find-file (org-dailies-directory)))

;;; Calendar integration
(defun org-dailies-calendar--file-to-date (file)
  "Convert FILE to date.
Return (MONTH DAY YEAR) or nil if not an Org time-string."
  (ignore-errors
    (cl-destructuring-bind (_ _ _ d m y _ _ _)
        (org-parse-time-string
         (file-name-sans-extension
          (file-name-nondirectory file)))
      (list m d y))))

(defun org-dailies-calendar-mark-entries ()
  "Mark days in the calendar for which a daily-note is present."
  (when (file-exists-p (org-dailies-directory))
    (dolist (date (remove nil
                          (mapcar #'org-dailies-calendar--file-to-date
                                  (org-dailies--list-files))))
      (when (calendar-date-is-visible-p date)
        (calendar-mark-visible-date date 'org-dailies-calendar-note)))))

(add-hook 'calendar-today-visible-hook #'org-dailies-calendar-mark-entries)
(add-hook 'calendar-today-invisible-hook #'org-dailies-calendar-mark-entries)

;;; Capture implementation

;; TODO This function is rudimentary, bare minimum to get the job done.
(defun org-dailies--capture (time &optional goto keys)
  "Capture an entry in a daily-note for TIME, creating it if necessary.
When GOTO is non-nil, go the note without creating an entry.

ELisp programs can set KEYS to a string associated with a template.
In this case, interactive selection will be bypassed."
  (let* ((daily-note-title (format-time-string "%Y-%m-%d" time))
         (daily-note-file (concat (org-dailies-directory)
                                  daily-note-title "."
                                  (car org-dailies-file-extensions)))
         (org-capture-templates
          `(("d" "daily" plain (file ,daily-note-file)))))
    (unless (seq-reduce (lambda (bool ext)
                          (or bool
                               (file-exists-p
                                (concat (org-dailies-directory)
                                       daily-note-title "." ext))))
                        org-dailies-file-extensions
                        nil)
      (with-temp-buffer
        (insert (format "#+title: %s\n" (format-time-string "%Y-%m-%d" time)))
        (write-file daily-note-file)))
    (org-capture (if goto '(4) nil) (if keys keys "d"))
    (when goto (run-hooks 'org-dailies-find-file-hook))))

;;; Bindings
(defvar org-dailies-map (make-sparse-keymap)
  "Keymap for `org-dailies'.")

(define-prefix-command 'org-dailies-map)
(global-set-key (kbd "C-c d") 'org-dailies-map)

(define-key org-dailies-map (kbd "d") #'org-dailies-goto-today)
(define-key org-dailies-map (kbd "y") #'org-dailies-goto-yesterday)
(define-key org-dailies-map (kbd "t") #'org-dailies-goto-tomorrow)
(define-key org-dailies-map (kbd "n") #'org-dailies-capture-today)
(define-key org-dailies-map (kbd "f") #'org-dailies-goto-next-note)
(define-key org-dailies-map (kbd "b") #'org-dailies-goto-previous-note)
(define-key org-dailies-map (kbd "c") #'org-dailies-goto-date)
(define-key org-dailies-map (kbd "v") #'org-dailies-capture-date)
(define-key org-dailies-map (kbd ".") #'org-dailies-find-directory)

(provide 'org-dailies)

;;; org-dailies.el ends here
