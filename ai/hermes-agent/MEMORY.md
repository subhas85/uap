UAP runbook lives at ~/uap/ — the reproducible runbook for the adminbox setup; ~/uap/README.md is the canonical reference. Every system-level change to UAP (install a package, edit /etc or ~/.config, change a service, tweak i3 / xrdp / Plymouth / GTK) must be mirrored into ~/uap/configs/ or ~/uap/scripts/ and reflected in ~/uap/README.md. Live system + runbook stay in lockstep.
§
Workspace hub is ~/workspace/ — a router CLAUDE.md plus symlinks ops/ → ~/ops, dev/ → ~/dev, uap/ → ~/uap, dashboard/ → ~/dashboard. This is the gateway's WorkingDirectory, so ~/workspace/CLAUDE.md auto-loads as project context each Telegram session.
§
Shared knowledge with Claude Code lives at ~/.claude/projects/-home-subhas/memory/. Start with MEMORY.md (the index) and follow its links. The rest of ~/.claude/ holds transcripts and auth tokens — out of scope; don't browse without explicit ask.
§
Other out-of-scope paths: ~/.ssh, ~/.gnupg, ~/.aws, ~/.azure, ~/.kube, ~/.docker/config.json, ~/.config/Microsoft, ~/.config/google-chrome, ~/snap/firefox, ~/.local/share/keyrings, browser profiles.
§
Git commit rule: no `Co-Authored-By: Claude ...` trailer. Ever. Clean human-authored history. Signed-off-by / Reviewed-by are fine.
§
Doc placement (ops vs repo): if a doc makes sense without the code checked out, it belongs in ~/ops/. If it references specific file paths or code in a repo, it belongs in that repo (README.md, docs/).
§
Screenshots: headless Chromium, not scrot — UAP is SSH-only over xrdp. Pattern: `chromium-browser --headless --disable-gpu --no-sandbox --screenshot=PATH --window-size=1920,1080 --virtual-time-budget=20000 --disk-cache-dir=/tmp/chrome-cache-N URL`. Fresh --disk-cache-dir each time.
