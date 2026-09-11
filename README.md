# Microsoft Entra SMS / Voice Retirement Readiness Workbook

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FNobufumiMurata%2Fentra-sms-voice-retirement-workbook%2Fmain%2Fazuredeploy.json)

An Azure Monitor Workbook for finding **observed Microsoft Entra SMS and voice authentication use** in Log Analytics `SigninLogs` before Microsoft-provided SMS and voice delivery retires on **February 1, 2027**.

日本語: Microsoft Entra の `SigninLogs.AuthenticationDetails` を使い、SMS / 音声認証の実利用ユーザー、認証ステップ、最終利用日、推移、データ重複を可視化する Azure Monitor Workbook です。

## What the workbook shows

- Observed SMS / voice users
- Deduplicated authentication steps and raw log rows
- Successful and failed authentication steps
- Daily SMS / voice usage trend
- User, application, first-seen, and last-seen details
- SMS / Voice / Other authentication-method share
- Authentication-method filter with `Previously satisfied` excluded by default
- Overall sign-in health and data-quality checks

The workbook uses the Microsoft Graph canonical values `SMS` and `Voice`, together with the observed/legacy labels `Text message`, `Phone call`, and `Voice call`. It does **not** classify `Passwordless phone sign-in` as SMS or voice.

## Important scope distinction

This workbook answers:

> Who actually used SMS or voice during the retained `SigninLogs` period?

It does **not** determine current Authentication Methods Policy scope or all users who have registered a phone method. Use it together with:

