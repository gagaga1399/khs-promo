param(
  [string]$Version = '1.2.14',
  [string]$Apk = 'C:\Users\user\Desktop\KHS-Windows\updates\khs-1.2.14.apk',
  [string]$Zip = 'C:\Users\user\Desktop\KHS-Windows\updates\khs-1.2.14-windows.zip',
  [string]$Repo = 'gagaga1399/khs-promo',
  [string]$TokenFile = 'C:\Users\user\AppData\Local\Temp\opencode\ghtoken.txt'
)
$ErrorActionPreference = 'Stop'
$pub = Join-Path $env:TEMP 'khs_public'
if (Test-Path $pub) { Remove-Item $pub -Recurse -Force }
New-Item -ItemType Directory -Path $pub | Out-Null

$src = Join-Path $PSScriptRoot 'index.html'
$html = Get-Content $src -Raw -Encoding UTF8

$base = "https://github.com/$Repo/releases/latest/download"
$androidUrl = "$base/khs-$Version.apk"
$windowsUrl = "$base/khs-$Version-windows.zip"

$html = $html.Replace('src="/files/cover.png"', 'src="cover.png"')
$html = $html.Replace('img.src = ''/files/'' + name;', 'img.src = name;')
$html = [regex]::Replace($html, '<span id="verline">[^<]*</span>', "<span id=`"verline`">$Version</span>")
$html = $html.Replace('href="/api/v1/update"', "href=`"https://github.com/$Repo`"")

$androidBtn = "<a class=`"btn btn-primary`" href=`"$androidUrl`" id=`"btnAndroid`" target=`"_blank`" rel=`"noopener`">"
$windowsBtn = "<a class=`"btn btn-ghost`" href=`"$windowsUrl`" id=`"btnWindows`" target=`"_blank`" rel=`"noopener`">"
$html = $html -replace '<a class="btn btn-primary" href="#" id="btnAndroid"[^>]*>', $androidBtn
$html = $html -replace '<a class="btn btn-ghost" href="#" id="btnWindows"[^>]*>', $windowsBtn

$apkBytes = (Get-Item $Apk).Length
$zipBytes = (Get-Item $Zip).Length
function Fmt-Bytes([long]$b) {
  $mb = $b / 1024 / 1024
  if ($mb -ge 1000) { return (('{0:0.0}' -f ($mb / 1024)) -replace ',', '.') + ' GB' }
  return (('{0:0.0}' -f $mb) -replace ',', '.') + ' MB'
}
$sizes = @"
    document.getElementById('verline').textContent = '$Version';
    document.getElementById('apkSize').textContent = '$(Fmt-Bytes $apkBytes)';
    document.getElementById('zipSize').textContent = '$(Fmt-Bytes $zipBytes)';
"@

$startMarker = "fetch('/api/v1/update')"
$endMarker = 'function fmt(b)'
$i = $html.IndexOf($startMarker)
$j = $html.IndexOf($endMarker)
if ($i -ge 0 -and $j -gt $i) {
  $head = $html.Substring(0, $i)
  $tail = $html.Substring($j)
  $html = $head + $sizes + "`n" + $tail
} else {
  Write-Warning 'fetch block not found'
}

Copy-Item 'C:\Users\user\Desktop\KHS-Windows\updates\cover.png' $pub -ErrorAction SilentlyContinue
[IO.File]::WriteAllText((Join-Path $pub 'index.html'), $html, [Text.UTF8Encoding]::new($false))

# ---- Публикация: git push + GitHub release ----
$git = 'C:\Program Files\Git\cmd\git.exe'
$gh = 'C:\Program Files\GitHub CLI\gh.exe'
$token = (Get-Content $TokenFile -Raw).Trim()
if (-not $token) { throw 'No GitHub token' }

Push-Location $pub
try {
  & $git init -q
  & $git config user.email 'gagaga1399@users.noreply.github.com'
  & $git config user.name 'gagaga1399'
  & $git add -A
  & $git commit -m "promo $Version" -q
  & $git branch -M main
  & $git push -f "https://gagaga1399:$token@github.com/$Repo.git" main
} finally {
  Pop-Location
}

$env:GH_TOKEN = $token
$tag = "v$Version"
$oldPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $gh release view $tag --repo $Repo --json tagName -q .tagName 2>$null | Out-Null
$exists = $LASTEXITCODE -eq 0
$ErrorActionPreference = $oldPreference
if ($exists) {
  & $gh release delete $tag --repo $Repo --yes | Out-Null
}
& $gh release create $tag $Apk $Zip --repo $Repo --title "KHS $Version" --notes "KHS $Version build" | Out-Null
$user = $Repo.Split('/')[0]
$repoName = $Repo.Split('/')[1]
Write-Host "Published: https://$user.github.io/$repoName/"
Write-Host "Release: https://github.com/$Repo/releases/tag/$tag"
