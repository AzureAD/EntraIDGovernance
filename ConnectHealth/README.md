# Microsoft Entra Connect Health Reference Scripts

These read-only PowerShell scripts are provided as references so you can inspect the information returned for your tenant by the Microsoft Entra Connect Health APIs. Each query script calls the Azure Resource Manager (ARM) endpoints using HTTP `GET` requests and outputs JSON to the console without making any configuration changes.

## Prerequisites

- **PowerShell:** Windows PowerShell 5.1 or PowerShell 7+.
- **Permissions:** Read access to Microsoft Entra Connect Health in the target tenant. Confirm you can open the Microsoft Entra Connect Health blades in the Microsoft Entra admin center without an access denied error.
- **Az.Accounts module:** Version `2.17.0` or later is required by the query scripts. To install or update it for your user:

  ```powershell
  if (-not (Get-Module -ListAvailable -Name Az.Accounts | Where-Object { $_.Version -ge [version]'2.17.0' }))
  {
      Install-Module -Name Az.Accounts -MinimumVersion '2.17.0' -Repository PSGallery -Scope CurrentUser -ErrorAction Stop
  }
  ```

## Quick Start

1. Sign in to the target tenant by running `.\SelectConnectHealthTenant.ps1` (or `Connect-AzAccount -Tenant '<tenant-id-or-domain>'`). When prompted for a subscription, press **Enter** to use the default.
2. Run any query script directly (for example, `.\GetTenant.ps1`), or copy and run its sections in order in PowerShell.

## Included Scripts

| File | Description |
| --- | --- |
| `SelectConnectHealthTenant.ps1` | Prompts for a tenant ID and signs in with `Connect-AzAccount`. |
| `GetTenant.ps1` | Returns tenant-level Microsoft Entra Connect Health configuration as JSON. |
| `GetTenantPksCertificateDetails.ps1` | Reads the tenant configuration and decodes `pksCertificate` metadata in memory as JSON without writing certificate files. |
| `GetServices.ps1` | Lists all Microsoft Entra Connect Health services registered in the tenant. |
| `GetService.ps1` | Retrieves detailed service properties for each registered service. |
| `GetServiceMembers.ps1` | Lists the monitored servers (service members) for each registered service. |
| `GetServiceMonitoringConfigurations.ps1` | Retrieves monitoring configuration settings across all registered service types. |
| `GetForestSummary.ps1` | Retrieves forest summaries for Active Directory Domain Services (`AdDomainService`) registrations. |
| `GetReplicationSummary.ps1` | Retrieves replication summaries for Active Directory Domain Services (`AdDomainService`) registrations. |

For illustrative JSON examples of the API responses, see [`SampleOutputs.md`](./SampleOutputs.md).
