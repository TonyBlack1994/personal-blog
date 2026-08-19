$ErrorActionPreference = "Stop"

# ==============================
# Luxseen Blog Manager
# Cross-PC Version
# ==============================

$BlogRepo = $PSScriptRoot
$PostsDir = Join-Path $BlogRepo "content\posts"
$MainBranch = "main"


function Pause {
    Read-Host "Press Enter to continue"
}


function CheckEnvironment {

    if (-not (Test-Path $BlogRepo)) {
        Write-Host "ERROR: Blog repository not found." -ForegroundColor Red
        exit
    }


    if (-not (Test-Path (Join-Path $BlogRepo "hugo.toml"))) {
        Write-Host "ERROR: hugo.toml not found." -ForegroundColor Red
        exit
    }


    if (-not (Test-Path $PostsDir)) {
        Write-Host "ERROR: content/posts not found." -ForegroundColor Red
        exit
    }


    Set-Location $BlogRepo
}



function GetArticles {

    $files = Get-ChildItem `
        -Path $PostsDir `
        -Filter "*.md" `
        -File

    return $files
}



function ShowArticles {

    Write-Host ""
    Write-Host "========== Articles =========="

    $articles = GetArticles


    if ($articles.Count -eq 0) {

        Write-Host "No articles found."

        return
    }


    $i = 1

    foreach ($article in $articles) {

        Write-Host "$i. $($article.Name)"

        $i++
    }

}



function SelectArticle {


    $articles = GetArticles


    if ($articles.Count -eq 0) {

        Write-Host "No articles."

        return $null
    }


    Write-Host ""

    $i = 1

    foreach ($article in $articles) {

        Write-Host "$i. $($article.Name)"

        $i++
    }


    Write-Host ""

    $choice = Read-Host "Select article number"


    if ($choice -match "^\d+$") {

        $index = [int]$choice - 1


        if ($index -ge 0 -and $index -lt $articles.Count) {

            return $articles[$index]
        }
    }


    Write-Host "Invalid selection." -ForegroundColor Red

    return $null

}



function GitPush($message){


    Write-Host ""
    Write-Host "Git updating..." -ForegroundColor Cyan


    git add -A


    git commit -m $message


    git push origin $MainBranch


    Write-Host ""

    Write-Host "GitHub updated." -ForegroundColor Green

}



function DeleteArticle {


    $article = SelectArticle


    if ($null -eq $article) {

        Pause

        return
    }


    Write-Host ""

    Write-Host "You are deleting:" -ForegroundColor Yellow

    Write-Host $article.Name


    $confirm = Read-Host "Type DELETE to confirm"


    if ($confirm -ne "DELETE") {

        Write-Host "Cancelled."

        Pause

        return
    }


    Remove-Item $article.FullName


    GitPush "Delete article: $($article.BaseName)"


    Pause

}



function SetDraft($draftValue){


    $article = SelectArticle


    if ($null -eq $article) {

        Pause

        return
    }


    $path = $article.FullName


    $content = Get-Content `
        -LiteralPath $path `
        -Raw `
        -Encoding UTF8


    if ($draftValue -eq $true) {


        $content = $content -replace `
        "(?im)^draft\s*:\s*(true|false)", `
        "draft: true"


        Write-Host ""

        Write-Host "Article hidden." -ForegroundColor Yellow

    }


    else {


        $content = $content -replace `
        "(?im)^draft\s*:\s*(true|false)", `
        "draft: false"


        Write-Host ""

        Write-Host "Article restored." -ForegroundColor Green

    }



    Set-Content `
        -Path $path `
        -Value $content `
        -Encoding UTF8



    GitPush "Update draft status: $($article.BaseName)"


    Pause

}




function SyncGit {


    Write-Host ""

    Write-Host "Pulling latest GitHub..." -ForegroundColor Cyan


    git pull --ff-only origin $MainBranch


    Write-Host ""

    Write-Host "Sync completed." -ForegroundColor Green


    Pause

}




CheckEnvironment



while ($true) {


    Clear-Host


    Write-Host ""
    Write-Host "================================="
    Write-Host "       Luxseen Blog Manager"
    Write-Host "================================="
    Write-Host ""

    Write-Host "1. View articles"

    Write-Host "2. Delete article"

    Write-Host "3. Hide article (draft=true)"

    Write-Host "4. Restore article (draft=false)"

    Write-Host "5. Sync GitHub"

    Write-Host "6. Push all changes"

    Write-Host "0. Exit"

    Write-Host ""


    $choice = Read-Host "Choose"



    switch ($choice) {


        "1" {

            ShowArticles

            Pause

        }


        "2" {

            DeleteArticle

        }


        "3" {

            SetDraft $true

        }


        "4" {

            SetDraft $false

        }


        "5" {

            SyncGit

        }


        "6" {

            GitPush "Update Luxseen blog"

            Pause

        }


        "0" {

            exit

        }


        default {

            Write-Host "Invalid option."

            Pause

        }

    }

}