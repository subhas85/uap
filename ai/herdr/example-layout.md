# Herdr workspace layout (example)

An example of how to organize a persistent Herdr session on a UAP box. The
**workspace → project** mapping is the durable design; **tabs** are one task each
and churn as work moves, so treat any tab list as a snapshot, not a fixed spec.

- Live, machine-restorable state lives in `~/.config/herdr/session.json` (volatile —
  pane and terminal ids change constantly; not worth tracking in git).
- Convention: **one workspace per project area**, **one tab per task/agent**, named
  for the work (not `1`/`2`). Rename placeholders with
  `herdr tab rename <tab_id> "<label>"`.

## Workspaces (project areas)

Map one workspace to each area you actually context-switch between. A useful
starting set for a UAP box:

| Workspace | cwd | Owns |
|---|---|---|
| **Hub** | `~/workspace` | index / routing, cross-cutting one-offs |
| **Site** | `~/dev/website` | marketing site work |
| **Ops** | `~/ops` | runbooks, pipelines, operational tasks |
| **Infra** | `~/uap` | this box / UAP framework itself |
| **App** | `~/dev/<app>` | a product repo you work in daily |
| _Claude_ | — | **plugin-owned** mini-space for the `claude-usage` quota meter — auto-created and managed by the plugin; do not rename or close it |

Most workspaces can share `~/workspace` as their cwd — the hub's `CLAUDE.md`
routes an agent into the right subworkspace from there. Point a workspace
directly at a repo only when you always want panes to start inside it.

## Tab snapshot

Tabs are one task each. A snapshot looks like this — yours will differ and should
churn freely:

```
Hub   : Daily messages | Research architecture | Plugin config
Site  : Content refresh | Design pass | SEO fixes
Ops   : Ticket triage | Weekly digest
Infra : New box bootstrap | Chat-app agent surface
App   : Account automation | Form validation
```

## Dump your current layout

Re-run this to print your live workspace → tab mapping in the format above:

```bash
python3 - <<'PY'
import json,subprocess
def cli(*a): return json.loads(subprocess.check_output(['herdr',*a],text=True))
for w in cli('workspace','list')['result']['workspaces']:
    if w['label']=='Claude': continue
    tabs=cli('tab','list','--workspace',w['workspace_id'])['result']['tabs']
    print(f"{w['label']:9}:", ' | '.join(t['label'] for t in tabs))
PY
```
