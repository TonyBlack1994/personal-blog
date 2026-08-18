$ErrorActionPreference = "Stop"

# ==============================
# Luxseen Blog Publisher
# Cross-PC Version
# ==============================

$BlogRepo = $PSScriptRoot
$PostsDir = Join-Path $BlogRepo "content\posts"
$MainBranch = "main"

Write-Host ""
Write-Host "========================================"
Write-Host "       Luxseen Blog Publisher"
Write-Host "========================================"
Write-Host ""

Write-Host "Blog repository:"
Write-Host $BlogRepo
Write-Host ""

# ==============================
# 1. Check environment
# ==============================

if (-not (Test-Path $BlogRepo)) {
    Write-Host "ERROR: Blog repository not found." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Path (Join-Path $BlogRepo "hugo.toml"))) {
    Write-Host "ERROR: hugo.toml not found." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please place publish-blog.ps1 in the personal-blog root folder."
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Path (Join-Path $BlogRepo ".git"))) {
    Write-Host "ERROR: This folder is not a Git repository." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Git is not installed or not available in PATH." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Get-Command hugo -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Hugo is not installed or not available in PATH." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if (-not (Test-Path $PostsDir)) {
    New-Item -ItemType Directory -Path $PostsDir -Force | Out-Null
}

Set-Location $BlogRepo

# ==============================
# 2. Check branch
# ==============================

$CurrentBranch = git branch --show-current

if ($CurrentBranch -ne $MainBranch) {
    Write-Host ""
    Write-Host "ERROR: Current Git branch is not main." -ForegroundColor Red
    Write-Host ""
    Write-Host "Current branch:"
    Write-Host $CurrentBranch
    Write-Host ""
    Write-Host "Please switch to main first:"
    Write-Host "git checkout main"
    Read-Host "Press Enter to exit"
    exit 1
}

# ==============================
# 3. Pull latest version
# ==============================

Write-Host "[1/7] Pulling latest version from GitHub..." -ForegroundColor Cyan

git pull --ff-only origin $MainBranch

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: git pull failed." -ForegroundColor Red
    Write-Host ""
    Write-Host "Please resolve the Git issue before publishing."
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "GitHub sync completed." -ForegroundColor Green

# ==============================
# 4. Select Markdown file
# ==============================

Write-Host ""
Write-Host "[2/7] Select an Obsidian Markdown file..." -ForegroundColor Cyan

Add-Type -AssemblyName System.Windows.Forms

$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Title = "Select article to publish to Luxseen"
$dialog.Filter = "Markdown files (*.md)|*.md"
$dialog.Multiselect = $false

$result = $dialog.ShowDialog()

if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host ""
    Write-Host "Publishing cancelled."
    exit 0
}

$SourceFile = $dialog.FileName
$FileName = Split-Path $SourceFile -Leaf
$TargetFile = Join-Path $PostsDir $FileName

Write-Host ""
Write-Host "Selected file:" -ForegroundColor Green
Write-Host $SourceFile

# ==============================
# 5. Check front matter
# ==============================

Write-Host ""
Write-Host "[3/7] Checking article front matter..." -ForegroundColor Cyan

$content = Get-Content -LiteralPath $SourceFile -Raw -Encoding UTF8

if ($content -notmatch '(?m)^title\s*:') {
    Write-Host "ERROR: Missing title property." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if ($content -notmatch '(?m)^date\s*:') {
    Write-Host "ERROR: Missing date property." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if ($content -notmatch '(?m)^categories\s*:') {
    Write-Host "ERROR: Missing categories property." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

if ($content -match '(?im)^draft\s*:\s*true\s*$') {
    Write-Host ""
    Write-Host "STOP: This article is still a draft." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Change:"
    Write-Host "draft: true"
    Write-Host ""
    Write-Host "to:"
    Write-Host "draft: false"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

if ($content -notmatch '(?im)^draft\s*:\s*false\s*$') {
    Write-Host ""
    Write-Host "STOP: draft: false was not found." -ForegroundColor Yellow
    Write-Host "Publishing cancelled for safety."
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "Front matter check passed." -ForegroundColor Green

# ==============================
# 6. Copy article into Hugo
# ==============================

Write-Host ""
Write-Host "[4/7] Copying article into Hugo..." -ForegroundColor Cyan

$SourceFullPath = [System.IO.Path]::GetFullPath($SourceFile)
$TargetFullPath = [System.IO.Path]::GetFullPath($TargetFile)

if ($SourceFullPath -ne $TargetFullPath) {

    if (Test-Path $TargetFile) {

        Write-Host ""
        Write-Host "An article with the same filename already exists:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host $FileName
        Write-Host ""

        $ConfirmUpdate = Read-Host "Type UPDATE to overwrite the existing Hugo copy"

        if ($ConfirmUpdate -ne "UPDATE") {
            Write-Host ""
            Write-Host "Publishing cancelled."
            exit 0
        }
    }

    Copy-Item `
        -LiteralPath $SourceFile `
        -Destination $TargetFile `
        -Force
}
else {
    Write-Host ""
    Write-Host "Article is already inside content/posts."
}

Write-Host ""
Write-Host "Hugo article:"
Write-Host $TargetFile

# ==============================
# 7. Hugo build test
# ==============================

Write-Host ""
Write-Host "[5/7] Running Hugo build test..." -ForegroundColor Cyan

hugo

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Hugo build failed." -ForegroundColor Red
    Write-Host "Nothing has been pushed to GitHub."
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "Hugo build passed." -ForegroundColor Green

# ==============================
# 8. Git add and commit
# ==============================

Write-Host ""
Write-Host "[6/7] Creating Git commit..." -ForegroundColor Cyan

$RelativeFile = "content/posts/$FileName"

git add -- $RelativeFile

git diff --cached --quiet

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "No changes detected. Nothing to publish." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 0
}

$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName)

$CommitMessage = "Publish article: $BaseName"

git commit -m $CommitMessage

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: git commit failed." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# ==============================
# 9. Push
# ==============================

Write-Host ""
Write-Host "[7/7] Pushing to GitHub..." -ForegroundColor Cyan

git push origin $MainBranch

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: git push failed." -ForegroundColor Red
    Write-Host ""
    Write-Host "The commit already exists locally."
    Write-Host "You can retry later with:"
    Write-Host ""
    Write-Host "git push origin main"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

# ==============================
# Success
# ==============================

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
Write-Host ""

Read-Host "Press Enter to exit"