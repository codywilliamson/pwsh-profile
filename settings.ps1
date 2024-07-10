$scripts = "totallyDidntPutMyPath/Here"
$isAdmin = $false

# Import-Module -Name "$scripts\path\to\module.ps1"

if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] “Administrator”)) {
    Write-Warning "Running as Administrator"
    $isAdmin = $true
}

function Get-LastSuccessColor {
    param(
        [bool]$lastSuccess
    )

    $color = @{
        Reset = "`e[0m"
        Red   = "`e[31;1m"
        Green = "`e[32;1m"
    }

    if ($lastSuccess -eq $false) {
        return $color.Red
    }
    else {
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
        if ($cmdTime -gt 250 -and $cmdTime -lt 1000) {
            $timeColor = $color.Yellow
        }
        elseif ($cmdTime -ge 1000) {
            $timeColor = $color.Red
            $units = "s"
            $cmdTime = $lastCmd.Duration.TotalSeconds
            if ($cmdTime -ge 60) {
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
        Green = "`e[32;1m"
        Red   = "`e[31;1m"
        Grey  = "`e[37;0m"
        Reset = "`e[0m"
    }

    $path = Get-Location
    while ($path -ne "") {

        if (Test-Path (Join-Path $path .git)) {
            # need to do this so the stderr doesn't show up in $error
            $ErrorActionPreferenceOld = $ErrorActionPreference
            $ErrorActionPreference = 'Ignore'
            $branch = git rev-parse --abbrev-ref --symbolic-full-name '@{u}'
            $ErrorActionPreference = $ErrorActionPreferenceOld
 
            # handle case where branch is local
            if ($lastexitcode -ne 0 -or $null -eq $branch) {
                $branch = git rev-parse --abbrev-ref HEAD
            }
 
            $branchColor = $color.Green
 
            if ($branch -match "/master" -or $branch -match "/main") {
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
    }
    else {
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

function tree {
    <#
    .SYNOPSIS
    Prints a directory's subtree structure, optionally with exclusions.

    .DESCRIPTION
    Prints a given directory's subdirectory structure recursively in tree form,
    so as to visualize the directory hierarchy similar to cmd.exe's built-in
    'tree' command, but with the added ability to exclude subtrees by directory
    names.

    NOTE: Symlinks to directories are not followed; a warning to that effect is
            issued.

    .PARAMETER Path
    The target directory path; defaults to the current directory.
    You may specify a wildcard pattern, but it must resolve to a single directory.

    .PARAMETER Exclude
    One or more directory names that should be excluded from the output; wildcards
    are permitted. Any directory that matches anywhere in the target hierarchy
    is excluded, along with its subtree.
    If -IncludeFiles is also specified, the exclusions are applied to the files'
    names as well.

    .PARAMETER IncludeFiles
    By default, only directories are printed; use this switch to print files
    as well.

    .PARAMETER Ascii
    Uses ASCII characters to visualize the tree structure; by default, graphical
    characters from the OEM character set are used.

    .PARAMETER IndentCount
    Specifies how many characters to use to represent each level of the hierarchy.
    Defaults to 4.

    .PARAMETER Force
    Includes hidden items in the output; by default, they're ignored.

    .NOTES
    Directory symlinks are NOT followed, and a warning to that effect is issued.

    .EXAMPLE
    tree

    Prints the current directory's subdirectory hierarchy.

    .EXAMPLE
    tree ~/Projects -Ascii -Force -Exclude node_modules, .git

    Prints the specified directory's subdirectory hierarchy using ASCII characters
    for visualization, including hidden subdirectories, but excluding the
    subtrees of any directories named 'node_modules' or '.git'.
    #>

    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Position = 0)]
        [string] $Path = '.',
        [string[]] $Exclude,
        [ValidateRange(1, [int]::MaxValue)]
        [int] $IndentCount = 4,
        [switch] $Ascii,
        [switch] $Force,
        [switch] $IncludeFiles
    )

    # Embedded recursive helper function for drawing the tree.
    function _tree_helper {

        param(
            [string]$literalPath,
            [string]$prefix
        )

        # Get all subdirs. and, if requested, also files.
        $items = Get-ChildItem -Directory:(-not $IncludeFiles) -LiteralPath $LiteralPath -Force:$Force

        # Apply exclusion filter(s), if specified.
        if ($Exclude -and $items) {
            $items = $items.Where({ $name = $_.Name; -not $Exclude.Where({ $name -like $_ }, 'First') })
        }

        if (-not $items) { return } # no subdirs. / files, we're done

        $i = 0
        foreach ($item in $items) {
            $isLastSibling = ++ $i -eq $items.Count
            # Print this dir.
            $prefix + $(if ($isLastSibling) { $chars.last } else { $chars.interior }) + $chars.hline * ($indentCount - 1) + $item.Name
            # Recurse, if it's a subdir (rather than a file).
            if ($item.PSIsContainer) {
                if ($item.LinkType) { Write-Warning "Not following dir. symlink: $item"; continue }
                $subPrefix = $prefix + $(if ($isLastSibling) { $chars.space * $indentCount } else { $chars.vline + $chars.space * ($indentCount - 1) })
                _tree_helper $item.FullName $subPrefix
            }
        }
    } # function _tree_helper

    # Hashtable of characters used to draw the structure
    $ndx = [bool] $Ascii
    $chars = @{
        interior = ('├', '+')[$ndx]
        last     = ('└', '\\')[$ndx]
        hline    = ('─', '-')[$ndx]
        vline    = ('|', '|')[$ndx]
        space    = " "
    }

    # Resolve the path to a full path and verify its existence and expected type.
    $literalPath = (Resolve-Path $Path).Path
    if (-not $literalPath -or -not (Test-Path -PathType Container -LiteralPath $literalPath) -or $literalPath.Count -gt 1) { throw "$Path must resolve to a single, existing directory." }

    # Print the target path.
    $literalPath

    # Invoke the helper function to draw the tree.
    _tree_helper $literalPath
}

function prompt {
    $lastSuccess = $?
    $lastExit = Get-LastSuccessColor -lastSuccess $lastSuccess
    $lastCmdTime = Get-LastCmdTime
    $gitBranch = Get-GitBranch
    $displayPath = Get-DisplayPath
    $currentDirectory = Get-TruncatedCurrentDirectory

    $color = @{
        Reset   = "`e[0m"
        Red     = "`e[31;1m"
        Green   = "`e[32;1m"
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


Import-Module -Name "$scripts\Wait-WithProgress.psm1"
Set-Alias -Name wwp -Value Wait-WithProgress -Scope Global
Set-Alias -Name wws -Value Wait-WithSpinner -Scope Global
Set-Alias -Name wwd -Value Wait-WithMovingDots -Scope Global
Set-Alias -Name wwb -Value Wait-WithMovingBrackets -Scope Global
Set-Alias -Name wbb -Value Wait-WithBouncingBar -Scope Global

Import-Module -Name "$scripts\WebReqWrapper\WebReqWrapper.psd1"
Set-Alias -Name gr -Value Invoke-GetRequest -Scope Global

Import-Module -Name "$scripts\Get-SVG.psm1"