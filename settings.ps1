$scripts = "path\to\scripts"
$isAdmin = $false

Import-Module -Name "$scripts\path\to\module.ps1"

if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] “Administrator”)) {
    Write-Warning "Running as Administrator"
    $isAdmin = $true
}

function Get-LastSuccessColor {
    param(
        [bool]$lastSuccess
    )

    $color = @{
        Reset  = "`e[0m"
        Red    = "`e[31;1m"
        Green  = "`e[32;1m"
    }

    if ($lastSuccess -eq $false) {
        return $color.Red
    } else {
        return $color.Green
    }
}

function Get-LastCmdTime {
    $color = @{
        Green  = "`e[32;1m"
        Yellow = "`e[33;1m"
        Red    = "`e[31;1m"
        Grey   = "`e[37;0m"
        Reset  = "`e[0m"
    }

    $lastCmd = Get-History -Count 1
    if ($null -ne $lastCmd) {
        $cmdTime = $lastCmd.Duration.TotalMilliseconds
        $units = "ms"
        $timeColor = $color.Green
        if ($cmdTime -gt 250 -and $cmdTime -lt 1000)
        {
            $timeColor = $color.Yellow
        }
        elseif ($cmdTime -ge 1000)
        {
            $timeColor = $color.Red
            $units = "s"
            $cmdTime = $lastCmd.Duration.TotalSeconds
            if ($cmdTime -ge 60)
            {
                $units = "m"
                $cmdTIme = $lastCmd.Duration.TotalMinutes
            }
        }
 
        $lastCmdTime = "prev: $($color.Grey)[$timeColor$($cmdTime.ToString("#.##"))$units$($color.Grey)]$($color.Reset) "
    }

    return $lastCmdTime
}

function Get-GitBranch {
    $color = @{
        Green  = "`e[32;1m"
        Red    = "`e[31;1m"
        Grey   = "`e[37;0m"
        Reset  = "`e[0m"
    }

    $path = Get-Location
    while ($path -ne "") {

        if (Test-Path (Join-Path $path .git))
        {
            # need to do this so the stderr doesn't show up in $error
            $ErrorActionPreferenceOld = $ErrorActionPreference
            $ErrorActionPreference = 'Ignore'
            $branch = git rev-parse --abbrev-ref --symbolic-full-name '@{u}'
            $ErrorActionPreference = $ErrorActionPreferenceOld
 
            # handle case where branch is local
            if ($lastexitcode -ne 0 -or $null -eq $branch)
            {
                $branch = git rev-parse --abbrev-ref HEAD
            }
 
            $branchColor = $color.Green
 
            if ($branch -match "/master" -or $branch -match "/main")
            {
                $branchColor = $color.Red
            }

            $gitBranch = " $($color.Grey)[$branchColor$branch$($color.Grey)]$($color.Reset)"
            break
        }
 
        $path = Split-Path -Path $path -Parent
    }

    return $gitBranch
}

function Get-DisplayPath {
    $dirSep = [IO.Path]::DirectorySeparatorChar
    $pathComponents = $PWD.Path.Split($dirSep)
    if ($pathComponents.Count -le 3) {
        return $PWD.Path
    } else {
        return '…{0}{1}' -f $dirSep, ($pathComponents[-2, -1] -join $dirSep)
    }
}

function Get-TruncatedCurrentDirectory {
    $currentDirectory = $executionContext.SessionState.Path.CurrentLocation.Path
    $consoleWidth = [Console]::WindowWidth
    $maxPath = [int]($consoleWidth / 2)
    if ($currentDirectory.Length -gt $maxPath) {
        return "`u{2026}" + $currentDirectory.SubString($currentDirectory.Length - $maxPath)
    }
    return $currentDirectory
}

function prompt {
    $lastSuccess = $?
    $lastExit = Get-LastSuccessColor -lastSuccess $lastSuccess
    $lastCmdTime = Get-LastCmdTime
    $gitBranch = Get-GitBranch
    $displayPath = Get-DisplayPath
    $currentDirectory = Get-TruncatedCurrentDirectory

    $color = @{
        Reset  = "`e[0m"
        Red    = "`e[31;1m"
        Green  = "`e[32;1m"
        Magenta = "`e[34;1m"
    }

    $prefix = ""
    $PromptText = "$($color.Magenta)pwsh$($color.Reset)"

    if ($isAdmin -eq $true) {
        $prefix = "$($color.Red) ## ADMIN ## $($color.Reset)"
    } 

    return "$lastCmdTime$gitBranch`n$($lastExit)$PromptText % $prefix$($color.Green)$displayPath$($color.Reset)$('>' * ($nestedPromptLevel + 1)) "
}

Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key '(', '{', '[' `
    -BriefDescription InsertPairedBraces `
    -LongDescription "Insert matching braces" `
    -ScriptBlock {
    param($key, $arg)

    $closeChar = switch ($key.KeyChar) {
        '(' { [char]')'; break }
        '{' { [char]'}'; break }
        '[' { [char]']'; break }
    }

    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor - 1)
}

Set-PSReadLineKeyHandler -Key ')', ']', '}' `
    -BriefDescription SmartCloseBraces `
    -LongDescription "Insert closing brace or skip" `
    -ScriptBlock {
    param($key, $arg)

    $line = $null
    $cursor = $null
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

    if ($line[$cursor] -eq $key.KeyChar) {
        [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
    else {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
    }
}
