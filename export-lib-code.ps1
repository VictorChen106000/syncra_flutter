$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibPath = Join-Path $ProjectRoot "lib"

$OutputDir = "C:\Users\DARYN\OneDrive\Desktop\code-export"
$OutputHtml = Join-Path $OutputDir "lib-code-export.html"
$OutputPdf = Join-Path $OutputDir "lib-code-export.pdf"

if (!(Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

if (!(Test-Path $LibPath)) {
    Write-Host "ERROR: lib folder not found at $LibPath"
    pause
    exit 1
}

$files = Get-ChildItem -Path $LibPath -Recurse -File | Sort-Object FullName

$html = @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Syncra lib Code Export</title>
<style>
  body {
    font-family: Consolas, 'Courier New', monospace;
    font-size: 11px;
    line-height: 1.35;
    color: #111;
    background: #fff;
    padding: 24px;
  }
  h1 {
    font-family: Arial, sans-serif;
    font-size: 24px;
    margin-bottom: 4px;
  }
  .meta {
    font-family: Arial, sans-serif;
    font-size: 12px;
    color: #555;
    margin-bottom: 24px;
  }
  h2 {
    font-family: Arial, sans-serif;
    font-size: 15px;
    margin-top: 32px;
    padding-top: 14px;
    border-top: 1px solid #ccc;
    color: #000;
  }
  pre {
    white-space: pre-wrap;
    word-wrap: break-word;
    overflow-wrap: anywhere;
  }
</style>
</head>
<body>
<h1>Syncra lib Code Export</h1>
<div class="meta">
Project: $ProjectRoot<br>
Exported: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")<br>
Files: $($files.Count)
</div>
"@

foreach ($file in $files) {
    $relativePath = $file.FullName.Replace($ProjectRoot + "\", "")
    $code = [System.Net.WebUtility]::HtmlEncode((Get-Content $file.FullName -Raw -Encoding UTF8))
    $html += "<h2>$relativePath</h2>`n<pre>$code</pre>`n"
}

$html += "</body></html>"

Set-Content -Path $OutputHtml -Value $html -Encoding UTF8

$browser = "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe"
if (!(Test-Path $browser)) {
    $browser = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
}
if (!(Test-Path $browser)) {
    $browser = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
}
if (!(Test-Path $browser)) {
    $browser = "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe"
}

if (Test-Path $browser) {
    & $browser --headless --disable-gpu --print-to-pdf="$OutputPdf" "file:///$($OutputHtml.Replace('\','/'))"
    Write-Host "HTML exported to: $OutputHtml"
    Write-Host "PDF exported to:  $OutputPdf"
} else {
    Write-Host "HTML exported to: $OutputHtml"
    Write-Host "PDF was not created because Edge/Chrome was not found."
}

pause
