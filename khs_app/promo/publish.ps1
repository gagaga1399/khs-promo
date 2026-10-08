param(
  [string]$Version = '1.2.31',
  [string]$Repo = 'gagaga1399/khs-promo',
  [string]$UpdatesDir = 'C:\Users\user\Desktop\KHS-Windows\updates',
  [string]$TokenFile = 'C:\Users\user\AppData\Local\Temp\opencode\ghtoken.txt',
  [string]$OutFile = '',
  # Собрать и проверить страницу без обращения к GitHub.
  [switch]$DryRun,
  # Страница для GitHub Pages: картинки лежат в корне репозитория, поэтому
  # /files/... надо убрать. Для локального сервера путь остаётся /files/...
  [switch]$ForPages,
  # Обновить только сайт, файлы в релиз не выкладывать.
  [switch]$SkipRelease
)
$ErrorActionPreference = 'Stop'
$git = 'C:\Program Files\Git\cmd\git.exe'

$Apk = Join-Path $UpdatesDir "khs-$Version.apk"
$Zip = Join-Path $UpdatesDir "khs-$Version-windows.zip"
$QzApk = Join-Path $UpdatesDir 'qutzem-reader.apk'
$Cover = Join-Path $UpdatesDir 'cover.png'
if (-not $OutFile) { $OutFile = Join-Path $env:TEMP 'khs_promo_index.html' }

# ---- Сборка страницы ----
$src = Join-Path $PSScriptRoot 'index.html'
$html = Get-Content $src -Raw -Encoding UTF8

$base = "https://github.com/$Repo/releases/latest/download"
$androidUrl = "$base/khs-$Version.apk"
$windowsUrl = "$base/khs-$Version-windows.zip"
# APK читалки лежит отдельным релизом: его имя не зависит от версии хаба.
$qzUrl = 'https://github.com/gagaga1399/khs-reader-promo/releases/latest/download/qutzem-reader.apk'

