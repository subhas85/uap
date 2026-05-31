# M365 admin tools

Installs operator-facing Microsoft 365 / Teams administration tooling on UAP:

- PowerShell (`pwsh`) from Microsoft's Ubuntu 24.04 apt repository.
- PowerShell Gallery `MicrosoftTeams` module (CurrentUser scope) — Teams Phone + Teams policy work.
- PowerShell Gallery `Microsoft.Graph.Teams` module (CurrentUser scope) — Graph queries Connect-MicrosoftTeams doesn't cover (e.g. `Get-MgAppCatalogTeamsApp` for finding a Teams catalog app id by externalId).
- `librsvg2-bin` (apt) — `rsvg-convert` for SVG→PNG when preparing Copilot Studio agent icons.

Use a separate Azure CLI profile for elevated admin work so the normal account stays isolated:

```bash
AZURE_CONFIG_DIR=~/.azure-elevated az login
AZURE_CONFIG_DIR=~/.azure-elevated az account show
```

Use Teams PowerShell for Teams Phone objects:

```powershell
Connect-MicrosoftTeams
Get-CsCallQueue
Get-CsAutoAttendant
Get-CsOnlineUser -Identity user@domain.com
```

## Teams App Setup Policy: install + pin a Copilot Studio agent for a group

End-to-end recipe (Linux, all CLI, no admin center). Sign in everywhere with the elevated admin account, not the daily one.

1. **Find the teamsApp catalog id.** Filter by the bot's externalId (= the Bot Framework / Azure Bot app registration GUID, visible in `applicationmanifestinformation.teams.botChannelRegistrationAppId` on the Dataverse `bot` record).

   ```powershell
   Connect-MgGraph -Scopes "AppCatalog.Read.All" -UseDeviceAuthentication -NoWelcome
   Get-MgAppCatalogTeamsApp -Filter "externalId eq '<bot-app-id>'"
   ```

   **Gotcha:** `Connect-MgGraph -UseDeviceAuthentication` has a hardcoded 120 s timeout that doesn't fit MFA. If MFA is enforced, skip this and do a manual OAuth device-code flow against `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/devicecode` with `client_id=14d82eec-204b-4c2f-b7e8-296a70dab67e` and scope `https://graph.microsoft.com/AppCatalog.Read.All offline_access` — that window is 900 s. Then call Graph with `Authorization: Bearer <token>`.

2. **Set the policy.** Use the proper .NET types — hashtables are rejected.

   ```powershell
   Connect-MicrosoftTeams -UseDeviceAuthentication
   $teamsAppId = "<id-from-step-1>"
   $installed = New-Object Microsoft.Teams.Policy.Administration.Cmdlets.Core.AppPreset -Property @{Id=$teamsAppId}
   $pinned    = New-Object Microsoft.Teams.Policy.Administration.Cmdlets.Core.PinnedApp -Property @{Id=$teamsAppId}
   New-CsTeamsAppSetupPolicy -Identity 'YourOrg-IT-Bot' -Description '...' -ErrorAction SilentlyContinue
   Set-CsTeamsAppSetupPolicy -Identity 'YourOrg-IT-Bot' `
       -AllowUserPinning $true -AppPresetList @($installed) -PinnedAppBarApps @($pinned)
   ```

3. **Assign to a group** (M365 group or security group). Parameter is `-Rank`, not `-Priority`.

   ```powershell
   New-CsGroupPolicyAssignment -GroupId <group-guid> -PolicyType TeamsAppSetupPolicy `
       -PolicyName 'YourOrg-IT-Bot' -Rank 1
   ```

   New members of that group inherit the policy automatically; propagation to existing clients is 1–24 h.

Microsoft docs flag `New-/Set-CsTeamsAppSetupPolicy` as "do not use" (they prefer Admin Center UI). On Linux without Admin Center access these are the only path; functional outcome is identical.

## Copilot Studio agent / bot patches via Dataverse Web API

For Copilot Studio author work, the daily account's AI Administrator role is enough — no need to elevate. Get a Dataverse token directly with the daily account and PATCH the `bot` or `botcomponent` entities:

```bash
DV_URL="https://<org>.crm3.dynamics.com"
DV_TOKEN=$(az account get-access-token --resource "$DV_URL" --query accessToken -o tsv)
curl -X PATCH "$DV_URL/api/data/v9.2/bots(<botid>)" \
  -H "Authorization: Bearer $DV_TOKEN" \
  -H "Content-Type: application/json" -H "If-Match: *" \
  -d '{"accesscontrolpolicy":2,"authorizedsecuritygroupids":"<group-guid>"}'
```

Republish via the bound action when content changes:

```bash
curl -X POST "$DV_URL/api/data/v9.2/bots(<botid>)/Microsoft.Dynamics.CRM.PvaPublish" \
  -H "Authorization: Bearer $DV_TOKEN" -d '{}'
```
