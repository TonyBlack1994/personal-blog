$ErrorActionPreference = "Stop"

# ============================================================
# Luxseen Blog Manager v1.2
# Windows PowerShell / Multi-PC
# ============================================================

$BlogRepo = $PSScriptRoot
$PostsDir = Join-Path $BlogRepo "content\posts"
$ImagesDir = Join-Path $BlogRepo "static\images\posts"
$Branch = "main"
$Website = "https://luxseen.com/"

$BackupRoot = Join-Path $env:LOCALAPPDATA "LuxseenBlog\DeletedPosts"
$ConfigRoot = Join-Path $env:APPDATA "LuxseenBlog"
$ManagerConfig = Join-Path $ConfigRoot "config.txt"


# ============================================================
# Pause
# ============================================================

function Wait-Menu {

    Write-Host ""
    Read-Host "Press Enter to continue"

}


# ============================================================
# Save UTF-8 without BOM
# ============================================================

function Save-Utf8NoBom {

    param(
        [string]$Path,
        [string]$Content
    )

    $Encoding = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        $Encoding
    )
}


# ============================================================
# Initialize
# ============================================================

function Initialize-Luxseen {

    Set-Location $BlogRepo

    if (-not (Test-Path (Join-Path $BlogRepo "hugo.toml"))) {

        Write-Host "ERROR: hugo.toml not found." -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Path (Join-Path $BlogRepo ".git"))) {

        Write-Host "ERROR: Git repository not found." -ForegroundColor Red
        exit 1
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {

        Write-Host "ERROR: Git is not installed." -ForegroundColor Red
        exit 1
    }

    if (-not (Get-Command hugo -ErrorAction SilentlyContinue)) {

        Write-Host "ERROR: Hugo is not installed." -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Path $PostsDir)) {

        New-Item `
            -ItemType Directory `
            -Path $PostsDir `
            -Force | Out-Null
    }

    if (-not (Test-Path $ImagesDir)) {

        New-Item `
            -ItemType Directory `
            -Path $ImagesDir `
            -Force | Out-Null
    }

    if (-not (Test-Path $BackupRoot)) {

        New-Item `
            -ItemType Directory `
            -Path $BackupRoot `
            -Force | Out-Null
    }

    if (-not (Test-Path $ConfigRoot)) {

        New-Item `
            -ItemType Directory `
            -Path $ConfigRoot `
            -Force | Out-Null
    }

    $CurrentBranch = git branch --show-current

    if ($CurrentBranch -ne $Branch) {

        Write-Host ""
        Write-Host "ERROR: Current branch is not main." -ForegroundColor Red
        Write-Host ""
        Write-Host "Current branch: $CurrentBranch"
        Write-Host ""
        exit 1
    }
}


# ============================================================
# Check working tree clean
# ============================================================

function Test-WorkingTreeClean {

    $Status = git status --porcelain

    if ($Status) {

        Write-Host ""
        Write-Host "STOP: Local changes were detected." -ForegroundColor Yellow
        Write-Host ""
        git status --short
        Write-Host ""
        Write-Host "Finish or push these changes before this operation."

        return $false
    }

    return $true
}


# ============================================================
# Sync GitHub
# ============================================================

function Sync-Repository {

    Write-Host ""
    Write-Host "[GIT] Checking GitHub..." -ForegroundColor Cyan

    if (-not (Test-WorkingTreeClean)) {

        return $false
    }

    git fetch origin $Branch

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: git fetch failed." -ForegroundColor Red

        return $false
    }

    git pull --ff-only origin $Branch

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: git pull failed." -ForegroundColor Red

        return $false
    }

    Write-Host ""
    Write-Host "GitHub sync completed." -ForegroundColor Green

    return $true
}


# ============================================================
# Hugo build test
# Build into temporary folder
# ============================================================