# На GitHub Pages файлы лежат в корне репозитория, поэтому абсолютные пути
# не работают. На локальном сервере, наоборот, раздача идёт через /files/.
if ($ForPages) {
  $html = $html.Replace('src="/files/cover.png"', 'src="cover.png"')
  $html = $html.Replace("img.src = '/files/' + name;", 'img.src = name;')
}
$html = [regex]::Replace($html, '<span id="verline">[^<]*</span>', "<span id=`"verline`">$Version</span>")
$html = $html.Replace('href="/api/v1/update"', "href=`"https://github.com/$Repo`"")

$androidBtn = "<a class=`"btn btn-primary`" href=`"$androidUrl`" id=`"btnAndroid`" target=`"_blank`" rel=`"noopener`">"
$windowsBtn = "<a class=`"btn btn-ghost`" href=`"$windowsUrl`" id=`"btnWindows`" target=`"_blank`" rel=`"noopener`">"
$html = $html -replace '<a class="btn btn-primary" href="#" id="btnAndroid"[^>]*>', $androidBtn
$html = $html -replace '<a class="btn btn-ghost" href="#" id="btnWindows"[^>]*>', $windowsBtn

# Кнопки в блоке «Приложения центра» — те же файлы, отдельная разметка.
$html = $html -replace '(<a[^>]*id="btnAndroidCard"[^>]*?)href="#"', ('$1href="' + $androidUrl + '"')
$html = $html -replace '(<a[^>]*id="btnWindowsCard"[^>]*?)href="#"', ('$1href="' + $windowsUrl + '"')
$html = $html -replace '(<a[^>]*id="btnReaderApk"[^>]*?)href="#"', ('$1href="' + $qzUrl + '"')

$apkBytes = (Get-Item $Apk).Length
$zipBytes = (Get-Item $Zip).Length
$qzBytes = if (Test-Path $QzApk) { (Get-Item $QzApk).Length } else { 0 }
function Fmt-Bytes([long]$b) {
  $mb = $b / 1024 / 1024
  if ($mb -ge 1000) { return (('{0:0.0}' -f ($mb / 1024)) -replace ',', '.') + ' GB' }
  return (('{0:0.0}' -f $mb) -replace ',', '.') + ' MB'
}
$sizes = @"
    document.getElementById('verline').textContent = '$Version';
    document.getElementById('apkSize').textContent = '$(Fmt-Bytes $apkBytes)';
    document.getElementById('zipSize').textContent = '$(Fmt-Bytes $zipBytes)';
    document.getElementById('apkSize3').textContent = '$(Fmt-Bytes $apkBytes)';
    document.getElementById('zipSize3').textContent = '$(Fmt-Bytes $zipBytes)';
    document.getElementById('qzSize').textContent = '$(Fmt-Bytes $qzBytes)';
"@

# Размеры подставляются вместо блока, который тянет /api/v1/update:
# на Pages такого адреса нет, и без заглушки страница падала бы с ошибкой.
$startMarker = "fetch('/api/v1/update')"
$endMarker = 'function fmt(b)'
$i = $html.IndexOf($startMarker)
$j = $html.IndexOf($endMarker)
if ($i -ge 0 -and $j -gt $i) {
  $html = $html.Substring(0, $i) + $sizes + "`n" + $html.Substring($j)
} else {
  Write-Warning 'fetch block not found: sizes may not be substituted'
}

[IO.File]::WriteAllText($OutFile, $html, [Text.UTF8Encoding]::new($false))

# ---- Проверка результата ----
$problems = @()
if ($html -match 'href="#"') { $problems += 'осталась битая ссылка href="#"' }
# /files/ обязателен на локальном сервере и недопустим на Pages.
if ($ForPages -and $html -match '/files/') {
  $problems += 'остался абсолютный путь /files/ (для Pages он не работает)'
}
if ($html -match "fetch\('/api/v1/update'\)") { $problems += 'остался fetch к /api/v1/update' }
if ($html -notmatch 'IntersectionObserver') { $problems += 'нет анимации появления (IntersectionObserver)' }
foreach ($id in @('progress', 'verline', 'btnAndroid', 'btnWindows')) {
  if ($html -notmatch ('id="' + $id + '"')) { $problems += "нет элемента #$id" }
}
$opens = ([regex]::Matches($html, '<(section|div|a|header|footer|nav|main)\b')).Count
$closes = ([regex]::Matches($html, '</(section|div|a|header|footer|nav|main)>')).Count
if ($opens -ne $closes) { $problems += "не сходятся теги: открыто $opens, закрыто $closes" }

if ($problems.Count -gt 0) {
  Write-Host 'Проверка НЕ пройдена:' -ForegroundColor Red
  $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
  throw 'index.html не готов к публикации'
}
Write-Host "Проверка пройдена: $OutFile ($((Get-Item $OutFile).Length) байт)" -ForegroundColor Green

if ($DryRun) {
  Write-Host 'Dry run: GitHub не трогали.' -ForegroundColor Yellow
  return
}

# ---- Релиз с файлами ----
# Страница ссылается на releases/latest/download/..., поэтому APK и ZIP должны
# лежать в самом релизе. Создаём тег только если его ещё нет: старые релизы и
# файлы в корне репозитория не трогаем, ничего не удаляем и не форсим.
if (-not $SkipRelease) {
  $gh = (Get-Command 'gh' -ErrorAction SilentlyContinue).Source
  if (-not $gh) { $gh = 'C:\Program Files\GitHub CLI\gh.exe' }

  # gh пишет в stderr даже при успехе, а $ErrorActionPreference = 'Stop'
  # превращает это в аварийный выход. Поэтому на время проверки
  # возвращаемся к 'Continue' и смотрим только на код возврата.
  function Invoke-Gh([string[]]$GhArgs) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      & $gh @GhArgs 2>&1 | Out-Null
      return ($LASTEXITCODE -eq 0)
    } finally { $ErrorActionPreference = $prev }
  }

  # Работать можно тремя способами: авторизованный gh, токен в файле или
  # сохранённая учётка git. Последняя — рабочая: gh auth login у нас
  # прерывался, не дописав hosts.yml, но токен остался в менеджере учётных
  # данных Windows, и публикация шла именно оттуда.
  function Get-GitCredential() {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $out = "protocol=https`nhost=github.com`n`n" | & $git credential fill 2>$null
      $line = $out | Select-String -Pattern '^password=' | Select-Object -First 1
      if ($line) { return ($line.Line -replace '^password=', '').Trim() }
      return ''
    } finally { $ErrorActionPreference = $prev }
  }

  # Токен берём из любого доступного источника и дальше всегда идём через API:
  # у gh и у API один и тот же путь кода, а значит и одна проверка ошибок.
  $apiToken = ''
  if ((Test-Path $gh) -and (Invoke-Gh @('auth', 'token'))) {
    $apiToken = (& $gh auth token 2>$null | Select-Object -First 1)
  }
  if (-not $apiToken -and (Test-Path $TokenFile)) {
    $apiToken = (Get-Content $TokenFile -Raw).Trim()
  }
  if (-not $apiToken) { $apiToken = Get-GitCredential }
  if (-not $apiToken) {
    throw ("Нет доступа к GitHub. Положите токен в файл $TokenFile " +
      'или выполните gh auth login. Только сайт можно выложить ключом -SkipRelease.')
  }

  $tag = "v$Version"
  $headers = @{
    'User-Agent' = 'khs-publish'
    'Accept' = 'application/vnd.github+json'
    'Authorization' = "Bearer $apiToken"
  }

  function Get-ReleaseByTag($Tag) {
    try {
      return Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/tags/$Tag" -Headers $headers -TimeoutSec 60
    } catch { return $null }
  }
  function New-Release($Tag) {
    $body = "KHS $Version. Заметки стали файловым менеджером как в Obsidian: папки внутри папок, создание папок и заметок в них, хлебные крошки и подстраница задач. Подровнены отступы по всему приложению. Облачная синхронизация задач и заметок: вход по почте и через Google. Анимации: кольцо у кнопки быстрого добавления, свечение в календаре. Нижняя панель на настройках уезжает вниз, а её место занимает кнопка возврата. Починена проверка обновлений на ПК: сервер поднимался не всегда из-за адреса вида 192.168.0.107:4680."
    $payload = @{
      tag_name         = $Tag
      name             = "KHS $Version"
      body             = $body
      target_commitish = 'main'
    } | ConvertTo-Json
    return Invoke-RestMethod -Method Post -Uri "https://api.github.com/repos/$Repo/releases" `
      -Headers $headers -Body ([Text.Encoding]::UTF8.GetBytes($payload)) `
      -ContentType 'application/json; charset=utf-8' -TimeoutSec 120
  }
  function Add-ReleaseAsset($Release, $Path) {
    $name = Split-Path $Path -Leaf
    # upload_url уже абсолютный и с https:// — свой префикс ломает его.
    $base = ($Release.upload_url -replace '\{.*\}$', '')
    # -InFile отдаёт потоком, иначе 82 МБ APK целиком поедут в память.
    Invoke-RestMethod -Method Post `
      -Uri "$base`?name=$([uri]::EscapeDataString($name))" `
      -Headers $headers -InFile $Path -ContentType 'application/octet-stream' -TimeoutSec 1800 | Out-Null
    Write-Host "  загружен $name ($((Get-Item $Path).Length) байт)" -ForegroundColor Green
  }

  $release = Get-ReleaseByTag $tag
  if ($release) {
    Write-Host "Релиз $tag уже есть — недостающие файлы доложу, старые не трогаю." -ForegroundColor Yellow
  } else {
    foreach ($f in @($Apk, $Zip)) {
      if (-not (Test-Path $f)) { throw "нет файла для релиза: $f" }
    }
    $release = New-Release $tag
    Write-Host "Создан релиз $tag" -ForegroundColor Green
  }
  if (-not $release) { throw 'релиз не создан' }

  # Если релиз уже был, файлы могли не загрузиться — доливаем недостающие.
  $have = @($release.assets | ForEach-Object { $_.name })
  foreach ($f in @($Apk, $Zip)) {
    if (-not (Test-Path $f)) { throw "нет файла для релиза: $f" }
    $name = Split-Path $f -Leaf
    if ($have -contains $name) {
      Write-Host "  $name уже есть в релизе — пропускаю" -ForegroundColor DarkGray
      continue
    }
    Add-ReleaseAsset $release $f
  }
}

