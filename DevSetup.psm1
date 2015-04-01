$script:Packages = @(
        @{Name = 'Git.Install'; Path = $null;                                Type = 'Chocolatey'},
        @{Name = 'Git';         Path = "${Env:ProgramFiles(x86)}\git\bin";   Type = 'Chocolatey'},
        @{Name = 'Ruby';        Path = 'C:\Tools\ruby215\bin';               Type = 'Chocolatey'},
        @{Name = 'githug';      Path = $null;                                Type = 'RubyGem'}
)

$script:InstalledChocoPackages = @()
$script:InstalledRubyGems      = @()

#region Helpers
function Assert-Prerequisite
{
    [CmdletBinding()]
    param()

    Write-Verbose 'Checking if correct version of PowerShell is available'

    if ($PSVersionTable.PSVersion -lt '5.0.10018.0')
    {
        throw 'WMF Feb 2015 or higher is required for this module to work'
    }

    Write-Verbose 'Testing elevation status'

    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object System.Security.Principal.WindowsPrincipal($id)

    if (!$p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator))
    {
        throw 'This module performs installations and needs to be run elevated'
    }                
}

function Update-InstalledChocoPackage
{ 
    $script:InstalledChocoPackages = @()
    if (-not (Test-Chocolatey)) {return}

    $Packages = (choco list -localonly) -split "`r`n"

    if ($Packages[0] -match 'No packages found.') {return}
    
    $Packages | % {
        $Property = $_.Split(' ')
        $script:InstalledChocoPackages += @{Name=($Property[0].Trim()); Version = ($Property[1].Trim())}
    }    
}

function Update-InstalledRubyGem
{   
    $script:InstalledRubyGems = @()
    
    if (!(Test-ChocoPackage -Name 'ruby')) {return}
   
    $Packages = (gem list --local) -split "`r`n"
        
    $Packages | % {
        $Property = $_.Split(' ')
        $script:InstalledRubyGems += @{Name=($Property[0].Trim()); Version = ($Property[1].Trim())}
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
        Update-InstalledChocoPackage
    }

    $found = $false

    foreach($Package in $script:InstalledChocoPackages)
    {
      if ($Package.Name -ieq $Name) {return $true}
    }
    
    return $false
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
        Update-InstalledRubyGem
    }

    foreach($Gem in $script:InstalledRubyGems)
    {
      if ($Gem.Name -ieq $Name) {return $true}
    }
    
    return $false
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
        $Command = 'install {0} -force'
    }
    else
    {
        $Command = 'install {0}'
    }
    $Command = $Command -f $Name

    & choco ("$Command" -split ' ')
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
        $Command = 'install {0} --force'
    }
    else
    {
        $Command = 'install {0}'
    }
    $Command = $Command -f $Name

    & gem ("$Command" -split ' ')
}

function Add-Path
{
    [CmdletBinding()]
    param(
        [string]
        $PathFragment,

        [ValidateSet('Machine', 'User')]
        [string]
        $Scope = 'Machine'
    )

    if ($env:Path.IndexOf($PathFragment) -ne -1)
    {
        Write-Verbose "$PathFragment exists in `$env:Path, returning"
        return
    }

    Write-Verbose "Adding $PathFragment to `$env:Path in $Scope scope"
    [System.Environment]::SetEnvironmentVariable('PATH', "$($env:Path);$PathFragment", $Scope)

    Write-Verbose "Adding $PathFragment to `$env:Path in process scope"
    [System.Environment]::SetEnvironmentVariable('PATH', "$($env:Path);$PathFragment", [environmentvariabletarget]::Process)
}

function Remove-Path
{
    [CmdletBinding()]
    param(
        [string]
        $PathFragment,

        [ValidateSet('Machine', 'User')]
        [string]
        $Scope = 'Machine'
    )

    $NewPath = $env:Path
    $Pos = $NewPath.IndexOf($PathFragment)

    while($Pos -ne -1)
    {
        $NewPath = $NewPath.Remove($pos, $PathFragment.Length)
        $Pos = $NewPath.IndexOf($PathFragment)
    }

    Write-Verbose "Removing $PathFragment from `$env:Path in $Scope scope"
    [System.Environment]::SetEnvironmentVariable('PATH', "$NewPath", $Scope)

    Write-Verbose "Removing $PathFragment from `$env:Path in process scope"
    [System.Environment]::SetEnvironmentVariable('PATH', "$NewPath", [environmentvariabletarget]::Process)
}

function Uninstall-ChocoPackage
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name
    )
    
    $Command = 'uninstall {0}'
    $Command = $Command -f $Name

    & choco ("$Command" -split ' ')
}

