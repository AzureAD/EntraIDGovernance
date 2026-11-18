# Customer script sample output

Representative objects extracted from the supplied capture. GetServices,
GetService, and GetServiceMembers each show one AD DS, AD FS, and AadSync example;
the other calls show one object. Identifiers, names, and certificate identifiers
are illustrative, and the connection string is replaced with a placeholder.
Request labels, discovery responses, collection wrappers, and other objects are
omitted. Related examples use consistent service and server identifiers.

## GetTenant.ps1

```json
{
  "tenantId": "10000000-0000-0000-0000-000000000001",
  "tenantName": "Example Connect Health tenant",
  "initialDomain": "exampletenant.onmicrosoft.com",
  "devOpsTtl": "0001-01-01T00:00:00",
  "countryLetterCode": "US",
  "replicationScope": "NA",
  "createdDate": "2026-11-09T21:38:43.125154Z",
  "pksCertificate": null,
  "disabled": false,
  "lastDisabled": null,
  "tenantAdoptionJobLastRunDateTime": "2026-11-16T18:38:32.1902244Z",
  "lastDirSyncTime": null,
  "isDirSyncEnabled": false,
  "lastVerified": null,
  "aadLicense": "Premium",
  "onboardingAllowed": true,
  "onboarded": true,
  "consentedToMicrosoftDevOps": null,
  "alertSuppressionTimeInMins": 4320,
  "aadPremium": true,
  "globalAdminsEmail": [
    "user1@example.com",
    "user2@example.com",
    "user3@example.com",
    "user4@example.com"
  ],
  "agentAutoUpdate": true,
  "disabledReason": 0,
  "tenantInQuarantine": false,
  "tenantServices": [],
  "technicalNotificationEmails": [
    "user2@example.com"
  ]
}
```

## GetServices.ps1

### AD DS

```json
{
  "activeAlerts": 0,
  "additionalInformation": [],
  "createdDate": "2026-11-10T08:57:11.0616692Z",
  "customNotificationEmails": null,
  "disabled": false,
  "displayName": "forest-c.example.test",
  "health": "Healthy",
  "lastDisabled": null,
  "lastUpdated": "2026-11-16T23:05:34.6711405Z",
  "disabledReason": 0,
  "monitoringConfigurationsComputed": null,
  "monitoringConfigurationsCustomized": null,
  "notificationEmailEnabled": true,
  "notificationEmailEnabledForGlobalAdmins": true,
  "notificationEmails": null,
  "notificationEmailsEnabledForGlobalAdmins": false,
  "resolvedAlerts": 0,
  "serviceId": "10000000-0000-0000-0000-000000000006",
  "serviceMembers": null,
  "serviceName": "AdDomainService-10000000-0000-0000-0000-000000000007",
  "signature": "10000000-0000-0000-0000-000000000007",
  "simpleProperties": [],
  "tenantId": "10000000-0000-0000-0000-000000000001",
  "type": "AdDomainService",
  "originalDisabledState": false,
  "partnerType": null,
  "id": "/providers/Microsoft.ADHybridHealthService/services/AdDomainService-10000000-0000-0000-0000-000000000007"
}
```

### AD FS

```json
{
  "activeAlerts": 0,
  "additionalInformation": [],
  "createdDate": "2026-11-09T21:49:40.8418965Z",
  "customNotificationEmails": null,
  "disabled": false,
  "displayName": "sts.forest-a.example.test",
  "health": "Healthy",
  "lastDisabled": null,
  "lastUpdated": "2026-11-09T21:51:14.0995397Z",
  "disabledReason": 0,
  "monitoringConfigurationsComputed": null,
  "monitoringConfigurationsCustomized": null,
  "notificationEmailEnabled": true,
  "notificationEmailEnabledForGlobalAdmins": true,
  "notificationEmails": null,
  "notificationEmailsEnabledForGlobalAdmins": false,
  "resolvedAlerts": 0,
  "serviceId": "10000000-0000-0000-0000-000000000008",
  "serviceMembers": null,
  "serviceName": "AdFederationService-sts.forest-a.example.test",
  "signature": "sts.forest-a.example.test",
  "simpleProperties": [],
  "tenantId": "10000000-0000-0000-0000-000000000001",
  "type": "AdFederationService",
  "originalDisabledState": false,
  "partnerType": null,
  "id": "/providers/Microsoft.ADHybridHealthService/services/AdFederationService-sts.forest-a.example.test"
}
```

