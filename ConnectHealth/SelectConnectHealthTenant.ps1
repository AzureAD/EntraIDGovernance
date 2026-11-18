# Guide: run this file to sign in before running the Connect Health query scripts.
# Prerequisite: your user must have read access to Microsoft Entra Connect Health
# in the target tenant. Verify that you can open the Connect Health blades in
# the portal without receiving an "Access denied" error.
#
# Setup: copy and run this block separately before running the file.
#
# if (-not (Get-Module -ListAvailable -Name Az.Accounts))
# {
#     Install-Module -Name Az.Accounts -Repository PSGallery -Scope CurrentUser -ErrorAction Stop
# }
#
# The requirement below is checked before any commands in this file execute.
#Requires -Modules Az.Accounts

# Enter the target tenant GUID, then complete the Azure sign-in prompts.
# When prompted to select a subscription, press Enter to use the default.
$tenantId = Read-Host -Prompt 'Enter your tenant ID'
if ([string]::IsNullOrWhiteSpace($tenantId))
{
    throw 'A tenant ID is required.'
}

Connect-AzAccount -Tenant $tenantId.Trim() -ErrorAction Stop