# ---- Публикация ----
# Репозиторий клонируется целиком: в нём лежат APK и ZIP (~98 МБ), и
# publish поверх пустого клона их бы удалил. Обновляем только index.html
# и добавляем недостающий cover.png, обычным push без --force.
$work = Join-Path $env:TEMP 'khs_promo_work'
if (Test-Path $work) { Remove-Item $work -Recurse -Force }

# Токен в адрес не подставляем: он остался бы в .git/config клона и мог бы
# попасть в текст ошибки. Запись идёт через менеджер учётных данных Windows,
# где для github.com уже сохранена учётка.
$remote = "https://github.com/$Repo.git"

& $git clone --depth 1 --quiet $remote $work
if ($LASTEXITCODE -ne 0) { throw 'clone failed' }

Copy-Item $OutFile (Join-Path $work 'index.html') -Force
if (Test-Path $Cover) {
  Copy-Item $Cover (Join-Path $work 'cover.png') -Force
} else {
  Write-Warning "cover.png not found at ${Cover}: logo останется битым"
}

# update.json на сайте — это то, что приложение читает при проверке
# обновления через интернет. Без него телефон видит прошлую версию и
# предлагать новую не будет, поэтому метаданные публикуем обязательно.
$UpdateJson = Join-Path $UpdatesDir 'update.json'
if (Test-Path $UpdateJson) {
  $meta = Get-Content $UpdateJson -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($meta.version -ne $Version) {
    throw "update.json устарел: в нём $($meta.version), а публикуем $Version"
  }
  Copy-Item $UpdateJson (Join-Path $work 'update.json') -Force
} else {
  throw "нет файла ${UpdateJson}: обновление через интернет работать не будет"
}

