$ErrorActionPreference = "Stop"

# ============================================================
# Luxseen Blog Manager
# Publish / Hide / Restore / Delete
# ============================================================

$BlogRepo = $PSScriptRoot
$PostsDir = Join-Path $BlogRepo "content\posts"
$MainBranch = "main"

# ============================================================
# Basic functions
# ============================================================

function Pause-AndExit {
    param(
        [int]$Code = 0
    )

    Write-Host ""
    Read-Host "Press Enter to exit"
    exit $Code
}

function Show-Header {

    Clear-Host

    Write-Host ""
    Write-Host "========================================"
    Write-Host "        Luxseen Blog Manager"
    Write-Host "========================================"
    Write-Host ""
}

function Test-Environment {

    if (-not (Test-Path $BlogRepo)) {
        Write-Host "ERROR: Blog repository not found." -ForegroundColor Red
        Pause-AndExit 1
    }

    if (-not (Test-Path (Join-Path $BlogRepo "hugo.toml"))) {
        Write-Host "ERROR: hugo.toml not found." -ForegroundColor Red
        Write-Host ""
        Write-Host "Put luxseen-blog.ps1 in the personal-blog root folder."
        Pause-AndExit 1
    }

    if (-not (Test-Path (Join-Path $BlogRepo ".git"))) {
        Write-Host "ERROR: This folder is not a Git repository." -ForegroundColor Red
        Pause-AndExit 1
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: Git is not installed." -ForegroundColor Red
        Pause-AndExit 1
    }

    if (-not (Get-Command hugo -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: Hugo is not installed." -ForegroundColor Red
        Pause-AndExit 1
    }

    if (-not (Test-Path $PostsDir)) {
        New-Item -ItemType Directory -Path $PostsDir -Force | Out-Null
    }

    Set-Location $BlogRepo
}

function Sync-GitHub {

    Write-Host ""
    Write-Host "[SYNC] Pulling latest version from GitHub..." -ForegroundColor Cyan
    Write-Host ""

    git pull --ff-only origin $MainBranch

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: git pull failed." -ForegroundColor Red
        Write-Host ""
        Write-Host "Please resolve the Git problem first."

        Pause-AndExit 1
    }

    Write-Host ""
    Write-Host "GitHub sync completed." -ForegroundColor Green
}

