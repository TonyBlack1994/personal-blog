$ErrorActionPreference = "Stop"


# =====================================
# Luxseen Blog Manager v1.0
# =====================================


$BlogRepo = $PSScriptRoot
$PostsDir = Join-Path $BlogRepo "content\posts"
$Branch = "main"



function Init {


    Set-Location $BlogRepo


    if (!(Test-Path "hugo.toml")) {

        Write-Host "hugo.toml not found"

        exit
    }


    if (!(Test-Path ".git")) {

        Write-Host "Git repository not found"

        exit
    }


}



function Sync-Git {


    Write-Host ""

    Write-Host "Sync GitHub..."


    git pull --ff-only origin $Branch


    if ($LASTEXITCODE -ne 0){

        Write-Host "Git sync failed"

        exit
    }


}




function Build-Hugo {


    Write-Host ""

    Write-Host "Building Hugo..."


    hugo


    if ($LASTEXITCODE -ne 0){

        Write-Host "Hugo build failed"

        exit
    }


}




function Commit-Push($msg){


    git add -A


    git diff --cached --quiet


    if ($LASTEXITCODE -eq 0){

        Write-Host "No changes"

        return
    }



    git commit -m $msg


    git push origin $Branch



    Write-Host ""

    Write-Host "Completed"



}




# =====================================
# 发布文章
# =====================================


function Publish {


    Sync-Git



    Add-Type -AssemblyName System.Windows.Forms



    $dialog = New-Object System.Windows.Forms.OpenFileDialog


    $dialog.Filter="Markdown (*.md)|*.md"


    $result=$dialog.ShowDialog()



    if($result -ne "OK"){

        return

    }



    $source=$dialog.FileName


    $name=Split-Path $source -Leaf


    $target=Join-Path $PostsDir $name



    $text=Get-Content $source -Raw -Encoding UTF8



    if($text -notmatch "title"){

        Write-Host "Missing title"

        return

    }



    if($text -match "draft:\s*true"){

        Write-Host "Article is draft"

        return

    }



    Copy-Item $source $target -Force



    Build-Hugo



    Commit-Push "Publish $name"



}




# =====================================
# 删除文章
# =====================================


function Delete {


    Sync-Git



    $files=Get-ChildItem $PostsDir -Filter *.md



    for($i=0;$i -lt $files.Count;$i++){

        Write-Host "$($i+1). $($files[$i].Name)"

    }



    $n=Read-Host "Choose number"



    $file=$files[$n-1]



    if(!$file){

        return

    }



    Write-Host ""

    Write-Host "Delete:" $file.Name



    $c=Read-Host "Type DELETE"



    if($c -ne "DELETE"){

        return

    }



    Remove-Item $file.FullName



    Build-Hugo



    Commit-Push "Delete $($file.Name)"



}




# =====================================
# 隐藏文章
# =====================================


function Hide {


    Sync-Git



    $files=Get-ChildItem $PostsDir -Filter *.md



    for($i=0;$i -lt $files.Count;$i++){

        Write-Host "$($i+1). $($files[$i].Name)"

    }



    $n=Read-Host "Choose number"



    $file=$files[$n-1]



    if(!$file){

        return

    }



    $text=Get-Content $file.FullName -Raw



    $text=$text -replace "draft:\s*false","draft: true"



    Set-Content $file.FullName $text -Encoding UTF8



    Commit-Push "Hide $($file.Name)"



}




# =====================================
# 恢复文章
# =====================================


function Restore {


    Sync-Git



    $files=Get-ChildItem $PostsDir -Filter *.md



    for($i=0;$i -lt $files.Count;$i++){

        Write-Host "$($i+1). $($files[$i].Name)"

    }



    $n=Read-Host "Choose number"



    $file=$files[$n-1]



    if(!$file){

        return

    }



    $text=Get-Content $file.FullName -Raw



    $text=$text -replace "draft:\s*true","draft: false"



    Set-Content $file.FullName $text -Encoding UTF8



    Commit-Push "Restore $($file.Name)"



}





# =====================================
# 查看文章
# =====================================


function List {


    Write-Host ""

    Write-Host "====== Luxseen Posts ======" -ForegroundColor Cyan


    $files = Get-ChildItem $PostsDir -Filter *.md


    if ($files.Count -eq 0){

        Write-Host "No posts found."

        return
    }


    foreach($file in $files){

        Write-Host "- $($file.Name)"

    }


    Write-Host ""

}





# =====================================
# 本地预览
# =====================================


function Preview {


    hugo server



}





# =====================================
# 更新网站
# =====================================


function Update {


    Sync-Git


    Build-Hugo


    Commit-Push "Update website"



}





# =====================================
# MENU
# =====================================


Init



while($true){


    Clear-Host



    Write-Host ""
    Write-Host "=============================="
    Write-Host " Luxseen Blog Manager"
    Write-Host "=============================="
    Write-Host ""

    Write-Host "1. Publish"
    Write-Host "2. Delete"
    Write-Host "3. Hide"
    Write-Host "4. Restore"
    Write-Host "5. List Posts"
    Write-Host "6. Preview"
    Write-Host "7. Update Website"
    Write-Host "0. Exit"



    $choice=Read-Host "Select"



    switch($choice){


        "1" {Publish}


        "2" {Delete}


        "3" {Hide}


        "4" {Restore}


        "5" {List}


        "6" {Preview}


        "7" {Update}


        "0" {exit}



        default {

            Write-Host "Invalid choice"

        }


    }



    pause


}