function Uninstall-RubyGem
{
    [CmdletBinding()]
    param
    (
        [string]
        $Name
    )
    
    $Command = 'uninstall {0} -x'
    $Command = $Command -f $Name

    & gem ("$Command" -split ' ')
}

function Test-Chocolatey
{
    Write-Verbose 'Checking if Chocolatey is present'
    Invoke-Command {choco} -ErrorVariable e 2> $null

    if ($e.Count -eq 0)
    {
        return $true
    }

    return $false
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

    $LocalGemFile = 'C:\tools\ruby215\rubygems-update-2.2.3.gem'
    $GemUri = 'https://github.com/rubygems/rubygems/releases/download/v2.2.3/rubygems-update-2.2.3.gem'
    $WebClient = New-Object System.Net.WebClient
    
    $WebClient.DownloadFile($GemUri, $LocalGemFile)

    gem install --local "$LocalGemFile"
    update_rubygems --no-ri --no-rdoc
    gem uninstall rubygems-update-x
}

#endregion Helpers

#region Exports
<#
 .SYNOPSIS
    Installs chocolatey

 .DESCRIPTION
    Installs chocolatey using 'https://chocolatey.org/install.ps1'

 .LINK
    https://github.com/nanalakshmanan/DevSetup     
#>
function Install-Chocolatey
{
    [CmdletBinding()]
    param()

    if (Test-Chocolatey)
    {
        Write-Verbose 'Chocolatey already present, returning'
        return
    }

    Write-Verbose 'Installing Chocolatey'

    Invoke-Expression ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
}

<#
 .SYNOPSIS
    Uninstalls chocolatey

 .DESCRIPTION
    Uninstalls chocolatey by removing folder and environment variable
    (as prescribed in chocolatey guidelines)

 .LINK
    https://github.com/nanalakshmanan/DevSetup     
#>
function Uninstall-Chocolatey
{
    [CmdletBinding()]
    param()

    if (! (Test-Chocolatey))
    {
        Write-Verbose 'Chocolatey not present, returning'
        return
    }

    Write-Verbose 'Uninstalling Chocolatey'
   
    Remove-Item -Recurse -Force "$env:ProgramData\Chocolatey"

    Remove-Item Env:\ChocolateyInstall -Force

    [System.Environment]::SetEnvironmentVariable('ChocolateyInstall', $Null, [environmentvariabletarget]::User)

}

<#
 .SYNOPSIS
    Install developer tools for building resources/configurations

 .DESCRIPTION
    Installs a pre determined set of tools for building resources
    and configurations

 .NOTES
    Currently supports chocolatey packages and ruby gems. Will
    also install Chocolatey if not already present

 .LINK
    https://github.com/nanalakshmanan/DevSetup

 .EXAMPLE
    Install-DevTool -Verbose

  .EXAMPLE
    Install-DevTool -Force -Verbose
    
    This command Force installs the tools even if already present
     
  .PARAMETER Force 
    Force installs the tools even if already present      
#>
function Install-DevTool
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

    Update-InstalledChocoPackage

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

<#
 .SYNOPSIS
    Uninstall developer tools for building resources/configurations

 .DESCRIPTION
    Unnstalls all tools from pre determined set of tools for building resources
    and configurations

 .NOTES
    Currently supports chocolatey packages and ruby gems. Does not uninstall
    chocolatey. Call Uninstall-Chocolatey command for the same

 .LINK
    https://github.com/nanalakshmanan/DevSetup

 .EXAMPLE
    Uninstall-DevTool -Verbose
       
#>
function Uninstall-DevTool
{
    [CmdletBinding()]
    param()

    Assert-Prerequisite

    $ChocoInstalled = Test-Chocolatey
    $RubyInstalled  = Test-ChocoPackage -Name 'ruby'

    Update-InstalledChocoPackage
    Update-InstalledRubyGem

    # first process all ruby gems
    $script:Packages | % {
        if ($_.Type -ieq 'RubyGem')
        {
            if (Test-RubyGem -Name $_.Name)
            {
                Uninstall-RubyGem -Name $_.Name 
            }
        }
    }

    # now process all choco packages
    $script:Packages | % {
        if ($_.Type -ieq 'Chocolatey')
        {
            if (Test-ChocoPackage -Name $_.Name)
            {
                Uninstall-ChocoPackage -Name $_.Name
            }

            if ($_.Path -ne $null)
            {
                Remove-Path -PathFragment $_.Path 
            }
        }
    }
}

#endregion Exports

Export-ModuleMember Install-Chocolatey, Uninstall-Chocolatey, Install-DevTool, Uninstall-DevTool