### AadSync

```json
{
  "activeAlerts": 0,
  "additionalInformation": [],
  "createdDate": "2017-02-04T07:02:30.1675955Z",
  "customNotificationEmails": [
    "identity@example.com",
    "messaging@example.com"
  ],
  "disabled": false,
  "displayName": "exampletenant.onmicrosoft.com",
  "health": "Healthy",
  "lastDisabled": null,
  "lastUpdated": "2026-11-16T23:28:41.0678554Z",
  "disabledReason": 0,
  "monitoringConfigurationsComputed": null,
  "monitoringConfigurationsCustomized": null,
  "notificationEmailEnabled": true,
  "notificationEmailEnabledForGlobalAdmins": true,
  "notificationEmails": null,
  "notificationEmailsEnabledForGlobalAdmins": false,
  "resolvedAlerts": 0,
  "serviceId": "10000000-0000-0000-0000-000000000020",
  "serviceMembers": null,
  "serviceName": "AadSyncService-exampletenant.onmicrosoft.com",
  "signature": "exampletenant.onmicrosoft.com",
  "simpleProperties": [],
  "tenantId": "10000000-0000-0000-0000-000000000001",
  "type": "AadSyncService",
  "originalDisabledState": false,
  "partnerType": null,
  "id": "/providers/Microsoft.ADHybridHealthService/services/AadSyncService-exampletenant.onmicrosoft.com"
}
```

## GetService.ps1

### AD DS

```json
{
  "activeAlerts": 0,
  "additionalInformation": [],
  "createdDate": "2026-11-10T08:57:11.0616692Z",
  "customNotificationEmails": null,
  "disabled": false,
  "displayName": "forest-c.example.test",
  "health": "Healthy",
  "lastDisabled": null,
  "lastUpdated": "2026-11-16T23:05:34.6711405Z",
  "disabledReason": 0,
  "monitoringConfigurationsComputed": null,
  "monitoringConfigurationsCustomized": null,
  "notificationEmailEnabled": true,
  "notificationEmailEnabledForGlobalAdmins": true,
  "notificationEmails": null,
  "notificationEmailsEnabledForGlobalAdmins": false,
  "resolvedAlerts": 0,
  "serviceId": "10000000-0000-0000-0000-000000000006",
  "serviceMembers": null,
  "serviceName": "AdDomainService-10000000-0000-0000-0000-000000000007",
  "signature": "10000000-0000-0000-0000-000000000007",
  "simpleProperties": [
    {
      "key": "Forest name",
      "value": "forest-c.example.test"
    },
    {
      "key": "Functional Level",
      "value": "Windows2016Forest"
    },
    {
      "key": "Domain naming master FSMO role",
      "value": "DC03.forest-c.example.test"
    },
    {
      "key": "Schema master FSMO role",
      "value": "DC03.forest-c.example.test"
    }
  ],
  "tenantId": "10000000-0000-0000-0000-000000000001",
  "type": "AdDomainService",
  "originalDisabledState": false,
  "partnerType": null
}
```

### AD FS

