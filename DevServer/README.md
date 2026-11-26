# Dev server

A disposable Vaultwarden environment for developing and testing Triwarden. It runs on the
`m1pro` dev box (OrbStack/Docker) and is driven from your Mac with `dev.sh`.

| Endpoint | What |
|---|---|
| `https://devbox.local:18843` | Vaultwarden **latest**, behind Caddy (private CA) |
| `https://devbox.local:18844` | Vaultwarden **1.30.5**, for older API shapes |
| `http://devbox.local:18880` | latest, plain HTTP (quick `curl`, app debugging) |
| `http://<dev ip>:18881` | latest with SSO (OpenID Connect) against dex |
| `http://<dev ip>:18856/dex` | dex identity provider; users `usagi@` and `momonga@chiikawarden.test` (TOTP after sign-on), dev password |
| `http://devbox.local:18826` | Mailpit — every email the servers send |
| `…:18843/admin` | Admin panel; token is in `~/triwarden-dev/.env` on the dev box |

```bash
./dev.sh up      # deploy/start, fetch the Caddy root CA to data/root.crt
./dev.sh seed    # create test accounts + items on both servers (idempotent)
./dev.sh test    # run VaultCore tests, including the dev-server integration suite
./dev.sh logs vaultwarden
./dev.sh reset   # wipe both vaults and start over
```

## Test accounts

All use the password `chiikawa-dev-password` (dev only — override with `TRIWARDEN_DEV_PASSWORD`).

| Account | KDF | Notes |
|---|---|---|
| `usagi@chiikawarden.test` | PBKDF2 600k | Logins (TOTP, unicode, reused/weak), note, card, identity; member of org “Chiikawa Family” |
| `hachiware@chiikawarden.test` | Argon2id t3 m64 p4 | Same personal items |
| `momonga@chiikawarden.test` | PBKDF2 600k | TOTP 2FA enabled. Vaultwarden 1.37+ issues the secret, and `seed` saves it to `data/totp/<port>.totp`; older servers use `JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP` |

`seed.py` does the client-side crypto in Python (`cryptography`, `argon2-cffi`), so it doubles as an
independent reference implementation for the Swift crypto.

The dev box answers as `devbox.local` (its mDNS name) and also by IP `192.168.1.50`.

Other machines: set `TRIWARDEN_DEV_REMOTE` (ssh host) and `TRIWARDEN_DEV_HOST` (address clients use).
