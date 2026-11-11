param(
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$AndroidNdk = $env:ANDROID_NDK_HOME,
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$BuildDirectory,
    [switch]$Debuggable
)
# Native Windows counterpart of build-android-apk.sh. No existing build output
# is deleted; every packaging run uses a fresh directory under the build.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not $BuildDirectory) { $BuildDirectory = Join-Path $repo 'rexglue/build-android-kr' }
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)
if (-not $AndroidSdk) { $AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
if (-not $AndroidNdk) {
    $AndroidNdk = (Get-ChildItem (Join-Path $AndroidSdk 'ndk') -Directory |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1).FullName
}
if (-not $JavaHome) { throw 'Set JAVA_HOME to JDK 17 or newer.' }
$buildTools = (Get-ChildItem (Join-Path $AndroidSdk 'build-tools') -Directory |
    Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1).FullName
$platform = (Get-ChildItem (Join-Path $AndroidSdk 'platforms') -Directory |
    Where-Object Name -Match '^android-\d+$' |
    Sort-Object { [int]($_.Name -replace '^android-', '') } -Descending | Select-Object -First 1).FullName
$androidJar = Join-Path $platform 'android.jar'
$java = Join-Path $JavaHome 'bin/java.exe'
$javac = Join-Path $JavaHome 'bin/javac.exe'
$app = Join-Path $repo 'rexglue/android'
$sdlJava = Join-Path $repo 'rexglue-sdk/thirdparty/sdl3/android-project/app/src/main/java'
$out = Join-Path $BuildDirectory ('apk-windows-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
foreach ($directory in @('gen','classes','dex','pack/lib/arm64-v8a')) {
    New-Item -ItemType Directory -Path (Join-Path $out $directory) -Force | Out-Null
}
function Invoke-AndroidTool {
    param([string]$Executable, [string[]]$ToolArguments)
    & $Executable @ToolArguments
    if ($LASTEXITCODE -ne 0) { throw "$Executable failed with exit code $LASTEXITCODE" }
}
$aapt = Join-Path $buildTools 'aapt2.exe'
Invoke-AndroidTool $aapt -ToolArguments @('compile','--dir',(Join-Path $app 'res'),'-o',(Join-Path $out 'res.zip'))
$linkArguments = @('link','-o',(Join-Path $out 'base.apk'),'-I',$androidJar,
    '--manifest',(Join-Path $app 'AndroidManifest.xml'),'--java',(Join-Path $out 'gen'),
    '--min-sdk-version','29','--target-sdk-version','34',(Join-Path $out 'res.zip'))
if ($Debuggable) { $linkArguments += '--debug-mode' }
Invoke-AndroidTool $aapt -ToolArguments $linkArguments
$sources = Join-Path $out 'sources.txt'
Get-ChildItem $sdlJava,(Join-Path $app 'java'),(Join-Path $out 'gen') -Recurse -Filter '*.java' |
    ForEach-Object { '"' + $_.FullName.Replace('\','/') + '"' } |
    Set-Content -LiteralPath $sources -Encoding utf8NoBOM
Invoke-AndroidTool $javac -ToolArguments @('-nowarn','-source','17','-target','17','-encoding','UTF-8',
    '-classpath',$androidJar,'-d',(Join-Path $out 'classes'),"@$sources")
$classList = Join-Path $out 'classes.txt'
Get-ChildItem (Join-Path $out 'classes') -Recurse -Filter '*.class' |
    ForEach-Object { $_.FullName.Replace('\','/') } |
    Set-Content -LiteralPath $classList -Encoding utf8NoBOM
Invoke-AndroidTool $java -ToolArguments @('-cp',(Join-Path $buildTools 'lib/d8.jar'),'com.android.tools.r8.D8',
    '--release','--min-api','29','--lib',$androidJar,'--output',(Join-Path $out 'dex'),"@$classList")
$libraryDir = Join-Path $out 'pack/lib/arm64-v8a'
$runtimeDir = Join-Path $repo 'rexglue-sdk/out/android-arm64'
$libraries = @(
    (Join-Path $BuildDirectory 'librexgpu-plume.so'),
    (Join-Path $runtimeDir 'librexruntime.so'),
    (Join-Path $BuildDirectory 'libxerenge_installer.so'),
    (Join-Path $AndroidNdk 'toolchains/llvm/prebuilt/windows-x86_64/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so')
)
$games = @(Get-ChildItem $BuildDirectory -Filter 'libmain_*.so')
if (-not $games.Count) { throw "No compiled game libraries in $BuildDirectory" }
$libraries += $games.FullName
foreach ($name in @('hook_impl','main_hook','file_redirect_hook','gsl_alloc_hook')) {
    $library = Get-ChildItem (Join-Path $BuildDirectory 'adrenotools') -Recurse -Filter "lib$name.so" | Select-Object -First 1
    if (-not $library) { throw "Missing adrenotools library: $name" }
    $libraries += $library.FullName
}
foreach ($library in $libraries) {
    if (-not (Test-Path -LiteralPath $library -PathType Leaf)) { throw "Missing library: $library" }
    Copy-Item -LiteralPath $library -Destination $libraryDir
}
$strip = Join-Path $AndroidNdk 'toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe'
foreach ($library in Get-ChildItem $libraryDir -Filter '*.so') {
    Invoke-AndroidTool $strip -ToolArguments @('--strip-unneeded',$library.FullName)
}
$unsigned = Join-Path $out 'unsigned.apk'
Copy-Item (Join-Path $out 'base.apk') $unsigned
$archive = [IO.Compression.ZipFile]::Open($unsigned, [IO.Compression.ZipArchiveMode]::Update)
try {
    foreach ($dex in Get-ChildItem (Join-Path $out 'dex') -Filter '*.dex') {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$dex.FullName,$dex.Name,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
    foreach ($library in Get-ChildItem $libraryDir -Filter '*.so') {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$library.FullName,
            "lib/arm64-v8a/$($library.Name)",[IO.Compression.CompressionLevel]::NoCompression) | Out-Null
    }
} finally { $archive.Dispose() }
$aligned = Join-Path $out 'aligned.apk'
Invoke-AndroidTool (Join-Path $buildTools 'zipalign.exe') -ToolArguments @('-f','-p','4',$unsigned,$aligned)
$keystore = Join-Path $BuildDirectory 'android-test.keystore'
if (-not (Test-Path -LiteralPath $keystore)) {
    Invoke-AndroidTool (Join-Path $JavaHome 'bin/keytool.exe') -ToolArguments @('-genkeypair','-keystore',$keystore,
        '-alias','androiddebugkey','-storepass','android','-keypass','android','-keyalg','RSA','-keysize','2048',
        '-validity','10000','-dname','CN=Android Debug,O=Android,C=US')
}
$apk = Join-Path $BuildDirectory 'Burnout-Revenge-Korea.apk'
Invoke-AndroidTool $java -ToolArguments @('-jar',(Join-Path $buildTools 'lib/apksigner.jar'),'sign',
    '--ks',$keystore,'--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android',
    '--out',$apk,$aligned)
Invoke-AndroidTool $java -ToolArguments @('-jar',(Join-Path $buildTools 'lib/apksigner.jar'),'verify',$apk)
Write-Output "APK: $apk"