function Test-HugoBuild {

    Write-Host ""
    Write-Host "[HUGO] Running build test..." -ForegroundColor Cyan

    $TempBuild = Join-Path `
        $env:TEMP `
        ("luxseen-hugo-" + [Guid]::NewGuid().ToString())

    try {

        hugo --destination $TempBuild

        if ($LASTEXITCODE -ne 0) {

            Write-Host ""
            Write-Host "ERROR: Hugo build failed." -ForegroundColor Red

            return $false
        }

        Write-Host ""
        Write-Host "Hugo build passed." -ForegroundColor Green

        return $true
    }

    finally {

        if (Test-Path $TempBuild) {

            Remove-Item `
                $TempBuild `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
    }
}


# ============================================================
# Commit selected paths
# ============================================================

function Commit-And-Push {

    param(
        [string]$Message,
        [string[]]$Paths,
        [bool]$StageAll = $false
    )

    Write-Host ""
    Write-Host "[GIT] Staging changes..." -ForegroundColor Cyan

    if ($StageAll) {

        git add -A
    }
    else {

        foreach ($Path in $Paths) {

            git add -A -- $Path
        }
    }

    git diff --cached --quiet

    if ($LASTEXITCODE -eq 0) {

        Write-Host ""
        Write-Host "No changes detected." -ForegroundColor Yellow

        return $false
    }

    Write-Host ""
    Write-Host "[GIT] Creating commit..." -ForegroundColor Cyan

    git commit -m $Message

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: git commit failed." -ForegroundColor Red

        return $false
    }

    Write-Host ""
    Write-Host "[GIT] Pushing to GitHub..." -ForegroundColor Cyan

    git push origin $Branch

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: git push failed." -ForegroundColor Red
        Write-Host ""
        Write-Host "The commit exists locally."
        Write-Host "Retry later with:"
        Write-Host ""
        Write-Host "git push origin main"

        return $false
    }

    Write-Host ""
    Write-Host "GitHub updated successfully." -ForegroundColor Green
    Write-Host "Cloudflare will deploy automatically."

    return $true
}


# ============================================================
# Select article
# ============================================================

