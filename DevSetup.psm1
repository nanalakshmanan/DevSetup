$script:Packages = @(
        @{Name = 'Git.Install'; Path = $null;                                Type = 'Chocolatey'},
        @{Name = 'Git';         Path = "${Env:ProgramFiles(x86)}\git\bin";   Type = 'Chocolatey'},
        @{Name = 'Ruby';        Path = "C:\Tools\ruby215\bin";               Type = 'Chocolatey'},
        @{Name = 'githug';      Path = $null;                                Type = 'RubyGem'}
)

$script:InstalledChocoPackages = @()
$script:InstalledRubyGems      = @()

function Assert-Prerequisite
{
    [CmdletBinding()]
    param()

    Write-Verbose "Checking if correct version of PowerShell is available"

    if ($PSVersionTable.PSVersion -lt '5.0.10018.0')
    {
        throw "WMF Feb 2015 or higher is required for this module to work"
    }

    Write-Verbose "Testing elevation status"

    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)

    if (!$p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
    {
        throw "This module performs installations and needs to be run elevated"
    }                
}

function Install-RequiredPackage
{
    [CmdletBinding()]
    param(
        [switch]
        $Force
    )

    Assert-Prerequisite

    if (-not (Test-Chocolatey))
    {
        Install-Chocolatey
    }

    Load-InstalledChocoPackage

    $script:Packages | % {

        $Package = New-Object PSObject -Property $_

        if (-not $Force)
        {
            if ($Package.Type -ieq 'Chocolatey')
            {
                $InstallNeeded = !(Test-ChocoPackage -Name $Package.Name )
            }
            else
            {
                $InstallNeeded = !(Test-RubyGem -Name $Package.Name)
            }
        }
        else
        {
            $InstallNeeded = $true
        }

        if ($InstallNeeded)
        {
            if ($Package.Type -ieq 'Chocolatey')
            {
                Install-ChocoPackage -Name $Package.Name
            }
            else
            {
                Install-RubyGem -Name $Package.Name
            }
        }

        if ($Package.Path -ne $null)
        {
            Add-Path -PathFragment $Package.Path 
        }
    }

    Install-RequiredPatch
}

function Load-InstalledChocoPackage
{   
    $Packages = (choco list -localonly) -split "`r`n"

    if ($Packages[0] -match "No packages found.")
    {
        $script:InstalledChocoPackages = @()
    }
    else
    {
        $Packages | % {
            $Property = $_.Split(" ")
            $script:InstalledChocoPackages += @{Name=($Property[0].Trim()); Version = ($Property[1].Trim())}
        }
    }
}

function Load-InstalledRubyGem
{   
    Load-InstalledChocoPackage

    $RubyInstalled = $false
    $script:InstalledChocoPackages | % {
        if ($_.Name -ieq 'Ruby')
        {
            $RubyInstalled = $true
        }
    }

    if ($RubyInstalled)
    {
        $Packages = (gem list -local) -split "`r`n"
        
        $Packages | % {
            $Property = $_.Split(" ")
            $script:InstalledRubyGems += @{Name=($Property[0].Trim()); Version = ($Property[1].Trim())}
        }       
    }
}

function Test-ChocoPackage
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name
    )

    if ($script:InstalledChocoPackages.Count -eq 0)
    {
        Load-InstalledChocoPackage
    }

    $found = $false

    $script:InstalledChocoPackages | % {
        if ($_.Name -ieq $Name)
        {
            $found = $true            
        }
    }
    
    return $found
}

function Test-RubyGem
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name
    )

    if ($script:InstalledRubyGems.Count -eq 0)
    {
        Load-InstalledRubyGem
    }

    $found = $false

    $script:InstalledRubyGems | % {
        if ($_.Name -ieq $Name)
        {
            $found = $true            
        }
    }
    
    return $found
}

function Install-ChocoPackage
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name,

        [switch]
        $Force
    )

    if ($Force)
    {
        $Command = 'choco install {0} -force'
    }
    else
    {
        $Command = 'choco install {0}'
    }
    $Command = $Command -f $Name

    powershell -c "$Command"
}

function Install-RubyGem
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name,

        [switch]
        $Force
    )

    if ($Force)
    {
        $Command = 'gem install {0} --force'
    }
    else
    {
        $Command = 'gem install {0}'
    }
    $Command = $Command -f $Name

    powershell -c "$Command"
}