function Select-MarkdownFile {

    param(
        [string]$Title,
        [string]$InitialDirectory
    )

    Add-Type -AssemblyName System.Windows.Forms

    $Dialog = New-Object System.Windows.Forms.OpenFileDialog

    $Dialog.Title = $Title
    $Dialog.Filter = "Markdown files (*.md)|*.md"
    $Dialog.Multiselect = $false

    if ($InitialDirectory -and (Test-Path $InitialDirectory)) {
        $Dialog.InitialDirectory = $InitialDirectory
    }

    $Result = $Dialog.ShowDialog()

    if ($Result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    return $Dialog.FileName
}

function Test-IsInsidePosts {

    param(
        [string]$FilePath
    )

    $PostsRoot = [System.IO.Path]::GetFullPath($PostsDir).TrimEnd("\") + "\"
    $FullFile = [System.IO.Path]::GetFullPath($FilePath)

    return $FullFile.StartsWith(
        $PostsRoot,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Test-HugoBuild {

    Write-Host ""
    Write-Host "[HUGO] Running production build test..." -ForegroundColor Cyan
    Write-Host ""

    hugo

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: Hugo build failed." -ForegroundColor Red
        Write-Host "Nothing was pushed to GitHub."

        return $false
    }

    Write-Host ""
    Write-Host "Hugo build passed." -ForegroundColor Green

    return $true
}

function Push-Change {

    param(
        [string]$RelativeFile,
        [string]$CommitMessage
    )

    Write-Host ""
    Write-Host "[GIT] Staging changes..." -ForegroundColor Cyan

    git add -A -- $RelativeFile

    git diff --cached --quiet

    if ($LASTEXITCODE -eq 0) {

        Write-Host ""
        Write-Host "No changes detected." -ForegroundColor Yellow

        return $false
    }

    Write-Host ""
    Write-Host "[GIT] Creating commit..." -ForegroundColor Cyan

    git commit -m $CommitMessage

    if ($LASTEXITCODE -ne 0) {

        Write-Host ""
        Write-Host "ERROR: git commit failed." -ForegroundColor Red

        return $false
    }

    Write-Host ""
    Write-Host "[GIT] Pushing to GitHub..." -ForegroundColor Cyan

    git push origin $MainBranch

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

    return $true
}

# ============================================================
# 1. Publish
# ============================================================

function Publish-Article {

    Show-Header

    Write-Host "ACTION: Publish Article" -ForegroundColor Green

    Sync-GitHub

    Write-Host ""
    Write-Host "Select the article from your Obsidian vault." -ForegroundColor Cyan

    $SourceFile = Select-MarkdownFile `
        -Title "Select Obsidian article to publish" `
        -InitialDirectory ""

    if (-not $SourceFile) {
        Write-Host ""
        Write-Host "Publishing cancelled."
        Pause-AndExit 0
    }

    $FileName = Split-Path $SourceFile -Leaf
    $TargetFile = Join-Path $PostsDir $FileName

    Write-Host ""
    Write-Host "Selected file:"
    Write-Host $SourceFile

    Write-Host ""
    Write-Host "[CHECK] Checking article front matter..." -ForegroundColor Cyan

    $Content = Get-Content -LiteralPath $SourceFile -Raw -Encoding UTF8

    if ($Content -notmatch '(?m)^title\s*:') {
        Write-Host "ERROR: Missing title property." -ForegroundColor Red
        Pause-AndExit 1
    }

    if ($Content -notmatch '(?m)^date\s*:') {
        Write-Host "ERROR: Missing date property." -ForegroundColor Red
        Pause-AndExit 1
    }

    if ($Content -notmatch '(?m)^categories\s*:') {
        Write-Host "ERROR: Missing categories property." -ForegroundColor Red
        Pause-AndExit 1
    }

    if ($Content -match '(?im)^draft\s*:\s*true\s*$') {

        Write-Host ""
        Write-Host "STOP: This article is still a draft." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Change:"
        Write-Host "draft: true"
        Write-Host ""
        Write-Host "to:"
        Write-Host "draft: false"

        Pause-AndExit 1
    }

    if ($Content -notmatch '(?im)^draft\s*:\s*false\s*$') {

        Write-Host ""
        Write-Host "STOP: draft: false was not found." -ForegroundColor Yellow
        Write-Host "Publishing cancelled for safety."

        Pause-AndExit 1
    }

    Write-Host ""
    Write-Host "Front matter check passed." -ForegroundColor Green

    if (Test-Path $TargetFile) {

        Write-Host ""
        Write-Host "An article with the same filename already exists." -ForegroundColor Yellow
        Write-Host ""
        Write-Host $FileName
        Write-Host ""

        $ConfirmUpdate = Read-Host "Type UPDATE to overwrite the Hugo copy"

        if ($ConfirmUpdate -ne "UPDATE") {
            Write-Host ""
            Write-Host "Publishing cancelled."
            Pause-AndExit 0
        }
    }

    Write-Host ""
    Write-Host "[COPY] Copying article into Hugo..." -ForegroundColor Cyan

    Copy-Item `
        -LiteralPath $SourceFile `
        -Destination $TargetFile `
        -Force

    Write-Host ""
    Write-Host "Copied to:"
    Write-Host $TargetFile

    if (-not (Test-HugoBuild)) {
        Pause-AndExit 1
    }

    $RelativeFile = "content/posts/$FileName"

    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)

    if (-not (Push-Change `
        -RelativeFile $RelativeFile `
        -CommitMessage "Publish article: $BaseName")) {

        Pause-AndExit 1
    }

    Write-Host ""
    Write-Host "========================================"
    Write-Host "       PUBLISH SUCCESSFUL" -ForegroundColor Green
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Article:"
    Write-Host $FileName
    Write-Host ""
    Write-Host "GitHub updated successfully."
    Write-Host "Cloudflare Pages will deploy automatically."
    Write-Host ""
    Write-Host "Website:"
    Write-Host "https://luxseen.com/"

    Pause-AndExit 0
}

# ============================================================
# 2. Hide
# ============================================================

function Hide-Article {

    Show-Header

    Write-Host "ACTION: Hide Article" -ForegroundColor Yellow

    Sync-GitHub

    $ArticlePath = Select-MarkdownFile `
        -Title "Select Luxseen article to hide" `
        -InitialDirectory $PostsDir

    if (-not $ArticlePath) {
        Write-Host ""
        Write-Host "Operation cancelled."
        Pause-AndExit 0
    }

    if (-not (Test-IsInsidePosts $ArticlePath)) {

        Write-Host ""
        Write-Host "ERROR: Select an article inside content/posts." -ForegroundColor Red

        Pause-AndExit 1
    }

    $FileName = Split-Path $ArticlePath -Leaf

    Write-Host ""
    Write-Host "Selected article:"
    Write-Host $FileName

    $Content = Get-Content `
        -LiteralPath $ArticlePath `
        -Raw `
        -Encoding UTF8

    if ($Content -match '(?im)^draft\s*:\s*true\s*$') {

        Write-Host ""
        Write-Host "This article is already hidden." -ForegroundColor Yellow

        Pause-AndExit 0
    }

    if ($Content -notmatch '(?im)^draft\s*:\s*false\s*$') {

        Write-Host ""
        Write-Host "ERROR: draft: false was not found." -ForegroundColor Red

        Pause-AndExit 1
    }

    $Content = [System.Text.RegularExpressions.Regex]::Replace(
        $Content,
        '(?im)^draft\s*:\s*false\s*$',
        'draft: true'
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $ArticlePath,
        $Content,
        $Utf8NoBom
    )

    Write-Host ""
    Write-Host "Changed to draft: true." -ForegroundColor Green

    if (-not (Test-HugoBuild)) {
        Pause-AndExit 1
    }

    $RelativeFile = $ArticlePath.Substring(
        $BlogRepo.Length + 1
    ).Replace("\", "/")

    if (-not (Push-Change `
        -RelativeFile $RelativeFile `
        -CommitMessage "Hide article: $FileName")) {

        Pause-AndExit 1
    }

    Write-Host ""
    Write-Host "========================================"
    Write-Host "         ARTICLE HIDDEN" -ForegroundColor Green
    Write-Host "========================================"
    Write-Host ""
    Write-Host "The article will disappear from Luxseen."
    Write-Host ""
    Write-Host "The Hugo file is still preserved."
    Write-Host "The Obsidian source is not changed."

    Pause-AndExit 0
}

# ============================================================
# 3. Restore
# ============================================================

function Restore-Article {

    Show-Header

    Write-Host "ACTION: Restore Article" -ForegroundColor Green

    Sync-GitHub

    $ArticlePath = Select-MarkdownFile `
        -Title "Select hidden Luxseen article to restore" `
        -InitialDirectory $PostsDir

    if (-not $ArticlePath) {
        Write-Host ""
        Write-Host "Operation cancelled."
        Pause-AndExit 0
    }

    if (-not (Test-IsInsidePosts $ArticlePath)) {

        Write-Host ""
        Write-Host "ERROR: Select an article inside content/posts." -ForegroundColor Red

        Pause-AndExit 1
    }

    $FileName = Split-Path $ArticlePath -Leaf

    $Content = Get-Content `
        -LiteralPath $ArticlePath `
        -Raw `
        -Encoding UTF8

    if ($Content -match '(?im)^draft\s*:\s*false\s*$') {

        Write-Host ""
        Write-Host "This article is already published." -ForegroundColor Yellow

        Pause-AndExit 0
    }

    if ($Content -notmatch '(?im)^draft\s*:\s*true\s*$') {

        Write-Host ""
        Write-Host "ERROR: draft: true was not found." -ForegroundColor Red

        Pause-AndExit 1
    }

    $Content = [System.Text.RegularExpressions.Regex]::Replace(
        $Content,
        '(?im)^draft\s*:\s*true\s*$',
        'draft: false'
    )

    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $ArticlePath,
        $Content,
        $Utf8NoBom
    )

    Write-Host ""
    Write-Host "Changed to draft: false." -ForegroundColor Green

    if (-not (Test-HugoBuild)) {
        Pause-AndExit 1
    }

    $RelativeFile = $ArticlePath.Substring(
        $BlogRepo.Length + 1
    ).Replace("\", "/")

    if (-not (Push-Change `
        -RelativeFile $RelativeFile `
        -CommitMessage "Restore article: $FileName")) {

        Pause-AndExit 1
    }

    Write-Host ""
    Write-Host "========================================"
    Write-Host "        ARTICLE RESTORED" -ForegroundColor Green
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Cloudflare Pages will redeploy automatically."
    Write-Host ""
    Write-Host "The article will appear on Luxseen again."

    Pause-AndExit 0
}

# ============================================================
# 4. Delete
# ============================================================

function Delete-Article {

    Show-Header

    Write-Host "ACTION: Delete Article" -ForegroundColor Red

    Sync-GitHub

    $ArticlePath = Select-MarkdownFile `
        -Title "Select Luxseen article to delete" `
        -InitialDirectory $PostsDir

    if (-not $ArticlePath) {
        Write-Host ""
        Write-Host "Operation cancelled."
        Pause-AndExit 0
    }

    if (-not (Test-IsInsidePosts $ArticlePath)) {

        Write-Host ""
        Write-Host "ERROR: Select an article inside content/posts." -ForegroundColor Red

        Pause-AndExit 1
    }

    $FileName = Split-Path $ArticlePath -Leaf

    $RelativeFile = $ArticlePath.Substring(
        $BlogRepo.Length + 1
    ).Replace("\", "/")

    Write-Host ""
    Write-Host "WARNING" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "You are about to delete this Hugo article:"
    Write-Host ""
    Write-Host $FileName
    Write-Host ""
    Write-Host "The Hugo copy will be moved to Windows Recycle Bin."
    Write-Host ""
    Write-Host "The original Obsidian article will NOT be deleted."
    Write-Host ""

    $ConfirmDelete = Read-Host "Type DELETE to continue"

    if ($ConfirmDelete -ne "DELETE") {

        Write-Host ""
        Write-Host "Deletion cancelled."

        Pause-AndExit 0
    }

    Add-Type -AssemblyName Microsoft.VisualBasic

    try {

        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $ArticlePath,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
    catch {

        Write-Host ""
        Write-Host "ERROR: Could not move the file to Recycle Bin." -ForegroundColor Red

        Pause-AndExit 1
    }

    Write-Host ""
    Write-Host "Hugo article moved to Recycle Bin." -ForegroundColor Green

    if (-not (Test-HugoBuild)) {
        Pause-AndExit 1
    }

    if (-not (Push-Change `
        -RelativeFile $RelativeFile `
        -CommitMessage "Delete article: $FileName")) {

        Pause-AndExit 1
    }

    Write-Host ""
    Write-Host "========================================"
    Write-Host "        ARTICLE DELETED" -ForegroundColor Green
    Write-Host "========================================"
    Write-Host ""
    Write-Host "GitHub has been updated."
    Write-Host "Cloudflare Pages will redeploy automatically."
    Write-Host ""
    Write-Host "The original Obsidian article is still preserved."

    Pause-AndExit 0
}

# ============================================================
# Main menu
# ============================================================

Show-Header

Test-Environment

Write-Host "Blog folder:"
Write-Host $BlogRepo

Write-Host ""
Write-Host "Choose an action:"
Write-Host ""
Write-Host "1 - Publish article"
Write-Host "2 - Hide article"
Write-Host "3 - Restore article"
Write-Host "4 - Delete article"
Write-Host "0 - Exit"
Write-Host ""

$Choice = Read-Host "Enter 1, 2, 3, 4 or 0"

switch ($Choice) {

    "1" {
        Publish-Article
    }

    "2" {
        Hide-Article
    }

    "3" {
        Restore-Article
    }

    "4" {
        Delete-Article
    }

    "0" {
        exit 0
    }

    default {

        Write-Host ""
        Write-Host "Invalid option." -ForegroundColor Red

        Pause-AndExit 1
    }
}