- [Microsoft Entra SMS and voice usage analyzer](https://github.com/microsoft/entra-sms-voice-usage-analyzer) for current policy state, include/exclude targets, registration campaign state, and target CSV.
- [Authentication Methods Activity](https://learn.microsoft.com/entra/identity/authentication/howto-authentication-methods-activity) when registered-method and passwordless-capability information is required.
- [`Export-TelephonyOnlyMfaUsers.ps1`](Export-TelephonyOnlyMfaUsers.ps1) to export enabled users who have a registered phone method but no other registered strong authentication method.

| Analyzer policy target | Workbook observed use | Suggested interpretation |
| --- | --- | --- |
| Yes | Yes | Highest migration priority |
| Yes | No | Potential impact even without recent use |
| No | Yes | Review policy changes and last-use time |
| No | No | No current evidence; continue periodic review |

## Export telephony-only MFA candidates

The included PowerShell script uses the Microsoft Graph `userRegistrationDetails` report to find enabled users who:

1. Are registered for MFA.
2. Have `mobilePhone`, `alternateMobilePhone`, or `officePhone` registered.
3. Have no other registered strong method, such as Microsoft Authenticator, software/hardware OATH, passkey, Windows Hello for Business, or certificate-based authentication.

Install the required modules and run the script:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser

./Export-TelephonyOnlyMfaUsers.ps1 `
   -OutputPath ./telephony-only-mfa-users.csv
```

The delegated Graph permission is `AuditLog.Read.All`. The signed-in user also needs a supported role, such as Reports Reader, Security Reader, Security Administrator, or Global Reader.

Important limitations:

- A registered `mobilePhone` can support SMS, voice, or both depending on policy. Registration data alone doesn't prove which channel the user normally uses.
- The registration report doesn't return disabled users.
- Guests are excluded by default because their MFA might be performed in a home tenant. Use `-IncludeGuests` only for a separate review.
- The script doesn't export phone numbers, tokens, or secrets.
- A candidate is not necessarily impacted if a supported customer-managed telephony provider is configured. Confirm current policy and provider state.

For migration planning, intersect the script output with the official analyzer's policy-target CSV, then prioritize users observed in the Workbook:

```text
Telephony-only registration
   AND current SMS/Voice policy target
   AND enabled user
   AND no applicable customer-managed provider
```

## Prerequisites

1. An Azure subscription and an existing Log Analytics workspace.
2. Microsoft Entra `SigninLogs` routed to that workspace:
   - Microsoft Entra admin center > **Entra ID** > **Monitoring & health** > **Diagnostic settings**.
   - Select `SigninLogs` and **Send to Log Analytics workspace**.
3. Deployment permission on the target resource group. Azure `Contributor` is the simplest built-in role for portal template deployment.
4. Read/query permission on the source workspace, such as `Log Analytics Reader` or `Monitoring Reader`.
5. Users opening the workbook need read access to both the Workbook resource and the referenced workspace. Typical roles are `Workbook Reader` plus `Log Analytics Reader`, or `Monitoring Reader` at an appropriate scope.

New diagnostic settings can take time to populate the workspace. Existing Log Analytics retention determines how far back the workbook can query.

## Deploy with the Azure portal

1. Select **Deploy to Azure** above.
2. Select the subscription and resource group where the Workbook resource will be stored.
3. Enter the existing Log Analytics workspace details.
4. Review the parameters and select **Review + create**.
5. After deployment, open Azure portal > **Monitor** > **Workbooks**, and search for `Entra SMS and Voice Retirement Readiness`.

Direct Workbook Viewer deep links can vary by portal context. The stable access paths are **Monitor > Workbooks** or the deployed Workbook resource overview > **Open Workbook**.

### Template parameters

| Parameter | Required | Default | Purpose |
| --- | --- | --- | --- |
| `workspaceSubscriptionId` | Yes | Current subscription | Subscription containing the workspace |
| `workspaceResourceGroupName` | Yes | Deployment resource group | Resource group containing the workspace |
| `workspaceName` | Yes | None | Existing Log Analytics workspace |
| `workbookDisplayName` | Yes | `Entra SMS and Voice Retirement Readiness` | Display name in the gallery |
| `workbookId` | No | Blank | Optional GUID; blank creates a deterministic ID from resource group and display name |
| `workbookLocation` | Yes | Deployment resource-group location | Workbook resource location |
| `workbookCategory` | Yes | `workbook` | Use `sentinel` for the Sentinel gallery |

## Deploy with Azure CLI

```bash
az deployment group create \
  --name entra-sms-voice-retirement-workbook \
  --resource-group <workbook-resource-group> \
  --template-file azuredeploy.json \
  --parameters \
      workspaceSubscriptionId=<workspace-subscription-id> \
      workspaceResourceGroupName=<workspace-resource-group> \
      workspaceName=<workspace-name>
```

To update an existing Workbook instead of creating a new deterministic resource, pass its GUID as `workbookId`.

## Query model

A single authentication step can appear in multiple `SigninLogs` rows. The workbook therefore does not treat raw row count as authentication count. It uses a distinct key based on:

```text
UserId + AuthenticationMethod + authenticationStepDateTime
```

If the authentication step timestamp is missing, the sign-in `Id` is used as the fallback anchor.

The template contains 13 Workbook items, 7 KQL queries, and 2 parameters:

- `TimeRange`: 1, 7, 30, 90 days, or a custom range.
- `AuthenticationMethod`: multi-select filter for posture charts.

## Security and privacy

- The template contains no tenant ID, subscription ID, workspace ID, user identity, phone number, token, secret, or password.
- The Workbook does not call Microsoft Graph at runtime and requires no Graph application permissions.
- Query results can display user principal names and display names from `SigninLogs`. Restrict Workbook and workspace access with Azure RBAC.
- Exported user tables and analyzer CSV files can contain personal data. Store them outside source control and protect them according to organizational policy.
- The Workbook never displays phone numbers, OTP values, access tokens, or client secrets.

## Troubleshooting

### No data

- Confirm `SigninLogs` exists in the selected workspace.
- Confirm the Entra diagnostic setting points to the same workspace.
- Increase the Workbook time range.
- Check access to both the Workbook resource and the workspace.
- Verify that `AuthenticationDetails` is populated in your tenant's rows.

No matching data can also mean that no SMS or voice authentication step occurred during the selected period. It does not prove that the user is outside current policy scope.

### Deployment succeeds but the Workbook is not in the expected gallery

- Use `workbook` for Azure Monitor > Workbooks.
- Use `sentinel` when the Workbook should be associated with the Microsoft Sentinel gallery.
- Open the Workbook resource overview and select **Open Workbook**.

## Files

- `azuredeploy.json` - parameterized ARM template and Workbook content.
- `Export-TelephonyOnlyMfaUsers.ps1` - exports enabled telephony-only MFA registration candidates to CSV.
- `LICENSE` - MIT license.

## Official references

- [Programmatically manage Azure Workbooks](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-automate)
- [Azure Workbooks overview and access control](https://learn.microsoft.com/azure/azure-monitor/visualize/workbooks-overview)
- [Integrate Microsoft Entra logs with Azure Monitor logs](https://learn.microsoft.com/entra/identity/monitoring-health/howto-integrate-activity-logs-with-azure-monitor-logs)
- [SigninLogs table reference](https://learn.microsoft.com/azure/azure-monitor/reference/tables/signinlogs)
- [Microsoft Graph authenticationDetail resource](https://learn.microsoft.com/graph/api/resources/authenticationdetail?view=graph-rest-beta)
- [Microsoft Graph userRegistrationDetails resource](https://learn.microsoft.com/graph/api/resources/userregistrationdetails?view=graph-rest-1.0)
- [List userRegistrationDetails](https://learn.microsoft.com/graph/api/authenticationmethodsroot-list-userregistrationdetails?view=graph-rest-1.0)
- [Review Microsoft Entra multifactor authentication events](https://learn.microsoft.com/entra/identity/authentication/howto-mfa-reporting)
- [Microsoft Entra SMS and voice usage analyzer](https://github.com/microsoft/entra-sms-voice-usage-analyzer)

## License

MIT. See [LICENSE](LICENSE).