```json
{
  "activeAlerts": 0,
  "additionalInformation": [
    {
      "hasProperties": true,
      "properties": [
        {
          "key": "Serial Number",
          "value": "11111111111111111111111111111111"
        },
        {
          "key": "Signature Algorithm",
          "value": "sha256RSA"
        },
        {
          "key": "Subject",
          "value": "CN=sts.forest-a.example.test"
        },
        {
          "key": "Thumbprint",
          "value": "1111111111111111111111111111111111111111"
        },
        {
          "key": "Issuer",
          "value": "CN=sts.forest-a.example.test"
        },
        {
          "key": "Is Primary",
          "value": "True"
        },
        {
          "key": "Valid To",
          "value": "11/09/2027 21:57:35"
        },
        {
          "key": "Valid From",
          "value": "11/09/2026 21:37:35"
        },
        {
          "key": "Version",
          "value": "3"
        }
      ],
      "titleName": "Service-Communications",
      "titleValue": "CN=sts.forest-a.example.test"
    },
    {
      "hasProperties": true,
      "properties": [
        {
          "key": "Serial Number",
          "value": "22222222222222222222222222222222"
        },
        {
          "key": "Signature Algorithm",
          "value": "sha256RSA"
        },
        {
          "key": "Subject",
          "value": "CN=ADFS Encryption - sts.forest-a.example.test"
        },
        {
          "key": "Thumbprint",
          "value": "2222222222222222222222222222222222222222"
        },
        {
          "key": "Issuer",
          "value": "CN=ADFS Encryption - sts.forest-a.example.test"
        },
        {
          "key": "Is Primary",
          "value": "True"
        },
        {
          "key": "Valid To",
          "value": "11/09/2027 21:48:00"
        },
        {
          "key": "Valid From",
          "value": "11/09/2026 21:48:00"
        },
        {
          "key": "Version",
          "value": "3"
        }
      ],
      "titleName": "Token-Decrypting",
      "titleValue": "CN=ADFS Encryption - sts.forest-a.example.test"
    },
    {
      "hasProperties": true,
      "properties": [
        {
          "key": "Serial Number",
          "value": "33333333333333333333333333333333"
        },
        {
          "key": "Signature Algorithm",
          "value": "sha256RSA"
        },
        {
          "key": "Subject",
          "value": "CN=ADFS Signing - sts.forest-a.example.test"
        },
        {
          "key": "Thumbprint",
          "value": "3333333333333333333333333333333333333333"
        },
        {
          "key": "Issuer",
          "value": "CN=ADFS Signing - sts.forest-a.example.test"
        },
        {
          "key": "Is Primary",
          "value": "True"
        },
        {
          "key": "Valid To",
          "value": "11/09/2027 21:48:00"
        },
        {
          "key": "Valid From",
          "value": "11/09/2026 21:48:00"
        },
        {
          "key": "Version",
          "value": "3"
        }
      ],
      "titleName": "Token-Signing",
      "titleValue": "CN=ADFS Signing - sts.forest-a.example.test"
    },
    {
      "hasProperties": true,
      "properties": [
        {
          "key": "Serial Number",
          "value": "11111111111111111111111111111111"
        },
        {
          "key": "Signature Algorithm",
          "value": "sha256RSA"
        },
        {
          "key": "Subject",
          "value": "CN=sts.forest-a.example.test"
        },
        {
          "key": "Thumbprint",
          "value": "1111111111111111111111111111111111111111"
        },
        {
          "key": "Issuer",
          "value": "CN=sts.forest-a.example.test"
        },
        {
          "key": "Is Primary",
          "value": "True"
        },
        {
          "key": "Valid To",
          "value": "11/09/2027 21:57:35"
        },
        {
          "key": "Valid From",
          "value": "11/09/2026 21:37:35"
        },
        {
          "key": "Version",
          "value": "3"
        }
      ],
      "titleName": "SSL",
      "titleValue": "CN=sts.forest-a.example.test"
    }
  ],
  "createdDate": "2026-11-09T21:49:40.8418965Z",
  "customNotificationEmails": null,
  "disabled": false,
  "displayName": "sts.forest-a.example.test",
  "health": "Healthy",
  "lastDisabled": null,
  "lastUpdated": "2026-11-09T21:51:14.0995397Z",
  "disabledReason": 0,
  "monitoringConfigurationsComputed": null,
  "monitoringConfigurationsCustomized": null,
  "notificationEmailEnabled": true,
  "notificationEmailEnabledForGlobalAdmins": true,
  "notificationEmails": null,
  "notificationEmailsEnabledForGlobalAdmins": false,
  "resolvedAlerts": 0,
  "serviceId": "10000000-0000-0000-0000-000000000008",
  "serviceMembers": null,
  "serviceName": "AdFederationService-sts.forest-a.example.test",
  "signature": "sts.forest-a.example.test",
  "simpleProperties": [
    {
      "key": "Identifier",
      "value": "http://sts.forest-a.example.test/adfs/services/trust"
    },
    {
      "key": "Primary WID Server",
      "value": "SERVER01"
    },
    {
      "key": "Service Account",
      "value": "EXAMPLE\\Administrator"
    },
    {
      "key": "AAD Trust",
      "value": "Not Configured"
    },
    {
      "key": "Farm Behavior Level",
      "value": "4 (2019 Mode)"
    },
    {
      "key": "Applications",
      "value": "-1"
    },
    {
      "key": "Identity Providers",
      "value": "1"
    },
    {
      "key": "Configuration Store",
      "value": "<configuration-store-connection-string>"
    },
    {
      "key": "AutoCertificateRollover Enabled",
      "value": "True"
    }
  ],
  "tenantId": "10000000-0000-0000-0000-000000000001",
  "type": "AdFederationService",
  "originalDisabledState": false,
  "partnerType": null
}
```

