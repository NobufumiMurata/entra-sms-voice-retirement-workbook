[CmdletBinding()]
param(
    [string]$OutputPath = (Join-Path $PWD "telephony-only-mfa-users.csv"),
    [switch]$IncludeGuests,
    [switch]$SkipConnect
)

$ErrorActionPreference = "Stop"

$requiredModules = @("Microsoft.Graph.Authentication")

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Required module '$module' isn't installed. Run: Install-Module $module -Scope CurrentUser"
    }
    Import-Module $module
}

if (-not $SkipConnect) {
    Connect-MgGraph -Scopes "AuditLog.Read.All" -NoWelcome
}
elseif (-not (Get-MgContext)) {
    throw "-SkipConnect was specified, but no Microsoft Graph context is available."
}

$telephonyMethods = @(
    "mobilePhone"
    "alternateMobilePhone"
    "officePhone"
)

# These registrations don't provide a nontelephony MFA alternative.
$nonMfaMethods = @(
    "password"
    "email"
    "securityQuestions"
)

$registrationDetails = @()
$requestUri = "https://graph.microsoft.com/v1.0/reports/authenticationMethods/userRegistrationDetails?`$select=id,userPrincipalName,userDisplayName,userType,isAdmin,isMfaRegistered,isMfaCapable,isPasswordlessCapable,methodsRegistered,systemPreferredAuthenticationMethods,userPreferredMethodForSecondaryAuthentication,lastUpdatedDateTime&`$top=999"

do {
    $response = Invoke-MgGraphRequest -Method GET -Uri $requestUri
    $registrationDetails += @($response.value)
    $requestUri = $response.'@odata.nextLink'
} while ($requestUri)

$candidates = foreach ($user in $registrationDetails) {
    if (-not $IncludeGuests -and $user.UserType -ne "member") {
        continue
    }

    $registeredMethods = @(
        $user.MethodsRegistered |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $registeredTelephonyMethods = @(
        $registeredMethods |
            Where-Object { $_ -in $telephonyMethods }
    )
    $otherStrongMethods = @(
        $registeredMethods |
            Where-Object {
                $_ -notin $telephonyMethods -and
                $_ -notin $nonMfaMethods
            }
    )

    if (
        $user.IsMfaRegistered -and
        $registeredTelephonyMethods.Count -gt 0 -and
        $otherStrongMethods.Count -eq 0
    ) {
        $preferredMethod = $user.UserPreferredMethodForSecondaryAuthentication
        $systemPreferredMethods = @(
            $user.SystemPreferredAuthenticationMethods |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )

        [pscustomobject]@{
            UserPrincipalName = $user.UserPrincipalName
            DisplayName = $user.UserDisplayName
            UserId = $user.Id
            UserType = $user.UserType
            IsAdmin = $user.IsAdmin
            IsMfaRegistered = $user.IsMfaRegistered
            IsMfaCapable = $user.IsMfaCapable
            IsPasswordlessCapable = $user.IsPasswordlessCapable
            RegisteredMethods = $registeredMethods -join ","
            TelephonyMethods = $registeredTelephonyMethods -join ","
            PreferredSecondaryMethod = $preferredMethod
            SystemPreferredMethods = $systemPreferredMethods -join ","
            ReportUpdatedAtUtc = $user.LastUpdatedDateTime
        }
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if ($outputDirectory -and -not (Test-Path $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$outputColumns = @(
    "UserPrincipalName"
    "DisplayName"
    "UserId"
    "UserType"
    "IsAdmin"
    "IsMfaRegistered"
    "IsMfaCapable"
    "IsPasswordlessCapable"
    "RegisteredMethods"
    "TelephonyMethods"
    "PreferredSecondaryMethod"
    "SystemPreferredMethods"
    "ReportUpdatedAtUtc"
)

$candidates = @($candidates | Sort-Object UserPrincipalName)
if ($candidates.Count -gt 0) {
    $candidates |
        Select-Object -Property $outputColumns |
        Export-Csv -Path $OutputPath -NoTypeInformation -Encoding utf8
}
else {
    ($outputColumns | ForEach-Object { '"{0}"' -f $_ }) -join "," |
        Set-Content -Path $OutputPath -Encoding utf8
}
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)

[pscustomobject]@{
    ReportUsers = $registrationDetails.Count
    TelephonyOnlyMfaCandidates = $candidates.Count
    IncludedUserTypes = if ($IncludeGuests) { "member,guest" } else { "member" }
    OutputPath = $resolvedOutputPath
} | Format-List

Write-Warning "This report identifies enabled users with a registered phone method and no other registered strong method. Confirm Authentication Methods Policy scope and recent SigninLogs usage before taking action."