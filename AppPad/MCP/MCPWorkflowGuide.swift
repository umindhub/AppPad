import Foundation

// Authoring rules served by the `workflow_guide` tool (read by the model, plain Markdown).
// Keep in sync with WorkflowModel / WorkflowRunner / SeatbeltProfile.
enum MCPWorkflowGuide {
    static let text = """
    # Writing AppPad workflows

    A workflow is one JSON object (format 1.0). Save it with `save_workflows`; the user reviews \
    and approves every save in an AppPad dialog. To change an existing workflow, read it with \
    `export_workflows`, edit it, raise `version`, and save it again with the same `id`.

    ## Top-level fields

    | Field | Type | Notes |
    |---|---|---|
    | `formatVersion` | string | Always `"1.0"`. |
    | `id` | string | **Required.** Reverse-DNS, lowercase, at least two segments of `[a-z0-9-]`, e.g. `com.charles.diskfree`. The same id replaces the installed workflow. Never use the built-in ids (`com.youmindhub.*` from the built-in group). |
    | `version` | string | `"1.0"`, `"1.1"`, … A replacement must have a HIGHER version than the installed one. |
    | `name` | string | **Required.** English display name. |
    | `description` | string | English, one sentence; shown in the panel preview. |
    | `localizations` | object | Optional per language: `{"zh-Hans": {"name": "…", "description": "…", "argumentHint": "…", "keywords": ["…"]}}`. Languages: de, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant. Missing fields fall back to English. |
    | `group` | string | Optional free-text group shown in Settings. Not `"system"` (reserved). |
    | `keywords` | [string] | Lowercase, no spaces. What the user types in the panel; an exact keyword ranks first. The first one appears in usage hints. |
    | `argument` | string | `"none"` (default), `"optional"` or `"required"`: whether the panel text after the first space is passed in. |
    | `argumentType` | string | How the argument is parsed (see below). Default `"text"`. |
    | `argumentHint` | string | Short English placeholder, e.g. `"duration"`, `"keywords"`. |
    | `symbol` | string | SF Symbol for the generated icon, e.g. `"terminal"`, `"globe"`. |
    | `iconURL` | string | Optional https image (512×512 PNG); downloaded once. Prefer `symbol`. |
    | `successNotice` | string | After a panel run: `"none"` (default, silent), `"output"` (notification with the final output) or `"custom"` (`successMessage`, `{{output}}` replaced). |
    | `failureNotice` | string | `"error"` (default) or `"custom"` (`failureMessage`, `{{error}}` replaced). |
    | `copyOutput` | bool | Also copy the final output to the clipboard (panel runs). |
    | `confirm` | bool | Ask "Run …?" before every run. Use for destructive actions only. |
    | `steps` | [step] | **Required**, at least one; run in order. |
    | `permissions` | object | What the steps may do (see Permissions). |

    ## Argument types (what the FIRST step receives as input)

    | `argumentType` | User types | Step input |
    |---|---|---|
    | `text` | anything | as typed |
    | `duration` | `10` (minutes), `90s`, `1h30m`, `1:30` | seconds, e.g. `5400` (under 24 h) |
    | `time` | `7:30`, `19:30`, `7pm`, optionally `+ label` | `HH:mm`, or `HH:mm` newline `label` |
    | `number` | an integer | the integer |
    | `percent` | `0`–`100` (clamped) | the integer |
    | `reminder` | `tomorrow 3pm Call Mom !! @Work` | a JSON reminder for the `createReminder` action |

    ## Data flow

    Each step's output becomes the next step's input; the last step's output is the workflow \
    result. A step fails on a non-zero exit, timeout, non-2xx HTTP status or denied permission, \
    and the run stops there. Every step has `timeout` (seconds, default 60).

    ## Step kinds (`"kind"`)

    ### `shell`
    `{"kind": "shell", "script": "…", "timeout": 60}`
    - Runs as `/bin/zsh -f -c <script>` inside a sandbox; rc files are NOT loaded, but `PATH` is \
    the user's login PATH (Homebrew tools work).
    - Input arrives on **stdin** and in `$APPPAD_INPUT` (up to 64 KB). Output = stdout (trailing \
    newlines trimmed). stderr is shown only on failure.
    - Environment: `HOME`, `USER`, `PATH`, `LANG`, `APPPAD_WORKFLOW`, and `TMPDIR`, a per-run \
    scratch directory that is also the working directory and is deleted afterwards.

    ### `appleScript`
    `{"kind": "appleScript", "language": "appleScript" | "javaScript", "script": "…"}`
    - Runs with `osascript` in the same sandbox. Input is the first argument \
    (`on run argv` / `function run(argv)`) and stdin; the returned value is the output.
    - Implies the `systemServices` permission. To control an app, add its bundle id to \
    `permissions.appleEvents` (macOS also asks for Automation access once).

    ### `shortcut`
    `{"kind": "shortcut", "shortcutName": "My Shortcut", "shortcutInput": ""}`
    - Runs an Apple Shortcut by exact name. `shortcutInput` is a template: empty = the step \
    input; `{{input}}` is replaced, `\\n` becomes a newline. Output = the shortcut's text output.
    - The shortcut must already exist in the Shortcuts app.

    ### `http`
    `{"kind": "http", "http": {"method": "GET", "url": "https://api.example.com/x?q={{input}}", "headers": "Accept: application/json", "body": ""}}`
    - `method`: GET, POST, PUT, PATCH, DELETE. `headers`: one `Name: Value` per line. `body` is \
    sent for non-GET requests.
    - `{{input}}` is percent-encoded in the URL and inserted raw in headers and body.
    - `{{secret:NAME}}` inserts a Keychain secret (the user adds it in Settings › Workflows › \
    Secrets; never put tokens in the JSON). Declare each NAME in `permissions.secrets`.
    - The URL's host must be listed in `permissions.httpHosts`; redirects to other hosts are \
    blocked. Output = response body. No `network` permission needed.

    ### `builtin`
    `{"kind": "builtin", "builtin": "<action>"}` — AppPad's own actions:

    | Action | Input |
    |---|---|
    | `emptyTrash`, `sleepDisplays`, `sleepMac`, `toggleDarkMode`, `toggleMute`, `ejectDisks`, `toggleHiddenFiles`, `quitAllApps`, `copyIPAddress`, `generateUUID`, `shutDown`, `restart`, `addToClaudeDesktop`, `removeFromClaudeDesktop` | none |
    | `keepAwake` | seconds; empty or 0 = until stopped |
    | `setVolume` | 0–100 |
    | `quitApp` | app name (exact, then prefix) |
    | `openURL` | needs `"url"` on the step, e.g. `"https://www.google.com/search?q={{input}}"` (`{{input}}` percent-encoded) |
    | `createReminder` | from `argumentType: "reminder"`, or plain text |

    ## Permissions

    ```json
    "permissions": {
      "fileRead": ["~/Documents/Notes"], "fileWrite": ["~/Desktop"],
      "network": false, "systemServices": false,
      "appleEvents": ["com.apple.finder"],
      "httpHosts": ["api.github.com"], "secrets": ["GITHUB_TOKEN"]
    }
    ```
    - `shell` / `appleScript` run in a default-deny sandbox. They can always read system \
    locations (/usr, /bin, /System, /Library, /Applications, /opt/homebrew, /etc) and use \
    `TMPDIR`. Everything else must be declared:
      - `fileRead` / `fileWrite`: user folders (`~` allowed; write includes read).
      - `network`: outbound network for scripts (curl, git, gh…).
      - `systemServices`: `open`, `pbcopy`/`pbpaste`, launching apps, notifications.
      - `appleEvents`: bundle ids scripts may control.
    - `httpHosts` / `secrets`: for `http` steps. Shortcuts and built-in actions are permitted \
    per item automatically (the user is asked).
    - On the first run the user gets Allow Once / Always Allow / Don't Allow for undecided items. \
    Declare the minimum: the smaller the list, the easier the approval.

    ## Validation (save fails otherwise)

    - At least one step; no empty scripts; a shortcut name for `shortcut` steps; an http(s) URL \
    whose host is in `httpHosts` and every referenced secret in `secrets`; a `url` for `openURL`.

    ## Examples

    Shell, no permissions, no argument:
    ```json
    {"formatVersion": "1.0", "id": "com.example.diskfree", "version": "1.0",
     "name": "Disk Free Space", "description": "Show free space on the startup disk.",
     "keywords": ["df", "disk"], "symbol": "internaldrive", "successNotice": "output",
     "steps": [{"kind": "shell", "script": "df -h / | awk 'NR==2 {print $4 \\" free of \\" $2}'"}]}
    ```

    HTTP with a required argument and a secret:
    ```json
    {"formatVersion": "1.0", "id": "com.example.deploy", "version": "1.0",
     "name": "Run Deploy", "description": "Trigger the deploy GitHub Action for a branch.",
     "keywords": ["deploy"], "symbol": "paperplane", "argument": "required",
     "argumentType": "text", "argumentHint": "branch", "successNotice": "custom",
     "successMessage": "Deploy started",
     "steps": [{"kind": "http", "timeout": 30, "http": {"method": "POST",
       "url": "https://api.github.com/repos/OWNER/REPO/actions/workflows/deploy.yml/dispatches",
       "headers": "Authorization: Bearer {{secret:GITHUB_TOKEN}}\\nAccept: application/vnd.github+json",
       "body": "{\\"ref\\": \\"{{input}}\\"}"}}],
     "permissions": {"httpHosts": ["api.github.com"], "secrets": ["GITHUB_TOKEN"]}}
    ```

    Two steps (the shell output feeds the next step):
    ```json
    {"formatVersion": "1.0", "id": "com.example.searchclipboard", "version": "1.0",
     "name": "Search Clipboard", "keywords": ["sc"], "symbol": "magnifyingglass",
     "steps": [{"kind": "shell", "script": "pbpaste | head -c 200"},
               {"kind": "builtin", "builtin": "openURL", "url": "https://www.google.com/search?q={{input}}"}],
     "permissions": {"systemServices": true}}
    ```
    """
}
