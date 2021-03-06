;;; pallet.el --- Manage your packages with Cask.

;; Copyright (C) @YEAR Robert Dallas Gray

;; Author: Robert Dallas Gray
;; URL: https://github.com/rdallasgray/pallet
;; Version: @VERSION
;; Created: 2013-02-24
;; Keywords: elpa, package

;; This file is NOT part of GNU Emacs.

;;; License:

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
;@COMMENTARY
;;
;;; Code:

;; We need to get a copy of the package-archives alist
;; before requiring Cask, as doing so will empty the list.
(package-initialize)

(defvar pallet--package-archives-copy
  (copy-alist package-archives))

(require 'cask)
(require 'f)

;; interactive/api functions

(defun pallet-init ()
  "Bootstrap a Cask setup from package.el information."
  (interactive)
  (pallet--repack t))

(defun pallet-install ()
  "Install packages from the Cask file."
  (interactive)
  (pallet--cask-up
   (lambda (bundle) (cask-install bundle))))

(defun pallet-update ()
  "Update installed packages."
  (interactive)
  (pallet--cask-up
   (lambda (bundle) (cask-update bundle))))

;;; private

(defvar pallet--ignored-text-comment ";;;pallet-ignore")

(defun pallet--on ()
  "Add and remove entries from your Cask file on `package-install' and `package-delete'."
  (ad-enable-advice 'package-install 'after 'pallet--after-install)
  (ad-enable-advice 'package-delete 'after 'pallet--after-delete)
  (ad-activate 'package-install)
  (ad-activate 'package-delete))

(defun pallet--off ()
  "Stop reacting to `package-install' and `package-delete'."
  (ad-disable-advice 'package-install 'after 'pallet--after-install)
  (ad-disable-advice 'package-delete 'after 'pallet--after-delete)
  (ad-activate 'package-install)
  (ad-activate 'package-delete))

(defun pallet--repack (&optional use-copy)
  "Recreate the Cask file from package.el information;
use `pallet--package-archives-copy' if USE-COPY is true."
  (let ((archive-alist
         (if use-copy pallet--package-archives-copy package-archives)))
    (pallet--ship archive-alist (pallet--pick-packages))))

(defun pallet--cask-up (&optional body)
  "Attempt to initialize Cask, optionally running BODY if initialisation succeeds."
  (if (file-exists-p (pallet--cask-file))
      (let ((bundle (cask-initialize)))
        (when body (funcall body bundle)))
    (message "No Cask file found. Run `pallet-init' to create one.")))

(defun pallet--cask-file ()
  "Location of the Cask file."
  (expand-file-name "Cask" user-emacs-directory))

(defun pallet--package-name (package-name-or-desc)
  "Return a package name from a string or package-desc struct in PACKAGE-NAME-OR-DESC."
  (if (or (stringp package-name-or-desc)
          (symbolp package-name-or-desc))
      (format "%s" package-name-or-desc)
    (if (fboundp 'package-desc-name)
        (format "%s" (package-desc-name package-name-or-desc))
      nil)))

(defun pallet--pick-packages ()
  "Get a simple list of installed packages."
  (if package-alist
      (let ((picked '()))
        (dolist (package-details package-alist)
          (push (symbol-name (car package-details)) picked))
        (reverse picked))
    nil))

(defun pallet--pick-cask (bundle)
  "Get a list of dependencies from the Cask BUNDLE."
  (pallet--pick-cask-except bundle nil))

(defun pallet--pick-cask-except (bundle excluded-package-name)
  "Get a list of dependencies from the Cask BUNDLE, excluding EXCLUDED-PACKAGE-NAME."
  (let ((picked '()))
    (dolist (package-details (cask-runtime-dependencies bundle))
      (let ((package-name (aref package-details 1)))
        (when (not (equal package-name excluded-package-name))
          (push (format "%s" package-name) picked))))
    (delete-dups picked)))

(defun pallet--pack (archives packages)
  "Construct a Caskfile from ARCHIVES and PACKAGES."
  (format "%s\n\n%s"
          (pallet--write-sources archives)
          (pallet--write-depends packages)))

(defun pallet--pack-one (package-name)
  "Add PACKAGE-NAME to the Caskfile."
  (pallet--cask-up
   (lambda (bundle)
     (cask-add-dependency bundle (format "%s" package-name) :scope 'runtime)
     (pallet--ship package-archives (pallet--pick-cask bundle)))))

(defun pallet--unpack-one (package-name)
  "Remove a PACKAGE-NAME from the Caskfile."
  (pallet--cask-up
   (lambda (bundle)
     (pallet--ship package-archives
                     (pallet--pick-cask-except bundle (intern package-name))))))

(defun pallet--ship (archives packages)
  "Create and save a Caskfile based on installed ARCHIVES and PACKAGES."
  (let ((ignored-text (when (f-exists? (pallet--cask-file))
                        (pallet--ignored-text
                         (f-read-text (pallet--cask-file))))))
    (pallet--write-file (pallet--cask-file)
                        (pallet--with-ignored-text
                         ignored-text
                         (pallet--pack archives packages)))))

(defun pallet--with-ignored-text (ignored-text text)
  "Maybe insert IGNORED-TEXT below a comment, after TEXT."
  (if ignored-text
      (concat text "\n" pallet--ignored-text-comment ignored-text)
    text))

(defun pallet--ignored-text (text)
  "Find TEXT after `pallet--ignored-text-comment'."
  (nth 1 (s-split pallet--ignored-text-comment text)))

(defun pallet--write-sources (archive-list)
  "Create a Caskfile source set from ARCHIVE-LIST."
  (let ((source-list '()))
    (dolist (source archive-list)
      (push (pallet--format-source source) source-list))
    (mapconcat 'identity (sort source-list #'string<) "\n")))

(defun pallet--format-source (source)
  "Return a string correctly formatting an archive SOURCE."
  (let ((cask-source `(,(intern (car source)) . ,(cdr source))))
    (if (member cask-source cask-source-mapping)
        (format "(source %s)" (car source))
      (format "(source \"%s\" \"%s\")" (car source) (cdr source)))))

(defun pallet--write-depends (package-list)
  "Create a Caskfile dependency set from PACKAGE-LIST."
  (let ((depends-list '()))
    (dolist (package package-list)
      (push (format "(depends-on \"%s\")" package) depends-list))
    (let ((depends-list (sort depends-list #'string<)))
      (mapconcat 'identity depends-list "\n"))))

(defun pallet--write-file (file contents)
  "Write to FILE the given (string) CONTENTS."
  (f-write contents 'utf-8 file))

(defun pallet--installed-p (package-name)
  "Return t if (string) PACKAGE-NAME is installed, or nil otherwise."
  ;; Ensure we have up-to-date information -- package-delete doesn't
  ;; recreate package-alist automatically.
  (epl-initialize t)
  (epl-package-installed-p (intern package-name)))


;; advise package.el functions

(defadvice package-install
    (after pallet--after-install (package-name-or-desc))
  "Add a dependency to the Cask file after `package-install'."
  (let ((package-name (pallet--package-name package-name-or-desc)))
    (message "Pallet: packing %s" package-name)
    (pallet--pack-one package-name)))

(defadvice package-delete
  (after pallet--after-delete (package-name-or-desc &optional version))
  "Remove a dependency from the Cask file after `package-delete'."
  ;; NB check if package is still installed; updates trigger deletes
  (let ((package-name (pallet--package-name package-name-or-desc)))
    (when (not (pallet--installed-p package-name))
      (message "Pallet: unpacking %s" package-name)
      (pallet--unpack-one package-name))))

;;;###autoload
(define-minor-mode pallet-mode
  "Maintain entries in your Cask file automatically."
  :init-value nil
  :global t
  :group 'pallet
  (if pallet-mode
      (pallet--on)
    (pallet--off)))

(provide 'pallet)

;;; pallet.el ends here
