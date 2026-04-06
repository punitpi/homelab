# Authentik SSO Setup Guide

> **Note: Authentik was removed from this homelab in April 2026.**
>
> It consumed ~1GB RAM on the Raspberry Pi and SSO was never fully configured.
> All `authentik@file` forward auth middleware labels have been removed from app routes.
> n8n and paperless-ngx no longer have OIDC env vars configured.
>
> If you want to re-add SSO in the future, consider lighter alternatives like:
> - **Authelia** (~100MB RAM) — simpler forward auth, LDAP/TOTP support
> - **Pocket ID** — minimal OIDC provider
> - Native per-app auth (most apps have built-in user management)
>
> To re-enable Authentik: check git history for the previous configuration.
