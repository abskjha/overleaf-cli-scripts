# overleaf-cli-scripts

Shell scripts to create Overleaf projects and invite collaborators from the command line.

| Script | What it does |
|---|---|
| `set-overleaf-cookie.sh` | Safely paste your Overleaf session cookie, check that it works, and store it (optionally on a remote machine) |
| `overleaf-new.sh` | Create a project, optionally tag it, and invite collaborators by email |

> **Disclaimer.** This project is not affiliated with, endorsed by, or supported by Overleaf or Digital Science. "Overleaf" is a trademark of its owner and is used here only to describe what the scripts work with.
>
> Overleaf has no public API for creating projects or sending invites. These scripts use undocumented internal web endpoints, which may change without notice. **Overleaf's Terms of Service and Acceptable Use Policy restrict automated access and access through non-public interfaces**, so using these scripts may violate those terms and could lead to restrictions on your account. Read the current terms at [overleaf.com/legal](https://www.overleaf.com/legal) and decide for yourself before using them. You use these scripts entirely at your own risk; they are provided as is, without warranty of any kind.

## Requirements

- `bash`, `curl`, and `python3` (used only for safe JSON handling)
- macOS or Linux
- An Overleaf account. The number of collaborators per project depends on your plan.

## Setup

```bash
git clone https://github.com/<username>/overleaf-cli-scripts.git
cd overleaf-cli-scripts
chmod +x set-overleaf-cookie.sh overleaf-new.sh
```

### 1. Get your session cookie

1. Log in at [overleaf.com](https://www.overleaf.com).
2. Open DevTools (F12, or Cmd+Option+I on Mac) → **Application** (Chrome/Edge) or **Storage** (Firefox) → **Cookies** → `https://www.overleaf.com`.
3. Copy the **Value** of the `overleaf_session2` cookie.

The cookie is HttpOnly, so `document.cookie` in the console won't show it; use the Cookies panel.

### 2. Store it

```bash
./set-overleaf-cookie.sh                         # saves to ~/.overleaf-session.env
REMOTE=user@host ./set-overleaf-cookie.sh        # also copies it to another machine over SSH
```

Paste the value at the hidden prompt and press Enter. The script:

- never shows the value on screen, in shell history, or on any process's command line
- checks the cookie with Overleaf first and saves nothing if it's rejected
- writes the file with owner-only permissions (`600`), replacing it in one step
- tolerates stray spaces, quotes, or a pasted `overleaf_session2=` prefix

| Variable | Default | Meaning |
|---|---|---|
| `ENV_FILE` | `~/.overleaf-session.env` | Local file to write |
| `REMOTE` | – | `user@host` to also copy the cookie to |
| `REMOTE_FILE` | `.overleaf-session.env` | File on the remote machine, relative to its home folder |
| `OVERLEAF_BASE_URL` | `https://www.overleaf.com` | Overleaf instance (for self-hosted) |

Run it again whenever the session expires.

## Creating projects

```bash
./overleaf-new.sh "Project name" [email ...]
```

Examples:

```bash
# Blank project, two editors
./overleaf-new.sh "My paper" user1@example.com user2@example.com

# Viewers instead of editors
ROLE=readOnly ./overleaf-new.sh "My paper" user3@example.com

# Start from Overleaf's example document and add a tag
TEMPLATE=example TAG="Drafts" ./overleaf-new.sh "My paper" user1@example.com
```

Output:

```
Created: "My paper" → https://www.overleaf.com/project/<id>
Invited (readAndWrite): user1@example.com
Invited (readAndWrite): user2@example.com
```

| Variable | Default | Meaning |
|---|---|---|
| `ROLE` | `readAndWrite` | `readAndWrite` = Editor, `readOnly` = Viewer. Applies to everyone invited in that run |
| `TEMPLATE` | `none` | `none` = blank project, `example` = Overleaf's sample document |
| `TAG` | – | Add the project to this tag, creating it if needed (case-insensitive match) |
| `ENV_FILE` | `~/.overleaf-session.env` | Where to read the cookie from (skipped if `OVERLEAF_SESSION` is already set) |
| `OVERLEAF_BASE_URL` | `https://www.overleaf.com` | Overleaf instance (for self-hosted) |

Notes:

- **Tags are personal.** They organize the dashboard of the account running the script; collaborators don't see them.
- **Reviewer role:** invite someone as a reviewer once in the web interface with DevTools → Network open to see the value Overleaf sends, then pass it as `ROLE`.
- Invitees receive an email from Overleaf and must accept it while logged in to their Overleaf account.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Project created; all tagging and invites succeeded |
| `1` | Usage error or missing cookie, **or** project created but a tag or invite failed (see stderr) |
| `2` | Session invalid or expired: run `set-overleaf-cookie.sh` again |
| `3` | CSRF token not found (Overleaf's page may have changed) |
| `4` | Project creation failed |

### Checking the session

```bash
set -a; source ~/.overleaf-session.env; set +a
curl -s -o /dev/null -w "%{http_code}\n" -b "overleaf_session2=$OVERLEAF_SESSION" https://www.overleaf.com/project
```

`200` means the session is valid.

## Security

The `overleaf_session2` cookie gives **full access to the Overleaf account**. Treat it like a password:

- Never commit the `.env` file (it's in `.gitignore`), share the cookie, or log it.
- If you think it leaked, log out of that Overleaf session to invalidate it, then store a fresh cookie.
- `overleaf-new.sh` passes the cookie to `curl` on its command line, which other users on the same machine could briefly see in the process list. On a shared machine, run it under a dedicated user account.
- If you call `overleaf-new.sh` from another program, pass arguments as an array (not a shell string built from input) and validate the emails you pass in.

## How it works

Both scripts make the same requests the Overleaf website makes:

| Step | Request |
|---|---|
| Check session, read CSRF token | `GET /project` (token from the `ol-csrfToken` meta tag) |
| Create project | `POST /project/new` with `{"projectName", "template"}` |
| List / create tags | `GET /tag`, `POST /tag` with `{"name"}` |
| Tag project | `POST /tag/<tag-id>/project/<project-id>` |
| Invite | `POST /project/<project-id>/invite` with `{"email", "privileges"}` |

State-changing requests send the session cookie plus an `X-Csrf-Token` header.

## Troubleshooting

- **`Session invalid (HTTP 302)`**: the cookie expired or was copied incompletely. Run `set-overleaf-cookie.sh` again.
- **A step fails with an unexpected response:** Overleaf may have changed an endpoint. Do the same action in the web interface with DevTools → Network open and compare the request's URL, headers, and body with the table above.
- **An invite fails on a project that already has collaborators:** you may have hit your plan's per-project collaborator limit.
- **No invite email arrives:** check the address and spam folder, or use **Resend** in the project's Share window.

## License

See `LICENSE`. Provided as is, without warranty of any kind.
