# vm-guest component

Small guest-side tweaks that only make sense when UAP runs as a VM (Proxmox /
KVM / VMware). Every tweak is gated on `systemd-detect-virt`, so on bare metal
this component is a no-op.

There are no rendered files here — `install_vm_guest()` in `setup/apply.sh`
does the work directly. This directory exists so the apply dispatcher's
`render_component` step finds a matching source dir.

## What it does

### Disable `fwupd-refresh.timer`

On a UEFI (OVMF) guest with Secure Boot keys enrolled, `fwupd` sees the VM's
own EFI variables (`UEFI CA` / `UEFI dbx`) as "updatable firmware devices" and
the refresh timer writes a nagging line into the SSH login banner:

    2 devices have a firmware upgrade available.
    Run `fwupdmgr get-upgrades` for more information.

These are *not* host firmware — they're Secure Boot db/dbx updates stored in
the VM's EFI disk. Applying the dbx update can blacklist the shim/grub the
guest boots from and leave it unbootable, and fwupd only lists newer distros
as tested. We leave them alone and silence the MOTD by disabling the timer.
`fwupdmgr` still works on demand if you ever want to look.

Reverse with: `sudo systemctl enable --now fwupd-refresh.timer`