### AadSync

```json
{
  "activeAlerts": 0,
  "additionalInformation": [],
  "createdDate": "2017-02-04T07:02:30.1675955Z",
  "customNotificationEmails": [
    "identity@example.com",
    "messaging@example.com"
  ],
  "disabled": false,
  "displayName": "exampletenant.onmicrosoft.com",
  "health": "Healthy",
  "lastDisabled": null,
  "lastUpdated": "2026-11-16T23:28:41.0678554Z",
  "disabledReason": 0,
  "monitoringConfigurationsComputed": null,
  "monitoringConfigurationsCustomized": null,
  "notificationEmailEnabled": true,
  "notificationEmailEnabledForGlobalAdmins": true,
  "notificationEmails": null,
  "notificationEmailsEnabledForGlobalAdmins": false,
  "resolvedAlerts": 0,
  "serviceId": "10000000-0000-0000-0000-000000000020",
  "serviceMembers": null,
  "serviceName": "AadSyncService-exampletenant.onmicrosoft.com",
  "signature": "exampletenant.onmicrosoft.com",
  "simpleProperties": [],
  "tenantId": "10000000-0000-0000-0000-000000000001",
  "type": "AadSyncService",
  "originalDisabledState": false,
  "partnerType": null
}
```

## GetServiceMembers.ps1

### AD DS

```json
{
  "lastReboot": "2026-11-12T23:29:32.235484Z",
  "lastDisabled": null,
  "lastUpdated": "2026-11-16T23:05:34.6711405Z",
  "activeAlerts": 0,
  "resolvedAlerts": 0,
  "createdDate": "2026-11-10T08:57:12.083805Z",
  "disabled": false,
  "dimensions": [
    {
      "key": "addsdomain",
      "value": "10000000-0000-0000-0000-000000000007"
    },
    {
      "key": "addssite",
      "value": "10000000-0000-0000-0000-000000000015"
    }
  ],
  "additionalInformation": "{\"DcRole\":[\"SchemaRole\",\"NamingRole\",\"PdcRole\",\"RidRole\",\"InfrastructureRole\"],\"DcType\":[\"GC\"]}",
  "tenantId": "10000000-0000-0000-0000-000000000001",
  "serviceId": "10000000-0000-0000-0000-000000000006",
  "serviceMemberId": "10000000-0000-0000-0000-000000000016",
  "machineId": "10000000-0000-0000-0000-000000000017",
  "machineName": "DC03.forest-c.example.test",
  "role": "AddsDomainController",
  "status": "Healthy",
  "properties": null,
  "installedQfes": null,
  "recommendedQfes": null,
  "monitoringConfigurationsComputed": null,
  "monitoringConfigurationsCustomized": null,
  "osVersion": "10.0.17763.0",
  "osName": "Microsoft Windows Server 2019 Datacenter",
  "disabledReason": 0,
  "serverReportedMonitoringLevel": null,
  "lastServerReportedMonitoringLevelChange": null
}
```

