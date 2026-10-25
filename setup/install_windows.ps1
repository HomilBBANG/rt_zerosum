# RT Zerosum 설치 (Windows): %USERPROFILE%\game 에 프로젝트를 받고 Godot 4.7 을 _engine\ 에 내려받은 뒤 실행.
# 사용 (PowerShell 에 붙여넣기):
#   irm https://raw.githubusercontent.com/HomilBBANG/rt_zerosum/claude/clever-keller-maq0u6/setup/install_windows.ps1 | iex
# 옵션(환경변수): $env:GAME_DIR=설치폴더  $env:GAME_BRANCH=브랜치  $env:NO_RUN="1"(설치만)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest 속도
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo    = "https://github.com/HomilBBANG/rt_zerosum.git"
$Branch  = if ($env:GAME_BRANCH) { $env:GAME_BRANCH } else { "claude/clever-keller-maq0u6" }
$Dir     = if ($env:GAME_DIR) { $env:GAME_DIR } else { Join-Path $env:USERPROFILE "game" }
$GodotVer = "4.7-stable"
$Base    = "https://github.com/godotengine/godot-builds/releases/download/$GodotVer"

Write-Host "== RT Zerosum 설치: $Dir (브랜치 $Branch)"
$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
if (Test-Path (Join-Path $Dir ".git")) {
    Write-Host "-- 이미 있음: 최신으로 업데이트"
    git -C $Dir fetch origin $Branch
    git -C $Dir checkout -q $Branch
    git -C $Dir pull --ff-only origin $Branch
} elseif ($hasGit) {
    if ((Test-Path $Dir) -and (Get-ChildItem $Dir -Force | Select-Object -First 1)) {
        throw "$Dir 에 다른 파일이 있습니다. 비우거나 `$env:GAME_DIR 로 다른 폴더를 지정하세요."
    }
    git clone -b $Branch $Repo $Dir
} else {
    Write-Host "-- git 이 없어 zip 으로 받습니다 (업데이트하려면 다시 실행)"
    $tmp = Join-Path $env:TEMP ("rtz_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp "src.zip"
    Invoke-WebRequest -Uri "https://codeload.github.com/HomilBBANG/rt_zerosum/zip/refs/heads/$Branch" -OutFile $zip
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $srcRoot = Get-ChildItem $tmp -Directory | Where-Object { $_.Name -like "rt_zerosum-*" } | Select-Object -First 1
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Copy-Item -Path (Join-Path $srcRoot.FullName "*") -Destination $Dir -Recurse -Force
    Remove-Item $tmp -Recurse -Force
}

$Engine = Join-Path $Dir "_engine"
New-Item -ItemType Directory -Force -Path $Engine | Out-Null
$Exe     = Join-Path $Engine "Godot_v${GodotVer}_win64.exe"
$Console = Join-Path $Engine "Godot_v${GodotVer}_win64_console.exe"
if (-not (Test-Path $Exe)) {
    Write-Host "-- Godot $GodotVer (Windows) 다운로드 (약 70MB)"
    $gz = Join-Path $Engine "godot.zip"
    Invoke-WebRequest -Uri "$Base/Godot_v${GodotVer}_win64.exe.zip" -OutFile $gz
    Expand-Archive -Path $gz -DestinationPath $Engine -Force
    Remove-Item $gz
}

Write-Host "-- 첫 리소스 임포트 (1~2분)"
$imp = if (Test-Path $Console) { $Console } else { $Exe }
& $imp --headless --path $Dir --import | Out-Null

# 바탕화면 바로가기
try {
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath("Desktop")) "RT Zerosum.lnk"))
    $lnk.TargetPath = Join-Path $Dir "play.bat"
    $lnk.WorkingDirectory = $Dir
    $lnk.IconLocation = $Exe
    $lnk.Save()
    Write-Host "-- 바탕화면에 'RT Zerosum' 바로가기를 만들었습니다."
} catch { Write-Host "-- 바로가기 생성 생략: $($_.Exception.Message)" }

Write-Host "== 설치 완료. 다음부터는 $Dir\play.bat (또는 바탕화면 바로가기) 로 실행합니다."
if ($env:NO_RUN -ne "1") { Start-Process -FilePath (Join-Path $Dir "play.bat") -WorkingDirectory $Dir }