Push-Location $work
try {
  # git пишет предупреждения (LF -> CRLF и т.п.) в stderr. При
  # $ErrorActionPreference='Stop' PowerShell считает stderr нативной команды
  # фатальной ошибкой и роняет публикацию на ровном месте, поэтому на время
  # вызовов git режим меняем на Continue, а ошибки ловим по $LASTEXITCODE.
  $ErrorActionPreference = 'Continue'
  & $git config user.email 'gagaga1399@users.noreply.github.com' *>$null
  & $git config user.name 'gagaga1399' *>$null
  & $git add -A *>$null
  if ($LASTEXITCODE -ne 0) { throw 'git add failed' }
  & $git diff --cached --stat
  & $git commit -m "promo ${Version}: страница, логотип, метаданные обновления" -q *>$null
  if ($LASTEXITCODE -ne 0) { throw 'git commit failed' }
  & $git push origin HEAD:main *>$null
  if ($LASTEXITCODE -ne 0) {
    throw 'push failed: нужна авторизация (gh auth login или токен в ' + $TokenFile + ')'
  }
} finally {
  $ErrorActionPreference = 'Stop'
  Pop-Location
}

$user = $Repo.Split('/')[0]
$repoName = $Repo.Split('/')[1]
Write-Host "Published: https://$user.github.io/$repoName/" -ForegroundColor Green
Write-Host "Проверь сайт через 1-2 минуты: Pages кэширует сборку."
Write-Host "Ссылка на релиз: https://github.com/$Repo/releases/latest"