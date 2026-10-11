# SSH setup for the SiA Shiny server

The live Shiny server is only reachable from inside the VU network. Upload needs two things: a connection to that network, and a key-based SSH login (the skill never types passwords).

## 1. Reach the server

Connect to the VU network or the VU VPN. If the check says "not reachable", this is the cause. Ask VU IT for VPN access if you do not have it.

## 2. Check that SSH exists

In a terminal: `ssh -V`. Windows 10 and 11 ship an OpenSSH client. If the command is missing, enable "OpenSSH Client" under Settings > Apps > Optional features.

## 3. Make a key (once per computer)

`ssh-keygen -t ed25519`

Accept the default location. The skill cannot type a passphrase, so either leave the passphrase empty, or load the key into the SSH agent before running the skill (`ssh-add`; on Windows start the "OpenSSH Authentication Agent" service first). This makes two files in `~/.ssh/`: `id_ed25519` (private, never share) and `id_ed25519.pub` (public).

## 4. Get the public key onto the server

Send the content of `id_ed25519.pub` (one line) to the server admin and ask them to add it to your account's `~/.ssh/authorized_keys`. Never send the private file.

If you can already log in with a password, you can add it yourself: log in with `ssh user@host`, then append the line to `~/.ssh/authorized_keys` on the server.

## 5. Test

`ssh user@host` should log you in without any password question. Then run the skill's check again.

## 6. Find the remote app folder and the restart command

Ask the server admin three things:

- Which folder holds the production app? It contains `app.R`, `global.R`, `data/` and `www/`.
- Which command restarts Shiny Server? `global.R` loads the files once per app process, so a restart is needed. Typically `sudo systemctl restart shiny-server`, but confirm.
- Which command reloads nginx (the web server in front of Shiny Server)? Typically `sudo nginx -t && sudo systemctl reload nginx`, but confirm.

The skill logs in without a password prompt, so the admin must also allow your account to run those two commands with `sudo` without asking for a password. Ask for exactly that, nothing broader.

Your account also needs write rights on the production app folder and on its `data/` and `www/` folders and files (Shiny Server often runs apps as its own `shiny` user, so these may belong to someone else). The skill's check reports "WRITE_FAIL" when they are missing.

Put the answers in `~/.sia_wd_deploy.conf` (template: `server_config.template.txt`).
