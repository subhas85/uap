# xrdp-watchdog tests

## Unit tests

```
./run-tests.sh
```

Runs all `test-*.sh` files. Uses env-overrideable shims; safe to run anywhere.

## Integration tests

```
./integration.sh
```

**WARNING:** breaks xrdp on purpose. Refuses to run without `/etc/uap.local/test-mode`.

Run only on disposable VMs.

```bash
sudo mkdir -p /etc/uap.local && sudo touch /etc/uap.local/test-mode
./integration.sh
```