function Select-Article {

    $Files = @(
        Get-ChildItem `
            $PostsDir `
            -Filter "*.md" `
            -File |
        Sort-Object Name
    )

    if ($Files.Count -eq 0) {

        Write-Host ""
        Write-Host "No articles found." -ForegroundColor Yellow

        return $null
    }

    Write-Host ""

    for ($i = 0; $i -lt $Files.Count; $i++) {

        Write-Host "$($i + 1). $($Files[$i].Name)"
    }

    Write-Host ""

    $InputNumber = Read-Host "Select article number"

    $Number = 0

    if (-not [int]::TryParse($InputNumber, [ref]$Number)) {

        Write-Host ""
        Write-Host "Invalid number." -ForegroundColor Red

        return $null
    }

    if (($Number -lt 1) -or ($Number -gt $Files.Count)) {

        Write-Host ""
        Write-Host "Invalid selection." -ForegroundColor Red

        return $null
    }

    return $Files[$Number - 1]
}


# ============================================================
# 1. Publish Article
# ============================================================

function Publish-Article {

    if (-not (Sync-Repository)) {

        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $Dialog = New-Object System.Windows.Forms.OpenFileDialog

    $Dialog.Title = "Select Obsidian article"
    $Dialog.Filter = "Markdown files (*.md)|*.md"
    $Dialog.Multiselect = $false

    $Result = $Dialog.ShowDialog()

    if ($Result -ne [System.Windows.Forms.DialogResult]::OK) {

        Write-Host ""
        Write-Host "Publishing cancelled."

        return
    }

    $Source = $Dialog.FileName
    $Name = Split-Path $Source -Leaf
    $Target = Join-Path $PostsDir $Name

    Write-Host ""
    Write-Host "Selected:"
    Write-Host $Source

    $Content = Get-Content `
        -LiteralPath $Source `
        -Raw `
        -Encoding UTF8

    if ($Content -notmatch '(?m)^title\s*:') {

        Write-Host ""
        Write-Host "ERROR: Missing title." -ForegroundColor Red

        return
    }

    if ($Content -notmatch '(?m)^date\s*:') {

        Write-Host ""
        Write-Host "ERROR: Missing date." -ForegroundColor Red

        return
    }

    if ($Content -notmatch '(?m)^categories\s*:') {

        Write-Host ""
        Write-Host "ERROR: Missing categories." -ForegroundColor Red

        return
    }

    if ($Content -match '(?im)^draft\s*:\s*true\s*$') {

        Write-Host ""
        Write-Host "STOP: Article is still draft: true." -ForegroundColor Yellow

        return
    }

    if ($Content -notmatch '(?im)^draft\s*:\s*false\s*$') {

        Write-Host ""
        Write-Host "STOP: draft: false was not found." -ForegroundColor Yellow

        return
    }

    if (Test-Path $Target) {

        Write-Host ""
        Write-Host "Article already exists:" -ForegroundColor Yellow
        Write-Host $Name
        Write-Host ""

        $Confirm = Read-Host "Type UPDATE to overwrite"

        if ($Confirm -ne "UPDATE") {

            Write-Host "Publishing cancelled."

            return
        }
    }

    Copy-Item `
        -LiteralPath $Source `
        -Destination $Target `
        -Force

    if (-not (Test-HugoBuild)) {

        return
    }

    $RelativePath = "content/posts/$Name"

    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($Name)

    Commit-And-Push `
        -Message "Publish article: $BaseName" `
        -Paths @($RelativePath) | Out-Null

    Write-Host ""
    Write-Host "PUBLISH COMPLETED" -ForegroundColor Green
}


# ============================================================
# 2. Delete Article
# ============================================================

function Delete-Article {

    if (-not (Sync-Repository)) {

        return
    }

    $File = Select-Article

    if ($null -eq $File) {

        return
    }

    Write-Host ""
    Write-Host "WARNING" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Article:"
    Write-Host $File.Name
    Write-Host ""

    $Confirm = Read-Host "Type DELETE to confirm"

    if ($Confirm -ne "DELETE") {

        Write-Host ""
        Write-Host "Deletion cancelled."

        return
    }

    $Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

    $BackupName = $Timestamp + "__" + $File.Name

    $BackupPath = Join-Path $BackupRoot $BackupName

    Copy-Item `
        -LiteralPath $File.FullName `
        -Destination $BackupPath `
        -Force

    Write-Host ""
    Write-Host "Backup created:"
    Write-Host $BackupPath

    $RelativePath = "content/posts/$($File.Name)"

    Remove-Item `
        -LiteralPath $File.FullName `
        -Force

    if (-not (Test-HugoBuild)) {

        Write-Host ""
        Write-Host "Hugo failed. Restoring deleted file..." -ForegroundColor Yellow

        Copy-Item `
            -LiteralPath $BackupPath `
            -Destination (Join-Path $PostsDir $File.Name) `
            -Force

        return
    }

    Commit-And-Push `
        -Message "Delete article: $($File.Name)" `
        -Paths @($RelativePath) | Out-Null

    Write-Host ""
    Write-Host "DELETE COMPLETED" -ForegroundColor Green
}


# ============================================================
# 3. Hide Article
# ============================================================

function Hide-Article {

    if (-not (Sync-Repository)) {

        return
    }

    $File = Select-Article

    if ($null -eq $File) {

        return
    }

    $Text = Get-Content `
        -LiteralPath $File.FullName `
        -Raw `
        -Encoding UTF8

    if ($Text -match '(?im)^draft\s*:\s*true\s*$') {

        Write-Host ""
        Write-Host "Article is already hidden." -ForegroundColor Yellow

        return
    }

    if ($Text -notmatch '(?im)^draft\s*:\s*false\s*$') {

        Write-Host ""
        Write-Host "ERROR: draft: false was not found." -ForegroundColor Red

        return
    }

    $Text = [Regex]::Replace(
        $Text,
        '(?im)^draft\s*:\s*false\s*$',
        'draft: true'
    )

    Save-Utf8NoBom `
        -Path $File.FullName `
        -Content $Text

    if (-not (Test-HugoBuild)) {

        return
    }

    $RelativePath = "content/posts/$($File.Name)"

    Commit-And-Push `
        -Message "Hide article: $($File.Name)" `
        -Paths @($RelativePath) | Out-Null

    Write-Host ""
    Write-Host "ARTICLE HIDDEN" -ForegroundColor Green
}


# ============================================================
# 4. Restore Article
# ============================================================

function Restore-Article {

    if (-not (Sync-Repository)) {

        return
    }

    $File = Select-Article

    if ($null -eq $File) {

        return
    }

    $Text = Get-Content `
        -LiteralPath $File.FullName `
        -Raw `
        -Encoding UTF8

    if ($Text -match '(?im)^draft\s*:\s*false\s*$') {

        Write-Host ""
        Write-Host "Article is already published." -ForegroundColor Yellow

        return
    }

    if ($Text -notmatch '(?im)^draft\s*:\s*true\s*$') {

        Write-Host ""
        Write-Host "ERROR: draft: true was not found." -ForegroundColor Red

        return
    }

    $Text = [Regex]::Replace(
        $Text,
        '(?im)^draft\s*:\s*true\s*$',
        'draft: false'
    )

    Save-Utf8NoBom `
        -Path $File.FullName `
        -Content $Text

    if (-not (Test-HugoBuild)) {

        return
    }

    $RelativePath = "content/posts/$($File.Name)"

    Commit-And-Push `
        -Message "Restore article: $($File.Name)" `
        -Paths @($RelativePath) | Out-Null

    Write-Host ""
    Write-Host "ARTICLE RESTORED" -ForegroundColor Green
}


# ============================================================
# 5. List Posts
# ============================================================

function List-Posts {

    $Files = @(
        Get-ChildItem `
            $PostsDir `
            -Filter "*.md" `
            -File |
        Sort-Object Name
    )

    Write-Host ""
    Write-Host "========== Luxseen Posts ==========" -ForegroundColor Cyan
    Write-Host ""

    if ($Files.Count -eq 0) {

        Write-Host "No posts found."

        return
    }

    foreach ($File in $Files) {

        $Text = Get-Content `
            -LiteralPath $File.FullName `
            -Raw `
            -Encoding UTF8

        $Status = "UNKNOWN"
        $Title = ""

        if ($Text -match '(?im)^draft\s*:\s*true\s*$') {

            $Status = "DRAFT"
        }

        if ($Text -match '(?im)^draft\s*:\s*false\s*$') {

            $Status = "PUBLISHED"
        }

        if ($Text -match '(?m)^title\s*:\s*["'']?(.*?)["'']?\s*$') {

            $Title = $Matches[1]
        }

        Write-Host "[$Status] $($File.Name)"

        if (-not [string]::IsNullOrWhiteSpace($Title)) {

            Write-Host "          $Title"
        }
    }
}


# ============================================================
# 6. Sync GitHub
# ============================================================

function Sync-Only {

    Sync-Repository | Out-Null
}


# ============================================================
# 7. Local Preview
# ============================================================

function Preview-Site {

    Write-Host ""
    Write-Host "Starting Hugo server..." -ForegroundColor Cyan

    $Command = "Set-Location '$BlogRepo'; hugo server"

    Start-Process `
        powershell `
        -ArgumentList "-NoExit", "-Command", $Command

    Start-Sleep -Seconds 2

    Start-Process "http://localhost:1313/"

    Write-Host ""
    Write-Host "Preview opened in browser." -ForegroundColor Green
}


# ============================================================
# 8. Push Website Changes
# ============================================================

function Update-Website {

    Write-Host ""
    Write-Host "[GIT] Checking remote version..." -ForegroundColor Cyan

    git fetch origin $Branch

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: git fetch failed." -ForegroundColor Red

        return
    }

    $Behind = git rev-list --count "HEAD..origin/$Branch"

    if ([int]$Behind -gt 0) {

        Write-Host ""
        Write-Host "STOP: GitHub contains newer commits." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "This computer is behind GitHub by $Behind commit(s)."
        Write-Host ""
        Write-Host "Do not push yet."
        Write-Host "Review your local changes first."

        return
    }

    if (-not (Test-HugoBuild)) {

        return
    }

    Commit-And-Push `
        -Message "Update website" `
        -Paths @() `
        -StageAll $true | Out-Null
}


# ============================================================
# 9. Open Website
# ============================================================

function Open-Website {

    Start-Process $Website
}


# ============================================================
# 10. Git Status
# ============================================================

function Show-GitStatus {

    Write-Host ""
    Write-Host "========== Git Status ==========" -ForegroundColor Cyan
    Write-Host ""

    git fetch origin $Branch

    Write-Host ""
    git status

    Write-Host ""
    Write-Host "Local commit:"
    git log -1 --oneline

    $Ahead = git rev-list --count "origin/$Branch..HEAD"
    $Behind = git rev-list --count "HEAD..origin/$Branch"

    Write-Host ""
    Write-Host "Ahead : $Ahead"
    Write-Host "Behind: $Behind"
}


# ============================================================
# 11. Search Article
# ============================================================

function Search-Article {

    $Keyword = Read-Host "Search keyword"

    if ([string]::IsNullOrWhiteSpace($Keyword)) {

        return
    }

    Write-Host ""
    Write-Host "Search results:" -ForegroundColor Cyan
    Write-Host ""

    $Results = @(
        Get-ChildItem `
            $PostsDir `
            -Filter "*.md" `
            -File |
        Select-String `
            -Pattern $Keyword `
            -SimpleMatch
    )

    if ($Results.Count -eq 0) {

        Write-Host "No results."

        return
    }

    foreach ($Result in $Results) {

        Write-Host "$($Result.Path):$($Result.LineNumber)"
        Write-Host $Result.Line
        Write-Host ""
    }
}


# ============================================================
# Get Obsidian Draft Folder
# ============================================================

function Get-DraftFolder {

    if (Test-Path $ManagerConfig) {

        $SavedPath = Get-Content `
            $ManagerConfig `
            -Raw `
            -ErrorAction SilentlyContinue

        $SavedPath = $SavedPath.Trim()

        if (Test-Path $SavedPath) {

            return $SavedPath
        }
    }

    Add-Type -AssemblyName System.Windows.Forms

    $Dialog = New-Object System.Windows.Forms.FolderBrowserDialog

    $Dialog.Description = "Select your Obsidian Blog or Drafts folder"

    $Result = $Dialog.ShowDialog()

    if ($Result -ne [System.Windows.Forms.DialogResult]::OK) {

        return $null
    }

    $Folder = $Dialog.SelectedPath

    Save-Utf8NoBom `
        -Path $ManagerConfig `
        -Content $Folder

    return $Folder
}


# ============================================================
# 12. New Obsidian Draft
# ============================================================

function New-BlogDraft {

    $DraftFolder = Get-DraftFolder

    if ([string]::IsNullOrWhiteSpace($DraftFolder)) {

        Write-Host ""
        Write-Host "Cancelled."

        return
    }

    Write-Host ""
    $Title = Read-Host "Article title"

    if ([string]::IsNullOrWhiteSpace($Title)) {

        Write-Host "Title cannot be empty."

        return
    }

    $Category = Read-Host "Category"
    $Subcategory = Read-Host "Subcategory"
    $TagsInput = Read-Host "Tags separated by comma"
    $Description = Read-Host "Description"

    $SafeTitle = $Title

    foreach ($Char in [System.IO.Path]::GetInvalidFileNameChars()) {

        $SafeTitle = $SafeTitle.Replace(
            $Char.ToString(),
            ""
        )
    }

    $SafeTitle = $SafeTitle.Trim()

    if ([string]::IsNullOrWhiteSpace($SafeTitle)) {

        $SafeTitle = Get-Date -Format "yyyyMMdd-HHmmss"
    }

    $FileName = (Get-Date -Format "yyyyMMdd") + "-" + $SafeTitle + ".md"

    $DraftPath = Join-Path $DraftFolder $FileName

    if (Test-Path $DraftPath) {

        Write-Host ""
        Write-Host "Draft already exists:" -ForegroundColor Yellow
        Write-Host $DraftPath

        return
    }

    $TagLines = ""

    if (-not [string]::IsNullOrWhiteSpace($TagsInput)) {

        $Tags = $TagsInput.Split(",")

        foreach ($Tag in $Tags) {

            $CleanTag = $Tag.Trim()

            if (-not [string]::IsNullOrWhiteSpace($CleanTag)) {

                $TagLines += "  - $CleanTag`r`n"
            }
        }
    }

    $Date = Get-Date -Format "yyyy-MM-dd"

    $Content = @"
---
title: "$Title"
date: $Date
draft: true

categories:
  - $Category

subcategories:
  - $Subcategory

tags:
$TagLines
description: "$Description"
---

# $Title

## Background


## Problem


## Analysis


## Practice


## Result


## Thoughts


## Summary

"@

    Save-Utf8NoBom `
        -Path $DraftPath `
        -Content $Content

    Write-Host ""
    Write-Host "Draft created:" -ForegroundColor Green
    Write-Host $DraftPath

    Start-Process explorer.exe `
        -ArgumentList "/select,`"$DraftPath`""
}


# ============================================================
# 13. Add Article Image
# ============================================================

function Add-ArticleImage {

    if (-not (Sync-Repository)) {

        return
    }

    Add-Type -AssemblyName System.Windows.Forms

    $Dialog = New-Object System.Windows.Forms.OpenFileDialog

    $Dialog.Title = "Select article image"
    $Dialog.Filter = "Images|*.png;*.jpg;*.jpeg;*.webp;*.gif"
    $Dialog.Multiselect = $false

    $Result = $Dialog.ShowDialog()

    if ($Result -ne [System.Windows.Forms.DialogResult]::OK) {

        return
    }

    $Source = $Dialog.FileName

    $Year = Get-Date -Format "yyyy"

    $YearDir = Join-Path $ImagesDir $Year

    if (-not (Test-Path $YearDir)) {

        New-Item `
            -ItemType Directory `
            -Path $YearDir `
            -Force | Out-Null
    }

    $OriginalName = [System.IO.Path]::GetFileNameWithoutExtension($Source)
    $Extension = [System.IO.Path]::GetExtension($Source).ToLower()

    $SafeName = $OriginalName -replace '[^a-zA-Z0-9\-_]', '-'

    if ([string]::IsNullOrWhiteSpace($SafeName)) {

        $SafeName = "image"
    }

    $NewName = `
        (Get-Date -Format "yyyyMMdd-HHmmss") +
        "-" +
        $SafeName +
        $Extension

    $Target = Join-Path $YearDir $NewName

    Copy-Item `
        -LiteralPath $Source `
        -Destination $Target `
        -Force

    if (-not (Test-HugoBuild)) {

        return
    }

    $RelativeGitPath = "static/images/posts/$Year/$NewName"

    Commit-And-Push `
        -Message "Add article image: $NewName" `
        -Paths @($RelativeGitPath) | Out-Null

    $MarkdownPath = "/images/posts/$Year/$NewName"

    $Markdown = "![image]($MarkdownPath)"

    Set-Clipboard $Markdown

    Write-Host ""
    Write-Host "Image uploaded." -ForegroundColor Green
    Write-Host ""
    Write-Host "Markdown copied to clipboard:"
    Write-Host ""
    Write-Host $Markdown
}


# ============================================================
# 14. Restore Deleted Backup
# ============================================================

function Restore-DeletedBackup {

    if (-not (Sync-Repository)) {

        return
    }

    $Backups = @(
        Get-ChildItem `
            $BackupRoot `
            -Filter "*.md" `
            -File |
        Sort-Object LastWriteTime -Descending
    )

    if ($Backups.Count -eq 0) {

        Write-Host ""
        Write-Host "No deleted backups found."

        return
    }

    Write-Host ""

    for ($i = 0; $i -lt $Backups.Count; $i++) {

        Write-Host "$($i + 1). $($Backups[$i].Name)"
    }

    Write-Host ""

    $InputNumber = Read-Host "Select backup number"

    $Number = 0

    if (-not [int]::TryParse($InputNumber, [ref]$Number)) {

        Write-Host "Invalid number."

        return
    }

    if (($Number -lt 1) -or ($Number -gt $Backups.Count)) {

        Write-Host "Invalid selection."

        return
    }

    $Backup = $Backups[$Number - 1]

    $Parts = $Backup.Name -split "__", 2

    if ($Parts.Count -ne 2) {

        Write-Host ""
        Write-Host "Invalid backup filename." -ForegroundColor Red

        return
    }

    $OriginalName = $Parts[1]

    $Target = Join-Path $PostsDir $OriginalName

    if (Test-Path $Target) {

        Write-Host ""
        Write-Host "Article already exists:" -ForegroundColor Yellow
        Write-Host $OriginalName

        return
    }

    Copy-Item `
        -LiteralPath $Backup.FullName `
        -Destination $Target `
        -Force

    if (-not (Test-HugoBuild)) {

        Remove-Item `
            -LiteralPath $Target `
            -Force `
            -ErrorAction SilentlyContinue

        return
    }

    $RelativePath = "content/posts/$OriginalName"

    Commit-And-Push `
        -Message "Restore deleted article: $OriginalName" `
        -Paths @($RelativePath) | Out-Null

    Write-Host ""
    Write-Host "BACKUP RESTORED" -ForegroundColor Green
}


# ============================================================
# 15. Open Blog Folder
# ============================================================

function Open-BlogFolder {

    Start-Process explorer.exe $BlogRepo
}


# ============================================================
# Main
# ============================================================

Initialize-Luxseen

while ($true) {

    Clear-Host

    Write-Host ""
    Write-Host "========================================"
    Write-Host "        Luxseen Blog Manager v1.2"
    Write-Host "========================================"
    Write-Host ""

    Write-Host "1.  Publish Article"
    Write-Host "2.  Delete Article"
    Write-Host "3.  Hide Article"
    Write-Host "4.  Restore Article"
    Write-Host "5.  List Posts"
    Write-Host "6.  Sync GitHub"
    Write-Host "7.  Local Preview"
    Write-Host "8.  Push Website Changes"
    Write-Host "9.  Open Website"
    Write-Host "10. Git Status"
    Write-Host "11. Search Article"
    Write-Host "12. New Obsidian Draft"
    Write-Host "13. Add Article Image"
    Write-Host "14. Restore Deleted Backup"
    Write-Host "15. Open Blog Folder"
    Write-Host ""
    Write-Host "0.  Exit"
    Write-Host ""

    $Choice = Read-Host "Select"

    switch ($Choice) {

        "1" {
            Publish-Article
        }

        "2" {
            Delete-Article
        }

        "3" {
            Hide-Article
        }

        "4" {
            Restore-Article
        }

        "5" {
            List-Posts
        }

        "6" {
            Sync-Only
        }

        "7" {
            Preview-Site
        }

        "8" {
            Update-Website
        }

        "9" {
            Open-Website
        }

        "10" {
            Show-GitStatus
        }

        "11" {
            Search-Article
        }

        "12" {
            New-BlogDraft
        }

        "13" {
            Add-ArticleImage
        }

        "14" {
            Restore-DeletedBackup
        }

        "15" {
            Open-BlogFolder
        }

        "0" {
            exit
        }

        default {
            Write-Host ""
            Write-Host "Invalid choice." -ForegroundColor Red
        }
    }

    Wait-Menu
}