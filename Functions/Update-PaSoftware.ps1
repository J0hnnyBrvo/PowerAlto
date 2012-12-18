﻿function Update-PaSoftware {
    <#
	.SYNOPSIS
		**IN PROGRESS** Updates PanOS software to desired version.
	.DESCRIPTION
		
	.EXAMPLE
        EXAMPLES!
	.EXAMPLE
		EXAMPLES!
	.PARAMETER PaConnectionString
		Specificies the Palo Alto connection string with address and apikey.
	#>

    Param (
        [Parameter(Mandatory=$False)]
        [alias('pc')]
        [String]$PaConnection,

        [Parameter(Mandatory=$True)]
        [alias('v')]
        [ValidatePattern("\d\.\d\.\d(-\w\d+)?|latest")]
        [String]$Version,

        [Parameter(Mandatory=$False)]
        [alias('d')]
        [Switch]$DownloadOnly,

        [Parameter(Mandatory=$False)]
        [alias('nr')]
        [Switch]$NoRestart
    )

    BEGIN {
        Function Get-Stepping ( [String]$Version ) {
            $Stepping = @()
            $UpdateCheck = Send-PaApiQuery -Op "<request><system><software><check></check></software></system></request>"
            if ($UpdateCheck.response.status -eq "success") {
                $VersionInfo = Send-PaApiQuery -Op "<request><system><software><info></info></software></system></request>"
                $AllVersions = $VersionInfo.response.result."sw-updates".versions.entry
                $DesiredVersion = $AllVersions | where { $_.version -eq "$Version" }
                if (!($DesiredVersion)) { return "version $Version not listed" }
                $DesiredBase = $DesiredVersion.version.Substring(0,3)
                $CurrentVersion = (Get-PaSystemInfo)."sw-version"
                $CurrentVersion = "4.0.0"
                $CurrentBase = $CurrentVersion.Substring(0,3)
                if ($CurrentBase -eq $DesiredBase) {
                    $Stepping += $Version
                } else {
                    foreach ($v in $AllVersions) {
                        $Step = $v.version.Substring(0,3)
                        if (($Stepping -notcontains "$Step.0") -and ("$Step.0" -ne "$CurrentBase.0") -and ($Step -le $DesiredBase)) {
                            $Stepping += "$Step.0"
                        }
                    }
                    $Stepping += $Version
                }
                set-variable -name pacom -value $true -scope 1
                return $Stepping | sort
            } else {
                return $UpdateCheck.response.msg.line
            }
        }

        Function Download-Update ( [Parameter(Mandatory=$True)][String]$Version ) {
            $VersionInfo = Send-PaApiQuery -Op "<request><system><software><info></info></software></system></request>"
            if ($VersionInfo.response.status -eq "success") {
                $DesiredVersion = $VersionInfo.response.result."sw-updates".versions.entry | where { $_.version -eq "$Version" }
                if ($DesiredVersion.downloaded -eq "no") {
                    $Download = Send-PaApiQuery -Op "<request><system><software><download><version>$($DesiredVersion.version)</version></download></software></system></request>"
                    $job = [decimal]($Download.response.result.job)
                    $Status = Watch-PaJob -j $job -c "Downloading $($DesiredVersion.version)" -s $DesiredVersion.size
                    if ($Status.response.result.job.result -eq "FAIL") {
                        return $Status.response.result.job.details.line
                    }
                    set-variable -name pacom -value $true -scope 1
                    return $Status
                } else {
                    set-variable -name pacom -value $true -scope 1
                    return "PanOS $Version already downloaded"
                }
            } else {
                throw $VersionInfo.response.msg.line
            }
        }

        Function Install-Update ( [Parameter(Mandatory=$True)][String]$Version ) {
            $VersionInfo = Send-PaApiQuery -Op "<request><system><software><info></info></software></system></request>"
            if ($VersionInfo.response.status -eq "success") {
                $DesiredVersion = $VersionInfo.response.result."sw-updates".versions.entry | where { $_.version -eq "$Version" }
                if ($DesiredVersion.downloaded -eq "no") { "PanOS $Version not downloaded" }
                if ($DesiredVersion.current -eq "no") {
                    $xpath = "<request><system><software><install><version>$Version</version></install></software></system></request>"
                    $Install = Send-PaApiQuery -Op $xpath
                    $Job = [decimal]($Install.response.result.job)
                    $Status = Watch-PaJob -j $job -c "Installing $Version"
                    if ($Status.response.result.job.result -eq "FAIL") {
                        return $Status.response.result.job.details.line
                    }
                    set-variable -name pacom -value $true -scope 1
                    return $Status
                } else {
                    set-variable -name pacom -value $true -scope 1
                    return "PanOS $Version already installed"
                }
            } else {
                return $VersionInfo.response.msg.line
            }
        }

        Function Process-Query ( [String]$PaConnectionString ) {
            $pacom = $false
            while (!($pacom)) {
                if ($Version -eq "latest") {
                    $UpdateCheck = Send-PaApiQuery -Op "<request><system><software><check></check></software></system></request>"
                    if ($UpdateCheck.response.status -eq "success") {
                        $VersionInfo = Send-PaApiQuery -Op "<request><system><software><info></info></software></system></request>"
                        $Version = ($VersionInfo.response.result."sw-updates".versions.entry | where { $_.latest -eq "yes" }).version
                        if (!($Version)) { throw "no version marked as latest" }
                        $pacom = $true
                    } else {
                        return $UpdateCheck.response.msg.line
                    }
                }
            }

            $pacom = $false
            while (!($pacom)) {
                $Steps = Get-Stepping "$Version"
                $Steps
            }

            Write-host "it will take $($steps.count) upgrades to get to the current firmware"

            if (($Steps.count -gt 1) -and ($NoRestart)) {
                "gotta restart for multiples"
            }

            <#
            foreach ($s in $Steps) {
                $pacom = $false
                "downloading $s"
                while (!($pacom)) {
                    $Download = Download-Update $s
                }
            }

            foreach ($s in $Steps) {
                $pacom = $false
                "installing $s"
                while (!($pacom)) {
                    $Install = Install-Update $s
                }
                Restart-PaSystem
            }#>
        }
    }

    PROCESS {
        if ($PaConnection) {
            Process-Query $PaConnection
        } else {
            if (Test-PaConnection) {
                foreach ($Connection in $Global:PaConnectionArray) {
                    Process-Query $Connection.ConnectionString
                }
            } else {
                Throw "No Connections"
            }
        }
    }
}