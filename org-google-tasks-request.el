;;; -*- lexical-binding: t -*-

;; call

(require 'ht)
(require 'oauth2)
(require 'el-mock)

(defcustom my/gtasks-client-secret-json ""
  "JSON file location to client secret."
  :type '(string)
  :group 'my)

;;; GTasks API access utilities.
(defun my/token ()
  (let* ((secret (json-read-file my/gtasks-client-secret-json))
       (installed (cdr (assq 'installed secret)))
       (client-id (cdr (assq 'client_id installed)))
       (client-secret (cdr (assq 'client_secret installed)))
       (auth-url "https://accounts.google.com/o/oauth2/auth")
       (token-url "https://www.googleapis.com/oauth2/v3/token")
       (scope "https://www.googleapis.com/auth/tasks"))
    (oauth2-auth-and-store auth-url token-url scope client-id client-secret)))

(defun my/parse-http-response (buffer)
  "This function parses a buffer as an HTTP response. See RFC 2616.

This returns a plist of :status, :reason, :header and :body."
  (let (status reason message header body)
      ;; decode coding
      (with-current-buffer buffer
        ;; parse RFC2616
        (goto-char (point-min))
        ;; status-line
        (looking-at "^HTTP/[^ ]+ \\([0-9]+\\) ?\\(.*\\)$")
        (setq status (string-to-number (match-string 1)))
        (setq reason (match-string 2))
        (forward-line)
        ;; headers
        (while (not (looking-at "^$"))
          (looking-at "^\\([^:]+\\): \\(.*\\)$")
          (push (cons (match-string 1) (match-string 2)) header)
          (forward-line))
        ;; CRLF
        (forward-line)
        ;; message-body
        (setq body (buffer-substring (point) (point-max)))
        ;; return results
        (list :status status :reason reason :header header :body body))))

;;; Macro for Google Tasks API.
(defmacro my/api (url &optional request-method request-data)
  "This is a macro for REST API request.
REQUEST-DATA is any emacs lisp object that json-serialize understands."
  `(let* ((response-buffer (oauth2-url-retrieve-synchronously
			 (my/token)
			 ,url
			 ,request-method
			 (if ,request-data
			     (encode-coding-string (json-serialize ,request-data) 'utf-8))))
	  (response (my/parse-http-response response-buffer))
	  (body (decode-coding-string (plist-get response :body) 'utf-8)))
     (json-parse-string body)))

;;; Google Tasks APIs for tasklists.
(defun my/api-tasklists-list ()
  "Creates a new task list and adds it to the authenticated user's task lists.

See URL https://developers.google.com/tasks/reference/rest/v1/tasklists/list"
  (my/api "https://tasks.googleapis.com/tasks/v1/users/@me/lists"
	  "GET"))

(defun my/api-tasklists-insert (tasklist)
  "Creates a new task list and adds it to the authenticated user's task lists.

TASKLIST is a tasklist object. This returns response in JSON strings.
See URL https://developers.google.com/tasks/reference/rest/v1/tasklists/insert

Usage:
  (my/api-tasklists-insert '(:title \"My Tasklist\"))
  (my/api-tasklists-insert '((title . \"My Tasklist\")))
"
  (my/api "https://tasks.googleapis.com/tasks/v1/users/@me/lists"
	  "POST"
	  tasklist))

;; (my/api-tasklists-list)
;; (my/api-tasklists-insert '(:title "はひふへほ"))
;; (my/api-tasklists-insert '((title . "はひふ")))
;; (my/api "https://tasks.googleapis.com/tasks/v1/users/@me/lists" "POST" '(:title "さしすせそ"))

(defun my/api-tasks-list (tasklist)
  "Returns all tasks in the specified task list.

See URL https://developers.google.com/tasks/reference/rest/v1/tasks/list"
  (my/api (format
	   "https://tasks.googleapis.com/tasks/v1/lists/%s/tasks" tasklist)
	  "GET"))

;;; Utils
(defun my/create-id-table ()
  "Create a hash table for looking up tasklist or task items by the id."
  (let* ((table (ht-create))
	 (tasklists (my/api-tasklists-list))
	 (tasklists-items (ht-get tasklists "items")))
    (dolist (tasklist (cl-coerce tasklists-items 'list))
      (let* ((tasklist-id (ht-get tasklist "id")))
		;; Set the tasklist to the table.
		(ht-set! table tasklist-id tasklist)
		;; Get the tasks under the tasklist.
		(let* ((tasks (my/api-tasks-list tasklist-id))
		       (tasks-items (ht-get tasks "items")))
		  (message "tasks:\n%s\nend:" tasks)
		  (dolist (task (cl-coerce tasks-items 'list))
		    (let ((task-id (ht-get task "id")))
		       ;; Set the task to the table.
		       (ht-set! table task-id task))))))
    table))

(ert-deftest my/create-id-table-test ()
  (with-mock
    (stub my/api-tasklists-list =>
	  #s(hash-table test equal data
                        ("kind" "tasks#taskLists" "etag" "\"MjA0MzIwOTcyNw\"" "items" [#s(hash-table test equal data ("kind" "tasks#taskList" "id" "MDc1MzA1NTQ1OTYxODU5MTEwMTg6MDow" "etag" "\"LTE1Nzc5OTMyNDA\"" "title" "Tasklist" "updated" "2022-03-19T11:30:48.118Z" "selfLink" "https://www.googleapis.com/tasks/v1/users/@me/lists/MDc1MzA1NTQ1OTYxODU5MTEwMTg6MDow")) #s(hash-table test equal data ("kind" "tasks#taskList" "id" "MkhZNnRBVGE4eFk2UW1sdw" "etag" "\"LTE4NTg3MTY1ODQ\"" "title" "タスク" "updated" "2022-03-16T05:32:05.318Z" "selfLink" "https://www.googleapis.com/tasks/v1/users/@me/lists/MkhZNnRBVGE4eFk2UW1sdw")) #s(hash-table test equal data ("kind" "tasks#taskList" "id" "M21GQnJNQm84YXdCWVZRcw" "etag" "\"LTE1NzA3ODUwNzE\"" "title" "はひふへほ" "updated" "2022-03-19T13:30:56.845Z" "selfLink" "https://www.googleapis.com/tasks/v1/users/@me/lists/M21GQnJNQm84YXdCWVZRcw"))])))
    (stub my/api-tasks-list =>
	  #s(hash-table test equal data
			("kind" "tasks#tasks" "etag" "\"LTE1Nzc5OTMyNDA\"" "items" [#s(hash-table size 9 test equal rehash-size 1.5 rehash-threshold 0.8125 data ("kind" "tasks#task" "id" "YWlqV0hsRV9lYVlQdkx5MQ" "etag" "\"LTIxMDQ5NTgyODI\"" "title" "Task2 with note" "updated" "2022-03-13T09:08:03.000Z" "selfLink" "https://www.googleapis.com/tasks/v1/lists/MDc1MzA1NTQ1OTYxODU5MTEwMTg6MDow/tasks/YWlqV0hsRV9lYVlQdkx5MQ" "position" "00000000000000000001" "notes" "This is note string.
Hello World!" "status" "needsAction")) #s(hash-table test equal data ("kind" "tasks#task" "id" "dlAzdXRlWDh2Z0dsck4xcQ" "etag" "\"MjA3MjIxMDY4Nw\"" "title" "Task 7 as sub-task" "updated" "2022-03-12T00:24:45.000Z" "selfLink" "https://www.googleapis.com/tasks/v1/lists/MDc1MzA1NTQ1OTYxODU5MTEwMTg6MDow/tasks/dlAzdXRlWDh2Z0dsck4xcQ" "parent" "aEQ1TjhNOGRiS3p6VmR4dw" "position" "00000000000000000000" "status" "needsAction")) #s(hash-table test equal data ("kind" "tasks#task" "id" "aEQ1TjhNOGRiS3p6VmR4dw" "etag" "\"MjA3MjE3NDc0OA\"" "title" "Task6 as parent" "updated" "2022-03-12T00:24:09.000Z" "selfLink" "https://www.googleapis.com/tasks/v1/lists/MDc1MzA1NTQ1OTYxODU5MTEwMTg6MDow/tasks/aEQ1TjhNOGRiS3p6VmR4dw" "position" "00000000000000000005" "status" "needsAction")) #s(hash-table test equal data ("kind" "tasks#task" "id" "Y1hxLXB0ZHJZb0x0Z3I0Mw" "etag" "\"MjA3MjE1ODc0MQ\"" "title" "Task5 with date time" "updated" "2022-03-12T00:23:53.000Z" "selfLink" "https://www.googleapis.com/tasks/v1/lists/MDc1MzA1NTQ1OTYxODU5MTEwMTg6MDow/tasks/Y1hxLXB0ZHJZb0x0Z3I0Mw" "position" "00000000000000000004" "status" "needsAction" "due" "2022-03-15T00:00:00.000Z")) #s(hash-table test equal data ("kind" "tasks#task" "id" "aUhGRlpRMXhqbmZrN1JsQQ" "etag" "\"MjA3MjE0NDc4NQ\"" "title" "Task4 with date (repeat)" "updated" "2022-03-12T00:23:38.000Z" "selfLink" "https://www.googleapis.com/tasks/v1/lists/MDc1MzA1NTQ1OTYxODU5MTEwMTg6MDow/tasks/aUhGRlpRMXhqbmZrN1JsQQ" "position" "00000000000000000003" "status" "needsAction" "due" "2022-03-15T00:00:00.000Z")) #s(hash-table test equal data ("kind" "tasks#task" "id" "TDlONFk0TThJT1VGb0h6RQ" "etag" "\"MjA3MjA4NTAzMA\"" "title" "Tasks3 with date" "updated" "2022-03-12T00:22:39.000Z" "selfLink" "https://www.googleapis.com/tasks/v1/lists/MDc1MzA1NTQ1OTYxODU5MTEwMTg6MDow/tasks/TDlONFk0TThJT1VGb0h6RQ" "position" "00000000000000000002" "status" "needsAction" "due" "2022-03-31T00:00:00.000Z")) #s(hash-table test equal data ("kind" "tasks#task" "id" "cF9ORW8yYWgyNTVES1dIbg" "etag" "\"MjA3MjA0NDc2MQ\"" "title" "Task1" "updated" "2022-03-12T00:21:59.000Z" "selfLink" "https://www.googleapis.com/tasks/v1/lists/MDc1MzA1NTQ1OTYxODU5MTEwMTg6MDow/tasks/cF9ORW8yYWgyNTVES1dIbg" "position" "00000000000000000000" "status" "needsAction"))])))
    (let ((result))
      (setq result (ht-keys (my/create-id-table)))
      (should (equal
	       (format "%s" result)
	       "(M21GQnJNQm84YXdCWVZRcw MkhZNnRBVGE4eFk2UW1sdw cF9ORW8yYWgyNTVES1dIbg TDlONFk0TThJT1VGb0h6RQ aUhGRlpRMXhqbmZrN1JsQQ Y1hxLXB0ZHJZb0x0Z3I0Mw aEQ1TjhNOGRiS3p6VmR4dw dlAzdXRlWDh2Z0dsck4xcQ YWlqV0hsRV9lYVlQdkx5MQ MDc1MzA1NTQ1OTYxODU5MTEwMTg6MDow)")))))
