;;; muse-blosxom.el --- Publish a document tree for serving by (py)Blosxom

;; Copyright (C) 2004, 2005  Free Software Foundation, Inc.

;; Date: Wed, 23 March 2005
;; Author: Michael Olson (mwolson AT gnu DOT org)
;; Maintainer: Michael Olson (mwolson AT gnu DOT org)

;; This file is not part of GNU Emacs.

;; This is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free
;; Software Foundation; either version 2, or (at your option) any later
;; version.
;;
;; This is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
;; FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
;; for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Commentary:

;; The Blosxom publishing style publishes a tree of categorised files
;; to a mirrored tree of stories to be served by blosxom.cgi or
;; pyblosxom.cgi.
;;
;; Serving entries with (py)blosxom
;; --------------------------------
;;
;; Each Blosxom file must include `#date yyyy-mm-dd', or optionally
;; the longer `#date yyyy-mm-dd-hh-mm', a title (using the `#title'
;; directive) plus whatever normal content is desired.
;;
;; The date directive is not used directly by (py)blosxom or this
;; program.  You need to find two additional items to make use of this
;; feature.
;;
;;  1. A script to gather date directives from the entire blog tree
;;     into a single file.  The file must associate a blog entry with
;;     a date.
;;
;;  2. A plugin for (py)blosxom that reads this file.
;;
;; These 2 things are provided for pyblosxom in the contrib/pyblosxom
;; subdirectory.  `getstamps.py' provides the 1st service, while
;; `hardcodedates.py' provides the second service.  Eventually it is
;; hoped that a blosxom plugin and script will be found/written.
;;
;; Creating new blog entries
;; -------------------------
;;
;; There is a function called `muse-blosxom-new-entry' that will
;; automate the process of making a new blog entry.  To make use of
;; it, do the following.
;;
;;  - Customize `muse-blosxom-base-directory' to the location that
;;    your blog entries are stored.
;;
;;  - Assign the `muse-blosxom-base-directory' function to a key
;;    sequence.  I use the following code to assign this function to
;;    `C-c p l'.
;;
;;    (global-set-key "\C-cpl" 'muse-blosxom-new-entry)
;;
;;  - You should create your directory structure ahead of time under
;;    your base directory.  These directories, which correspond with
;;    category names, may be nested.
;;
;;  - When you enter this key sequence, you will be prompted for the
;;    category of your entry and its title.  Upon entering this
;;    information, a new file will be created that corresponds with
;;    the title, but in lowercase letters and having special
;;    characters converted to underscores.  The title and date
;;    directives will be inserted automatically.

;;; Contributors:

;; Gary Vaughan (gary AT gnu DOT org) is the original author of
;; `emacs-wiki-blosxom.el', which is the ancestor of this file.

;; Brad Collins (brad AT chenla DOT org) ported this file to Muse.

;; Michael Olson (mwolson AT gnu DOT org) further adapted this file to
;; Muse and continues to maintain it.

;;; Code:

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Muse Blosxom Publishing
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(require 'muse-project)
(require 'muse-publish)
(require 'muse-html)

(defgroup muse-blosxom nil
  "Options controlling the behavior of Muse Blosxom publishing.
See `muse-blosxom' for more information."
  :group 'muse-publish)

(defcustom muse-blosxom-extension ".txt"
  "Default file extension for publishing Blosxom files."
  :type 'string
  :group 'muse-blosxom)

(defcustom muse-blosxom-header
  "<lisp>(muse-publishing-directive \"title\")</lisp>\n"
  "Header used for publishing Blosxom files."
  :type '(choice string file)
  :group 'muse-blosxom)

(defcustom muse-blosxom-footer ""
  "Footer used for publishing Blosxom files."
  :type '(choice string file)
  :group 'muse-blosxom)

;; Maintain (published-file . date) alist

(defvar muse-blosxom-page-date-alist nil)

;; This isn't really used for anything, but it may be someday
(defun muse-blosxom-markup-date-directive ()
  "Add a date entry to `muse-blosxom-page-date-alist' for this page."
  (let ((date (match-string 1)))
    (save-match-data
      (add-to-list
       'muse-blosxom-page-date-alist
       `(,muse-current-file . ,date))))
  "")

;; Enter a new blog entry

(defcustom muse-blosxom-base-directory "~/Blog"
  "Base directory of blog entries, used by `muse-blosxom-new-entry'.
This is the top-level directory where your blog entries may be found
locally."
  :type 'directory
  :group 'muse-blosxom)

(defun muse-blosxom-get-categories (&optional base)
  "Retrieve all of the categories from a Blosxom project.
The base directory is specified by BASE, and defaults to
`muse-blosxom-base-directory'.

Directories starting with \".\" will be ignored."
  (unless base (setq base muse-blosxom-base-directory))
  (let (list dir)
    (dolist (file (directory-files base t "^[^.]"))
      (when (file-directory-p file)     ; must be a directory
        (setq dir (file-name-nondirectory file))
        (push dir list)
        (nconc list (mapcar #'(lambda (item)
                                (concat dir "/" item))
                            (muse-blosxom-get-categories file)))))
    list))

(defun muse-blosxom-title-to-file (title)
  "Derive a file name from the given TITLE.

Feel free to overwrite this if you have a different concept of what
should be allowed in a filename."
  (muse-replace-regexp-in-string (concat "[^-." muse-regexp-alnum "]")
                                 "_" (downcase title)))

(defun muse-blosxom-new-entry (category title)
  "Start a new blog entry with given CATEGORY.
The filename of the blog entry is derived from TITLE.
The page will be initialized with the current date and TITLE."
  (interactive
   (list
    (completing-read "Category: " (muse-blosxom-get-categories))
    (read-string "Title: ")))
  (let ((file (muse-blosxom-title-to-file title)))
    (muse-project-find-file
     file "blosxom" nil
     (concat (directory-file-name muse-blosxom-base-directory)
             "/" category)))
  (goto-char (point-min))
  (insert "#date " (format-time-string "%4Y-%2m-%2d-%2H-%2M")
          "\n#title " title
          "\n\n")
  (forward-line 2))

;; Register the Blosxom Publisher

(unless (assoc "blosxom-html" muse-publishing-styles)
  (muse-derive-style "blosxom-html" "html"
                     :suffix    'muse-blosxom-extension
                     :header    'muse-blosxom-header
                     :footer    'muse-blosxom-footer)

  (muse-derive-style "blosxom-xhtml" "xhtml"
                     :suffix    'muse-blosxom-extension
                     :header    'muse-blosxom-header
                     :footer    'muse-blosxom-footer))

(provide 'muse-blosxom)

;;; muse-blosxom.el ends here