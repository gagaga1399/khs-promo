# Подписывает KHS.exe самоподписанным сертификатом (Authenticode, SHA-256).
#
# Зачем: Windows показывает «unknown publisher» и может блокировать запуск
# неподписанного exe. Самоподпись + добавление сертификата в личное хранилище
# доверия пользователя = целостность файла и отсутствие «неизвестного
# издателя» на этой машине. Для публичного распространения нужен платный
# сертификат (смартскрин), здесь — для личного использования.
#
# Использование: powershell -ExecutionPolicy Bypass -File tool\sign_exe.ps1
#   -Exe <путь к KHS.exe> [-Force]

param(
  [string]$Exe = "$PSScriptRoot\..\build\windows\x64\runner\Release\KHS.exe",
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$Subject = 'CN=KHS Local'
$CertName = 'KHS Local Code Signing'

$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
  Where-Object { $_.Subject -eq "CN=KHS Local" } |
  Select-Object -First 1

if ($null -eq $cert -or $Force) {
  if ($null -ne $cert) {
    Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -ErrorAction SilentlyContinue
  }
  $cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $Subject `
    -FriendlyName $CertName `
    -CertStoreLocation Cert:\CurrentUser\My `
    -NotAfter (Get-Date).AddYears(5) `
    -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3') # CodeSigning EKU
  Write-Output "Created cert: $($cert.Thumbprint)"
}

# Добавляем в личные доверенные издатели/стороны — SmartScreen не пугает,
# подпись проверяется локально.
foreach ($store in 'Root', 'TrustedPublisher', 'TrustedPeople') {
  $dst = "Cert:\CurrentUser\$store"
  if (-not (Get-ChildItem $dst | Where-Object { $_.Thumbprint -eq $cert.Thumbprint })) {
    Export-Certificate -Cert $cert -FilePath "$env:TEMP\khs-cert.cer" | Out-Null
    Import-Certificate -FilePath "$env:TEMP\khs-cert.cer" -CertStoreLocation $dst | Out-Null
    Write-Output "Imported into $store"
  }
}

$exe = (Resolve-Path $Exe).Path
if (-not (Test-Path $exe)) { throw "exe not found: $exe" }
$signtool = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter signtool.exe |
  Sort-Object FullName -Descending | Select-Object -First 1
if ($null -eq $signtool) { throw 'signtool.exe not found (install Windows SDK)' }

& $signtool.FullName sign /fd SHA256 /a /s my /n 'KHS Local' /t http://timestamp.digicert.com "$exe"
if ($LASTEXITCODE -ne 0) { throw "signtool failed: $LASTEXITCODE" }
& $signtool.FullName verify /pa "$exe"
Write-Output "Signed: $exe"