### AD FS

```json
{
  "lastReboot": "2026-11-09T21:41:42.881107Z",
  "lastDisabled": null,
  "lastUpdated": "2026-11-09T21:51:14.0995397Z",
  "activeAlerts": 0,
  "resolvedAlerts": 0,
  "createdDate": "2026-11-09T21:49:41.7463653Z",
  "disabled": false,
  "dimensions": null,
  "additionalInformation": null,
  "tenantId": "10000000-0000-0000-0000-000000000001",
  "serviceId": "10000000-0000-0000-0000-000000000008",
  "serviceMemberId": "10000000-0000-0000-0000-000000000018",
  "machineId": "10000000-0000-0000-0000-000000000019",
  "machineName": "SERVER01",
  "role": "AdfsServer_2016",
  "status": "Healthy",
  "properties": null,
  "installedQfes": null,
  "recommendedQfes": null,
  "monitoringConfigurationsComputed": null,
  "monitoringConfigurationsCustomized": null,
  "osVersion": "10.0.17763.0",
  "osName": "Microsoft Windows Server 2019 Datacenter",
  "disabledReason": 0,
  "serverReportedMonitoringLevel": null,
  "lastServerReportedMonitoringLevelChange": null
}
```

### AadSync

```json
{
  "lastReboot": "2026-10-24T01:58:34.5Z",
  "lastDisabled": null,
  "lastUpdated": "2026-11-16T23:27:53.2395699Z",
  "activeAlerts": 0,
  "resolvedAlerts": 0,
  "createdDate": "2024-08-01T21:57:45.5152275Z",
  "disabled": false,
  "dimensions": null,
  "additionalInformation": null,
  "tenantId": "10000000-0000-0000-0000-000000000001",
  "serviceId": "10000000-0000-0000-0000-000000000020",
  "serviceMemberId": "10000000-0000-0000-0000-000000000021",
  "machineId": "10000000-0000-0000-0000-000000000022",
  "machineName": "SYNC01",
  "role": "AadSync_AadConnectSync_1.0",
  "status": "Healthy",
  "properties": null,
  "installedQfes": null,
  "recommendedQfes": null,
  "monitoringConfigurationsComputed": [
    {
      "key": "MonitoringLevel",
      "value": "Full"
    },
    {
      "key": "StagingMode",
      "value": "False"
    }
  ],
  "monitoringConfigurationsCustomized": null,
  "osVersion": "10.0.17763.0",
  "osName": "Microsoft Windows Server 2019 Standard",
  "disabledReason": 0,
  "serverReportedMonitoringLevel": null,
  "lastServerReportedMonitoringLevelChange": null
}
```

## GetServiceMonitoringConfigurations.ps1

```json
{
  "key": "AadPremium",
  "value": "True"
}
```

## GetForestSummary.ps1

```json
{
  "domainCount": 1,
  "domains": [
    "forest-c.example.test"
  ],
  "forestName": "forest-c.example.test",
  "monitoredDcCount": 1,
  "siteCount": 1,
  "sites": [
    "Default-First-Site-Name"
  ],
  "totalDcCount": 1
}
```

## GetReplicationSummary.ps1

```json
{
  "domain": "forest-c.example.test",
  "inboundNeighborCollection": null,
  "lastAttemptedSync": "1753-01-01T00:00:00.0000001Z",
  "lastSuccessfulSync": "1753-01-01T00:00:00.0000001Z",
  "serviceId": "10000000-0000-0000-0000-000000000006",
  "serviceMemberId": "10000000-0000-0000-0000-000000000016",
  "site": "Default-First-Site-Name",
  "status": 3,
  "targetServer": "DC03.forest-c.example.test"
}
```
