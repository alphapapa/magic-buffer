;;; magic-buffer.el --- -*- lexical-binding: t; truncate-lines: nil; -*-
;;; Version: 0.1
;;; Author: sabof
;;; URL: https://github.com/sabof/magic-buffer

;;; Commentary:

;; The project is hosted at https://github.com/sabof/magic-buffer
;; The latest version, and all the relevant information can be found there.
;;
;; Some sections have comments such as this:
;;
;;     (info "(elisp) Pixel Specification")
;;
;; If you place the cursor in the end, and press C-x C-e, it will take you to
;; the related info page.

;;; License:

;; This file is NOT part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.
;;
;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program ; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Code:

(require 'cl-lib)
(require 'info) ; For title faces

;;; Library --------------------------------------------------------------------
;; Functions potentially useful in other contexts

(defun mb-in-range (number from to)
  "Test whether a number is in FROM \(inclusive\) TO \(exclusive\) range."
  (and (<= from number) (< number to)))

(defun mb-table-asciify-char (char)
  "Convert UTF8 table characters to their ASCII equivalents.
If a character is not a table character, it will be left unchanged."
  ;; All table characters belong to the range 9472 inclusive - 9600 exclusive,
  ;; The comment contains the first character of each range
  (cond ( (mb-in-range char 9472 9474) ?-) ; ─
        ( (mb-in-range char 9474 9476) ?|) ; │
        ( (mb-in-range char 9476 9478) ?-) ; ┄
        ( (mb-in-range char 9478 9480) ?|) ; ┆
        ( (mb-in-range char 9480 9482) ?-) ; ┈
        ( (mb-in-range char 9482 9484) ?|) ; ┊
        ( (mb-in-range char 9484 9500) ?-) ; ┌
        ( (mb-in-range char 9500 9508) ?|) ; ├
        ( (mb-in-range char 9508 9516) ?|) ; ┤
        ( (mb-in-range char 9516 9524) ?-) ; ┬
        ( (mb-in-range char 9524 9532) ?-) ; ┴
        ( (mb-in-range char 9532 9548) ?+) ; ┼
        ( (mb-in-range char 9548 9550) ?-) ; ╌
        ( (mb-in-range char 9550 9552) ?|) ; ╎
        ( (member char '(?═ ?╒ ?╔ ?╕ ?╗ ?╘ ?╚ ?╛ ?╝))    ?=)
        ( (member char '(?║ ?╓ ?╖ ?╙ ?╜))                ?-)
        ( (member char '(?╞ ?╠ ?╡ ?╣ ?╤ ?╦ ?╧ ?╩ ?╪ ?╬)) ?=)
        ( (member char '(?╟ ?╢ ?╥ ?╨ ?╫))                ?-)
        ( (member char '(?╭ ?╯ ?╱))                      ?/)
        ( (member char '(?╮ ?╰ ?╲))   (string-to-char "\\"))
        ( (= char ?╳) ?X)
        ( (mb-in-range char 9588 9600)
          (if (cl-evenp char) ?- ?|))
        ( t char)))

(defun mb-table-asciify-string (string)
  "Convert an UTF8 table to an ASCII table.
Accepts two numeric arguments, and will replace charactres in the
the corresponding region of the buffer."
  (cl-loop for char across string
           collect (or (mb-table-asciify-char char)
                       char)
           into char-list
           finally return (apply 'string char-list)))

(defun mb-table-asciify-region (from to)
  (save-excursion
    (goto-char from)
    (insert-and-inherit
     (mb-table-asciify-string
      (delete-and-extract-region from to)))))

(defun mb-table-insert (string)
  "Insert a table with UTF8 table borders, replacing them with ASCII
fallbacks, if needed."
  (let ((start-pos (point))
        end-pos)
    (condition-case error
        (progn
          (cl-loop for char across string
                   do
                   (cl-assert (char-displayable-p char)))
          (insert (propertize
                   string
                   'face '(:height
                           2.0
                           :family "DejaVu Sans Mono"
                           )
                   ))
          (setq end-pos (point))
          (goto-char start-pos)
          (let (( regions
                  (mb-region-pixel-width-multiple
                   (cl-loop while (< (point) end-pos)
                            collecting (cons (point) (line-end-position))
                            until (cl-plusp (forward-line))))))
            (cl-assert (cl-every (apply-partially '= (car regions))
                                 regions)))
          (goto-char end-pos))
      (error (mb-table-asciify-region start-pos end-pos)
             ))))

(defun mb-random-hex-color ()
  (apply 'format "#%02X%02X%02X"
         (mapcar 'random (make-list 3 255))))

(defun mb-region-pixel-width-multiple (alist)
  "Like `mb-region-pixel-width', but for multiple regions.
Takes an ALIST of format \(\(BEGINNING . END\) ... \) as an argument,
returns a list of lengths"
  (let (( position-x
          (lambda (pos)
            (goto-char pos)
            (or (car (nth 2 (posn-at-point pos)))
                (progn
                  (goto-char (line-beginning-position))
                  (set-window-start nil (point))
                  (goto-char pos)
                  (car (nth 2 (posn-at-point pos)))))))
        before after)
    (save-excursion
      (save-window-excursion
        (delete-other-windows)
        (unless (eq (current-buffer) (window-buffer))
          (set-window-buffer nil (current-buffer)))
        (cl-loop for (from . to) in alist
                 collecting (abs (- (funcall position-x from)
                                    (funcall position-x to))))
        ))))

(defun mb-region-pixel-width (from to)
  "Find a region's pixel width.
If you need to find widths of multiple regions, you might want to use
 `mb-region-pixel-width-multiple', as it will be faster."
  (car (mb-region-pixel-width-multiple (list (cons from to)))))

(defun mb-align-variable-width-internal (spec-func)
  (save-excursion
    (goto-char (line-beginning-position))
    (let* (( pixel-width
             (mb-region-pixel-width
              (point)
              (line-end-position)))
           ;; There is an off-by one bug. When word-wrap is enabled, the line will
           ;; break. That's why I substract one pixel in the end. This will show
           ;; up as a single empty character on terminals.
           ( space-spec (funcall spec-func pixel-width)
                        ))
      (if (looking-at "[\t ]+")
          (put-text-property (match-beginning 0) (match-end 0) 'display space-spec)
          (put-text-property (line-beginning-position)
                             (line-end-position)
                             'line-prefix (propertize " " 'display space-spec)))
      (goto-char (line-end-position))
      (skip-chars-backward "\t ")
      (when (looking-at "[\t ]+")
        (put-text-property (match-beginning 0) (match-end 0)
                           'invisible t))
      )))

(defun mb-center-line-variable-width ()
  "Only modifies the properties, not the text."
  (mb-align-variable-width-internal
   (lambda (pixel-width)
     `(space :align-to (- center (,(/ pixel-width 2)))))))

(defun mb-flush-line-right-variable-width ()
  "Only modifies the properties, not the text."
  (mb-align-variable-width-internal
   (lambda (pixel-width)
     `(space :align-to (- right (,pixel-width) (1))))))

;;; Helpers --------------------------------------------------------------------
;; Utilities that make this presentation possible

(defvar mb-sections nil)
(setq mb-sections nil)
(defvar mb-counter 1)
(setq mb-counter 1)

(defvar mb-expamle-image
  (or (and load-file-name
           (file-exists-p
            (concat
             (file-name-directory load-file-name)
             "lady-with-an-ermine.jpg"))
           (concat
            (file-name-directory load-file-name)
            "lady-with-an-ermine.jpg"))
      (and buffer-file-name
           (file-exists-p
            (concat
             (file-name-directory buffer-file-name)
             "lady-with-an-ermine.jpg"))
           (concat
            (file-name-directory buffer-file-name)
            "lady-with-an-ermine.jpg"))
      (let (( file-name
              (concat temporary-file-directory
                      "lady-with-an-ermine.jpg")))
        (url-copy-file
         "https://raw.github.com/sabof/magic-buffer/master/lady-with-an-ermine.jpg"
         file-name t)
        file-name)))

(defface mb-diff-terminal
  '(( ((type graphic))
      (:background "DarkRed"))

    ( ((class color)
       (min-colors 88))
      (:background "blue"))

    ( ((class color)
       (min-colors 88))
      (:background "green"))

    ( t (:background "gray")
        ))
  "a test face")

(defmacro mb-section (name &rest body)
  (declare (indent defun))
  `(let* (( cons (car (push (list (prog1 mb-counter
                                    (cl-incf mb-counter)))
                            mb-sections))))
     (setcdr cons (list ,name
                        ,(if (stringp (car body))
                             (pop body)
                             nil)
                        (lambda ()
                          ,@body)))))

(defun mb-insert-filled (string)
  (let ((beginning (point)))
    (insert string)
    (fill-region beginning (point))))

(defun mb-subsection-header (string)
  (insert "\n" (propertize string 'face 'info-title-4) "\n\n"))

(defun mb-comment (string)
  (mb-insert-filled (propertize string 'face 'font-lock-comment-face))
  (insert "\n"))

;; -----------------------------------------------------------------------------

(mb-section "Horizontal line"
  "The point-entered property prevents the point from staying on that location,
since that would change the color of the line."
  (insert (propertize
           "\n"
           'display `(space :align-to (- right (1)))
           'face '(:underline t)
           'point-entered (lambda (old new)
                            (forward-line
                             (if (< old new) 1 -1)))
           ))
  (insert "\n"))

;; -----------------------------------------------------------------------------

(mb-section "Differentiate displays"
  ;; (info "(elisp) Defining Faces")
  ;; (info "(elisp) Display Feature Testing")
  (mb-insert-filled
   (propertize "This text will have a different background, depending on \
the type of display (Graphical, tty, \"full color\" tty)."
               'face 'mb-diff-terminal))
  (insert "\n"))

;; -----------------------------------------------------------------------------

(mb-section "Differentiate windows"
  ;; (info "(elisp) Overlay Properties")
  (let (( text "This text will have a different background color in each \
  window it is displayed")
        (window-list (list 'window-list))
        (point-a (point))
        point-b)
    (insert text)
    (setq point-b (point))
    (add-hook 'window-configuration-change-hook
              (lambda (&rest ignore)
                (cl-dolist (win (get-buffer-window-list nil nil t))
                  (unless (assoc win (cdr window-list))
                    (let ((ov (make-overlay point-a point-b)))
                      (setcdr window-list (cl-acons win ov (cdr window-list)))
                      (overlay-put ov 'window win)
                      (overlay-put ov 'face
                                   `(:background
                                     ,(mb-random-hex-color))))
                    )))
              nil t)))

;; -----------------------------------------------------------------------------

(mb-section "Aligning fixed width text"
  "The alignment will persist on window resizing, unless the window is narrower
 than the text."
  ;; (info "(elisp) Pixel Specification")
  (let* (( text-lines (split-string "Lorem ipsum dolor sit amet
Sed bibendum
Curabitur lacinia pulvinar nibh
Nam euismod tellus id erat
Sed diam
Phasellus at dui in ligula mollis ultricies"
                                    "\n")))
    (mb-subsection-header "Center")
    (cl-dolist (text text-lines)
      (let ((spec `(space :align-to (- center ,(/ (length text) 2)))))
        (insert  (propertize text 'line-prefix
                             (propertize " " 'display spec))
                 "\n")))

    (mb-subsection-header "Right")
    (cl-dolist (text text-lines)
      (let ((spec `(space :align-to (- right ,(length text) (1)))))
        (insert  (propertize text 'line-prefix
                             (propertize " " 'display spec))
                 "\n"))))

  (mb-subsection-header "Display on both sides of the window")
  (let* (( text-left "LEFT --")
         ( text-right "-- RIGHT")
         ;; There is an off-by one bug. When word-wrap is enabled, the line will
         ;; break. That's why I substract one pixel in the end. This will show
         ;; up as a single empty character on terminals.
         ( spec `(space :align-to (- right ,(length text-right) (1)))))
    (insert text-left)
    (insert (propertize " " 'display spec))
    (insert text-right)
    ))

;; -----------------------------------------------------------------------------

(mb-section "Aligning variable width text"
  "Won't work should any of the text-lines be wider that the frame, at
 the moment of creation. Will also break, should the size of
 frame's text change. Generating the text properties is a lot slower
 than for fixed-width fonts. There might be a better way to do
 right alignement, using bidi text support."
  ;; (info "(elisp) Pixel Specification")
  (let (( paragraphs "Lorem ipsum dolor
Pellentesque dapibus ligula
Proin neque massa, eget, lacus
Curabitur vulputate vestibulum lorem"))
    (mb-subsection-header "Center")
    (cl-loop for text in (split-string paragraphs "\n")
             for height = 2.0 then (- height 0.4)
             do (let (( ori-point (point))
                      ( face-spec  `(:inherit variable-pitch :height ,height)))
                  (insert (propertize text 'face face-spec))
                  ;; (goto-char ori-point)
                  (mb-center-line-variable-width)
                  (insert "\n")
                  ))
    (mb-subsection-header "Right")
    (cl-loop for text in (split-string paragraphs "\n")
             for height = 1.0 then (+ height 0.4)
             do (let (( ori-point (point))
                      ( face-spec  `(:inherit variable-pitch :height ,height)))
                  (insert (propertize text 'face face-spec))
                  ;; (goto-char ori-point)
                  (mb-flush-line-right-variable-width)
                  (insert "\n")
                  ))
    ))

;; -----------------------------------------------------------------------------

(mb-section "Extra leading"
  "The line-height property only has effect when applied to newline characters."
  (insert (propertize "Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
Integer placerat tristique nisl.
Aenean in sem ac leo mollis blandit.
Nunc eleifend leo vitae magna.
"
                      'line-height 1.5
                      )))
;; -----------------------------------------------------------------------------

(mb-section "Utf-8 tables"
  "Some fonts don't support box characters well, for example the
widths might be different. For those cases an ASCII fallback is
provided. If you know which widely used fonts apart from
\"DejaVu Sans Mono\" render correctly, please let me know.

Spaces might appear between characters, especially with smaller font sizes.

A table of unicode box characters can be found in the source code."

  ;; ─ ━ │ ┃ ┄ ┅ ┆ ┇ ┈ ┉ ┊ ┋ ┌ ┍ ┎ ┏

  ;; ┐ ┑ ┒ ┓ └ ┕ ┖ ┗ ┘ ┙ ┚ ┛ ├ ┝ ┞ ┟

  ;; ┠ ┡ ┢ ┣ ┤ ┥ ┦ ┧ ┨ ┩ ┪ ┫ ┬ ┭ ┮ ┯

  ;; ┰ ┱ ┲ ┳ ┴ ┵ ┶ ┷ ┸ ┹ ┺ ┻ ┼ ┽ ┾ ┿

  ;; ╀ ╁ ╂ ╃ ╄ ╅ ╆ ╇ ╈ ╉ ╊ ╋ ╌ ╍ ╎ ╏

  ;; ═ ║ ╒ ╓ ╔ ╕ ╖ ╗ ╘ ╙ ╚ ╛ ╜ ╝ ╞ ╟

  ;; ╠ ╡ ╢ ╣ ╤ ╥ ╦ ╧ ╨ ╩ ╪ ╫ ╬ ╭ ╮ ╯

  ;; ╰ ╱ ╲ ╳ ╴ ╵ ╶ ╷ ╸ ╹ ╺ ╻ ╼ ╽ ╾ ╿

  ;; Taken from https://en.wikipedia.org/wiki/Box_Drawing_(Unicode_block)

  (let ((table1 (substring "
╔══════╤══════╗
║ text │ text ║
╟──────┼──────╢
║ text │ text ║
╚══════╧══════╝
"
                           1))
        (table2 (substring "
╭──────┰──────╮
│ text ┃ text │
┝━━━━━━╋━━━━━━┥
│ text ┃ text │
╰──────┸──────╯
"
                           1)))

    ;; In an application, especially one that where the content changes
    ;; frequently, it would probably be better to determine whether all used
    ;; table characters have equal width with letters once, and then use them or
    ;; ASCII accoringly. This would be noticably faster.

    (mb-table-insert table1)
    (mb-table-insert table2)
    ))

;; -----------------------------------------------------------------------------

(mb-section "Quoted paragraph"
  "The red line is drawn using text-properties, so the text can
be copy-pasted with without extra spaces."
  (let (( prefix (concat " "
                         (propertize " "
                                     'display '(space :width (4))
                                     'face '(:background "DarkRed"))
                         " ")))
    (mb-insert-filled
     (propertize "Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Nunc
porta vulputate tellus. Proin quam nisl, tincidunt et, mattis eget, convallis
nec, purus. Nullam tempus. Pellentesque tristique imperdiet tortor. Lorem ipsum
dolor sit amet, consectetuer adipiscing elit."
                 'wrap-prefix prefix
                 'line-prefix prefix
                 'face 'italic))
    ))

;; -----------------------------------------------------------------------------

(mb-section "Fringe indicators"
  "fringe-indicator-alist contains the default indicators. The easiest way to
make new ones is to use an external package called `fringe-helper'."
  ;; (info "(elisp) Fringe Indicators")
  (let (( insert-fringe-bitmap
          (lambda (symbol-name)
            (insert (propertize " " 'display
                                `((left-fringe ,symbol-name font-lock-comment-face)
                                  (right-fringe ,symbol-name font-lock-comment-face)))))))
    (cl-loop for pair in fringe-indicator-alist
             for iter = 0 then (1+ iter)
             do
             (unless (zerop iter)
               (insert "\n"))
             (insert (propertize (concat "* " (symbol-name (car pair)))
                                 'face 'info-title-4)
                     "\n")
             (if (symbolp (cdr pair))
                 (progn
                   (funcall insert-fringe-bitmap (cdr pair))
                   (insert (concat "  " (symbol-name (cdr pair))) "\n"))
                 (cl-dolist (bitmap (cdr pair))
                   (progn
                     (funcall insert-fringe-bitmap bitmap)
                     (insert (concat "  " (symbol-name bitmap)) "\n"))))
             )))

;; -----------------------------------------------------------------------------

(mb-section "Pointer shapes"
  "Hover with your mouse over the labels to change the pointer.
For some reason doesn't work when my .emacs is loaded."
  ;; (info "(elisp) Pointer Shape")
  (insert (propertize "text"
                      'pointer 'text
                      'face '(:background "Purple"))
          "\n\n"
          (propertize "arrow"
                      'pointer 'arrow
                      'face '(:background "Purple"))
          "\n\n"
          (propertize "hand"
                      'pointer 'hand
                      'face '(:background "Purple"))
          "\n\n"
          (propertize "vdrag"
                      'pointer 'vdrag
                      'face '(:background "Purple"))
          "\n\n"
          (propertize "hdrag"
                      'pointer 'hdrag
                      'face '(:background "Purple"))
          "\n\n"
          (propertize "modeline"
                      'pointer 'modeline
                      'face '(:background "Purple"))
          "\n\n"
          (propertize "hourglass"
                      'pointer 'hourglass
                      'face '(:background "Purple"))
          "\n\n"))

;; -----------------------------------------------------------------------------

(mb-section "Images"
  "Scrolling generally misbehaves with images. Presumably `insert-sliced-image'
was made to improve the situation, but it makes things worse on occasion."

  (let (( image-size
          ;; For terminal displays
          (ignore-errors
            (image-size `(image :type jpeg :file ,mb-expamle-image)))))
    (mb-subsection-header "Simple case")
    (insert-image `(image :type jpeg :file ,mb-expamle-image) "[you should be seeing an image]")
    (insert "\n\n")
    (when image-size
      (mb-subsection-header "Using `insert-sliced-image'")
      (insert-sliced-image `(image :type jpeg :file ,mb-expamle-image) "[you should be seeing an image]"
                           nil (car image-size))
      (insert "\n"))
    (mb-subsection-header "You can also crop images, or add a number of effects")
    (insert-image `(image :type jpeg :file ,mb-expamle-image) "[you should be seeing an image]" nil
                  '(60 25 100 150))
    (insert " ")
    (insert-image `(image :type jpeg :file ,mb-expamle-image :conversion disabled)
                  "[you should be seeing an image]" nil
                  '(60 25 100 150))))

(mb-section "SVG"
  "More complex effects can be achieved through SVG"
  (mb-subsection-header "Resizing an masking")
  ;; The link probably won't work on winodws
  (let ((data (format "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"109\" height=\"150\">
          <defs>
          <clipPath id=\"circularPath\" clipPathUnits=\"objectBoundingBox\">
          <circle cx=\"0.5\" cy=\"0.5\" r=\"0.5\"/>
          </clipPath>
          </defs>
          <image id=\"image\" width=\"109\" height=\"150\" style=\"clip-path: url(#circularPath);\"
          xlink:href=\"file://%s\" />
          </svg>"
                      mb-expamle-image)))
    (insert-image `(image :type svg :data ,data)
                  ))
  (insert "\n\n")
  (mb-subsection-header "Subjecting online images to multiplication and skewing")
  (let ((data "<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"400\" height=\"260\">
  <image id=\"image\" x=\"10\" y=\"10\" width=\"100\" height=\"45\" transform=\"skewX(10)\"
  xlink:href=\"http://www.gnu.org/graphics/behroze/behroze-gnu-button1.png\" />
  <image id=\"image2\" x=\"50\" y=\"35\" width=\"200\" height=\"90\" transform=\"skewX(-10)\"
  xlink:href=\"http://www.gnu.org/graphics/behroze/behroze-gnu-button1.png\" />
  <image id=\"image2\" x=\"50\" y=\"100\" width=\"300\" height=\"135\" transform=\"skewX(10)\"
  xlink:href=\"http://www.gnu.org/graphics/behroze/behroze-gnu-button1.png\" />
  </svg>"
              ))
    (insert-image `(image :type svg :data ,data))))

;; -----------------------------------------------------------------------------

;; (mb-section "Widgets"
;;   ())

;; -----------------------------------------------------------------------------

;; (mb-section "Colors")

;; -----------------------------------------------------------------------------
(defun magic-buffer (&rest ignore)
  (interactive)
  (let ((buf (get-buffer-create "*magic-buffer*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (fundamental-mode)
        (progn
          (setq truncate-lines nil)
          (setq line-spacing 0)
          (setq left-fringe-width 8
                right-fringe-width 8))
        (setq-local revert-buffer-function 'magic-buffer)
        (insert (propertize "Magic buffer"
                            'face 'info-title-2)
                "\n")
        (mb-insert-filled
         (propertize "If you want to see the source, do `M-x find-function magic-buffer'"
                     'face 'font-lock-comment-face))
        (insert "\n\n")
        (cl-dolist (section (cl-sort (cl-copy-list mb-sections) '< :key 'car))
          (cl-destructuring-bind (number name doc function) section
            (insert "\n\n")
            (insert (propertize (format "%s. %s:\n" number name)
                                'face 'info-title-3))
            (if doc
                (mb-insert-filled
                 (propertize (format "%s\n\n" doc)
                             'face 'font-lock-comment-face))
                (insert "\n"))
            (funcall function)
            (goto-char (point-max))
            (unless (zerop (current-column))
              (insert "\n"))
            (insert "\n"))))
      (unless view-mode
        (view-mode 1))
      (goto-char (point-min)))
    (switch-to-buffer buf)))

(provide 'magic-buffer)
;;; magic-buffer.el ends here