function Uninstall-RequiredPackage
{
    [CmdletBinding()]
    param()

    Assert-Prerequisite

    if (-not (Test-Chocolatey))
    {
        Install-Chocolatey
    }

    Load-InstalledChocoPackage

    $script:Packages | % {

        $Package = New-Object PSObject -Property $_

        $Installed =  (! (Test-ChocoPackage -Name $Package.Name ))
        
        if ($Installed)
        {
            if ($Package.Type -ieq 'Chocolatey')
            {
                uninstall-ChocoPackage -Name $Package.Name
            }
            else
            {
                Uninstall-RubyGem -Name $Package.Name 
            }
        }

        if ($Package.Path -ne $null)
        {
            Remove-Path -PathFragment $Package.Path 
        }
    }
}

function Add-Path
{
    [CmdletBinding()]
    param(
        [string]
        $PathFragment,

        [ValidateSet("Machine", "User")]
        [string]
        $Scope = "Machine"
    )

    if ($env:Path.IndexOf($PathFragment) -ne -1)
    {
        Write-Verbose "$PathFragment exists in `$env:Path, returning"
        return
    }

    Write-Verbose "Adding $PathFragment to `$env:Path in $Scope scope"
    [System.Environment]::SetEnvironmentVariable("PATH", "$($env:Path);$PathFragment", $Scope)

    Write-Verbose "Adding $PathFragment to `$env:Path in process scope"
    [System.Environment]::SetEnvironmentVariable("PATH", "$($env:Path);$PathFragment", [environmentvariabletarget]::Process)
}

function Remove-Path
{
    [CmdletBinding()]
    param(
        [string]
        $PathFragment,

        [ValidateSet("Machine", "User")]
        [string]
        $Scope = "Machine"
    )

    $NewPath = $env:Path
    $Pos = $NewPath.IndexOf($PathFragment)

    while($Pos -ne -1)
    {
        $NewPath = $NewPath.Remove($pos, $PathFragment.Length)
        $Pos = $NewPath.IndexOf($PathFragment)
    }

    Write-Verbose "Removing $PathFragment from `$env:Path in $Scope scope"
    [System.Environment]::SetEnvironmentVariable("PATH", "$NewPath", $Scope)

    Write-Verbose "Removing $PathFragment from `$env:Path in process scope"
    [System.Environment]::SetEnvironmentVariable("PATH", "$NewPath", [environmentvariabletarget]::Process)
}

function Uninstall-ChocoPackage
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name
    )
    
    $Command = 'choco uninstall {0}'
    $Command = $Command -f $Name

    powershell -c "$Command"
}

function Uninstall-RubyGem
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name
    )
    
    $Command = 'gem uninstall {0}'
    $Command = $Command -f $Name

    powershell -c "$Command"
}

function Test-Chocolatey
{
    Write-Verbose "Checking if Chocolatey is present"
    Invoke-Command {choco} -ErrorVariable e 2> $null

    if ($e.Count -eq 0)
    {
        return $true
    }

    return $false
}

function Install-Chocolatey
{
    [CmdletBinding()]
    param()

    if (Test-Chocolatey)
    {
        Write-Verbose "Chocolatey already present, returning"
        return
    }

    Write-Verbose "Installing Chocolatey"

    Invoke-Expression ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
}

function Uninstall-Chocolatey
{
    [CmdletBinding()]
    param()

    if (! (Test-Chocolatey))
    {
        Write-Verbose "Chocolatey not present, returning"
        return
    }

    Write-Verbose "Uninstalling Chocolatey"
   
    Remove-Item -Recurse -Force "$env:ProgramData\Chocolatey"

    Remove-Item Env:\ChocolateyInstall -Force

    [System.Environment]::SetEnvironmentVariable("ChocolateyInstall", $Null, [environmentvariabletarget]::User)

}

function Install-RequiredPatch
{
    $script:Packages | % {
        switch ($_.Name)
        {
            'Ruby' {Install-RubyPatch; break}
        }
    }
}

function Install-RubyPatch
{
    [CmdletBinding()]
    Param()

    $LocalGemFile = "C:\tools\ruby215\rubygems-update-2.2.3.gem"
    $GemUri = "https://github.com/rubygems/rubygems/releases/download/v2.2.3/rubygems-update-2.2.3.gem"
    $WebClient = New-Object System.Net.WebClient
    
    $WebClient.DownloadFile($GemUri, $LocalGemFile)

    gem install --local "$LocalGemFile"
    update_rubygems --no-ri --no-rdoc
    gem uninstall rubygems-update-x
}

Export-ModuleMember Install-Chocolatey, Uninstall-Chocolatey, Install-RequiredPackage, Uninstall-RequiredPackage