$ErrorActionPreference = "Stop"


# =====================================
# Luxseen Blog Manager v1.1
# =====================================


$BlogRepo = $PSScriptRoot

$PostsDir = Join-Path $BlogRepo "content\posts"

$BackupDir = Join-Path $BlogRepo "backup\deleted"

$Branch = "main"



function Init {


    Set-Location $BlogRepo


    if (!(Test-Path "hugo.toml")) {

        Write-Host "Missing hugo.toml"

        exit
    }


    if (!(Test-Path ".git")) {

        Write-Host "Git repository missing"

        exit
    }


    if (!(Test-Path $BackupDir)) {

        New-Item $BackupDir -ItemType Directory | Out-Null

    }

}




# =====================================
# Git Sync
# =====================================


function Sync-Git {


    Write-Host ""

    Write-Host "Sync GitHub..." -ForegroundColor Cyan


    git pull --ff-only origin $Branch


    if ($LASTEXITCODE -ne 0){

        Write-Host "Git sync failed"

        exit
    }


    Write-Host "Sync completed" -ForegroundColor Green

}




# =====================================
# Hugo Build
# =====================================


function Build-Hugo {


    Write-Host ""

    Write-Host "Running Hugo build..." -ForegroundColor Cyan


    hugo



    if($LASTEXITCODE -ne 0){

        Write-Host "Hugo failed" -ForegroundColor Red

        exit
    }



    Write-Host "Hugo OK" -ForegroundColor Green

}





# =====================================
# Git Push
# =====================================


function Commit-Push($Message){


    git add -A


    git diff --cached --quiet


    if($LASTEXITCODE -eq 0){

        Write-Host "No changes"

        return
    }



    git commit -m $Message



    git push origin $Branch



    Write-Host ""

    Write-Host "GitHub updated" -ForegroundColor Green

}

# =====================================
# Select Article
# =====================================


function Select-Article {


    $Files = Get-ChildItem $PostsDir -Filter *.md


    if($Files.Count -eq 0){

        Write-Host "No articles found"

        return $null
    }


    Write-Host ""


    for($i=0;$i -lt $Files.Count;$i++){

        Write-Host "$($i+1). $($Files[$i].Name)"

    }


    Write-Host ""


    $Num = Read-Host "Select number"


    return $Files[$Num-1]

}





# =====================================
# 1 Publish Article
# =====================================


function Publish-Article {


    Sync-Git



    Add-Type -AssemblyName System.Windows.Forms


    $Dialog = New-Object System.Windows.Forms.OpenFileDialog


    $Dialog.Filter = "Markdown (*.md)|*.md"


    $Result = $Dialog.ShowDialog()



    if($Result -ne "OK"){

        return

    }



    $Source = $Dialog.FileName


    $Name = Split-Path $Source -Leaf


    $Target = Join-Path $PostsDir $Name



    $Content = Get-Content $Source -Raw -Encoding UTF8



    if($Content -notmatch "title"){

        Write-Host "Missing title"

        return

    }


    if($Content -notmatch "date"){

        Write-Host "Missing date"

        return

    }



    if($Content -match "draft:\s*true"){

        Write-Host ""

        Write-Host "Article is draft. Stop."

        return

    }




    Copy-Item $Source $Target -Force



    Build-Hugo



    Commit-Push "Publish article $Name"



}





# =====================================
# 2 Delete Article
# =====================================


function Delete-Article {


    Sync-Git



    $File = Select-Article



    if($null -eq $File){

        return

    }




    Write-Host ""

    Write-Host "WARNING" -ForegroundColor Yellow

    Write-Host "Delete:"
    Write-Host $File.FullName



    $Confirm = Read-Host "Type DELETE"



    if($Confirm -ne "DELETE"){

        Write-Host "Cancelled"

        return

    }




    # backup first

    Copy-Item `
    $File.FullName `
    $BackupDir `
    -Force



    Remove-Item $File.FullName



    Build-Hugo



    Commit-Push "Delete article $($File.Name)"



}





# =====================================
# 3 Hide Article
# =====================================


function Hide-Article {


    Sync-Git



    $File = Select-Article



    if($null -eq $File){

        return

    }




    $Text = Get-Content `
    $File.FullName `
    -Raw



    $Text = $Text -replace `
    "draft:\s*false",`
    "draft: true"



    Set-Content `
    $File.FullName `
    $Text `
    -Encoding UTF8




    Commit-Push "Hide article $($File.Name)"



}





# =====================================
# 4 Restore Article
# =====================================


function Restore-Article {


    Sync-Git



    $File = Select-Article



    if($null -eq $File){

        return

    }



    $Text = Get-Content `
    $File.FullName `
    -Raw



    $Text = $Text -replace `
    "draft:\s*true",`
    "draft: false"



    Set-Content `
    $File.FullName `
    $Text `
    -Encoding UTF8




    Commit-Push "Restore article $($File.Name)"



}

# =====================================
# 5 List Posts
# =====================================


function List-Posts {


    Write-Host ""

    Write-Host "====== Luxseen Posts ======" -ForegroundColor Cyan


    $Files = Get-ChildItem $PostsDir -Filter *.md



    if($Files.Count -eq 0){

        Write-Host "No posts found"

        return

    }



    foreach($File in $Files){

        Write-Host "- $($File.Name)"

    }


}





# =====================================
# 6 Sync GitHub
# =====================================


function Sync-Only {


    Sync-Git


}





# =====================================
# 7 Local Preview
# =====================================


function Preview-Site {


    Write-Host ""

    Write-Host "Starting Hugo server..."

    hugo server


}





# =====================================
# 8 Update Website
# =====================================


function Update-Website {


    Sync-Git


    Build-Hugo


    Commit-Push "Update website"

}





# =====================================
# 9 Open Website
# =====================================


function Open-Website {


    Start-Process "https://luxseen.com/"

}





# =====================================
# 10 Git Status
# =====================================


function Show-Git-Status {


    Write-Host ""

    Write-Host "====== Git Status ======"


    git status


    Write-Host ""

    Write-Host "Last commit:"


    git log -1 --oneline



}





# =====================================
# 11 Search Article
# =====================================


function Search-Article {


    $Keyword = Read-Host "Search keyword"



    if([string]::IsNullOrWhiteSpace($Keyword)){

        return

    }




    Write-Host ""

    Write-Host "Search result:" -ForegroundColor Cyan




    Get-ChildItem $PostsDir -Filter *.md |
    Select-String $Keyword |
    Select Path,LineNumber,Line



}





# =====================================
# MENU
# =====================================


Init



while($true){


    Clear-Host



    Write-Host ""
    Write-Host "================================"
    Write-Host "   Luxseen Blog Manager v1.1"
    Write-Host "================================"
    Write-Host ""



    Write-Host "1. Publish Article"

    Write-Host "2. Delete Article"

    Write-Host "3. Hide Article"

    Write-Host "4. Restore Article"

    Write-Host "5. List Posts"

    Write-Host "6. Sync GitHub"

    Write-Host "7. Local Preview"

    Write-Host "8. Update Website"

    Write-Host "9. Open Website"

    Write-Host "10. Git Status"

    Write-Host "11. Search Article"

    Write-Host ""

    Write-Host "0. Exit"


    Write-Host ""


    $Choice = Read-Host "Select"



    switch($Choice){


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

            Show-Git-Status

        }


        "11" {

            Search-Article

        }


        "0" {

            exit

        }



        default {

            Write-Host "Invalid choice"

        }


    }



    Pause


}

