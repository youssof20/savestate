# Creates or updates GitHub Releases for v1.1.0, v1.1.1, v1.1.2 with notes from .github/release-notes/
# and uploads savestate-lite-<tag>.zip built from each tag.
#
# Prerequisites:
#   - Git for Windows (git in PATH)
#   - A GitHub fine-grained or classic PAT with Contents: Read and write (repo scope)
#
# Usage (PowerShell, from repo root):
#   $env:GITHUB_TOKEN = "ghp_...."   # or fine-grained token
#   .\tools\publish_github_releases.ps1
#
# Or one line:
#   $env:GITHUB_TOKEN="YOUR_TOKEN"; .\tools\publish_github_releases.ps1

$ErrorActionPreference = "Stop"
$Owner = "youssof20"
$Repo = "savestate"
$Tags = @("v1.1.0", "v1.1.1", "v1.1.2")

if (-not $env:GITHUB_TOKEN) {
    Write-Error "Set GITHUB_TOKEN to a PAT with repo scope (Contents: read/write)."
}

$Headers = @{
    "Accept"               = "application/vnd.github+json"
    "Authorization"        = "Bearer $($env:GITHUB_TOKEN)"
    "X-GitHub-Api-Version" = "2022-11-28"
}

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

Write-Host "Fetching tags from origin..."
git fetch origin --tags 2>$null

function Get-ReleaseByTag([string]$Tag) {
    $uri = "https://api.github.com/repos/$Owner/$Repo/releases/tags/$Tag"
    try {
        return Invoke-RestMethod -Uri $uri -Headers $Headers -Method Get
    }
    catch {
        $code = 0
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
        }
        if ($code -eq 404) { return $null }
        throw
    }
}

function New-Release([string]$Tag, [string]$Body, [string]$Title) {
    $uri = "https://api.github.com/repos/$Owner/$Repo/releases"
    $payload = @{
        tag_name         = $Tag
        name             = $Title
        body             = $Body
        draft            = $false
        generate_release_notes = $false
    } | ConvertTo-Json
    return Invoke-RestMethod -Uri $uri -Headers $Headers -Method Post -Body $payload -ContentType "application/json"
}

function Set-ReleaseBody([int]$ReleaseId, [string]$Body) {
    $uri = "https://api.github.com/repos/$Owner/$Repo/releases/$ReleaseId"
    $payload = @{ body = $Body } | ConvertTo-Json
    return Invoke-RestMethod -Uri $uri -Headers $Headers -Method Patch -Body $payload -ContentType "application/json"
}

function Remove-AssetIfExists($Release, [string]$Name) {
    foreach ($a in $Release.assets) {
        if ($a.name -eq $Name) {
            $del = "https://api.github.com/repos/$Owner/$Repo/releases/assets/$($a.id)"
            Invoke-RestMethod -Uri $del -Headers $Headers -Method Delete
            Write-Host "  Removed old asset: $Name"
        }
    }
}

function Upload-Zip([string]$UploadUrl, [string]$ZipPath) {
    # UploadUrl is like https://uploads.github.com/repos/o/r/releases/123/assets{?name,label}
    $url = $UploadUrl -replace '\{\?name,label\}', "?name=$(Split-Path $ZipPath -Leaf)"
    $uploadHeaders = @{
        "Accept"               = "application/vnd.github+json"
        "Authorization"        = "Bearer $($env:GITHUB_TOKEN)"
        "X-GitHub-Api-Version" = "2022-11-28"
        "Content-Type"         = "application/zip"
    }
    Invoke-RestMethod -Uri $url -Headers $uploadHeaders -Method Post -InFile $ZipPath
}

foreach ($tag in $Tags) {
    Write-Host "`n=== $tag ==="
    $notesPath = Join-Path $Root ".github\release-notes\$tag.md"
    if (-not (Test-Path $notesPath)) { Write-Error "Missing $notesPath" }
    $body = Get-Content -Path $notesPath -Raw -Encoding UTF8

    $release = Get-ReleaseByTag $tag
    if ($null -eq $release) {
        Write-Host "Creating release..."
        $release = New-Release -Tag $tag -Body $body -Title "SaveState Lite $tag"
    }
    else {
        Write-Host "Release exists; updating description..."
        $release = Set-ReleaseBody -ReleaseId $release.id -Body $body
    }

    $zipName = "savestate-lite-$tag.zip"
    $zipPath = Join-Path $env:TEMP $zipName
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    Write-Host "Building $zipName from git tag $tag..."
    git archive --format=zip --output=$zipPath $tag addons/savestate
    if (-not (Test-Path $zipPath)) { Write-Error "git archive failed" }

    Remove-AssetIfExists -Release $release -Name $zipName
    Write-Host "Uploading $zipName..."
    $release = Get-ReleaseByTag $tag
    Upload-Zip -UploadUrl $release.upload_url -ZipPath $zipPath
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Write-Host "Done $tag"
}

Write-Host "`nAll releases updated: https://github.com/$Owner/$Repo/releases"
