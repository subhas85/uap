# apps component

This component installs operator-facing applications (browsers, markdown editor,
terminal tools, file manager, screenshot tool) based on the `apps:` block in
`~/uap.local/identity.yaml`.

There are no rendered files here — `install_apps()` in `setup/apply.sh` does the
work directly via apt + third-party repos. This directory exists so the apply
dispatcher's `render_component` step finds a matching source dir and is a no-op
copy of this README.

To customize what gets installed, edit your `identity.yaml`:

```yaml
apps:
  browsers: [edge, chrome]          # also: chromium, firefox, brave
  markdown_editor: typora            # also: none
  terminal_tools: [btop, bat, glow]  # any apt pkg name works
  file_manager: thunar               # also: nautilus, dolphin, pcmanfm, none
  screenshot: flameshot              # also: scrot, gnome-screenshot, none
```

Then re-run `apply.sh apps`.
