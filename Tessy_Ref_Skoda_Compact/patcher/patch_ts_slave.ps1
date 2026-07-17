$tessyRoot = "C:\Users\buimi1\Documents\03_repos\e-gsh_non-autosar_bsw_sk336-rcl-impl\test\tessy"

Write-Host ""
Write-Host "=== TESSY ts_slave.out Fixer ===" -ForegroundColor Cyan
Write-Host ""

$latest = Get-ChildItem "$tessyRoot\work" -Filter "ts_slave.out" -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if ($null -eq $latest)
{
    Write-Host "[ERROR] ts_slave.out not found in work folder" -ForegroundColor Red
    exit 1
}

$dst = "$tessyRoot\config\dummy\ts_slave.out"

Write-Host "[INFO] Source:" -ForegroundColor Yellow
Write-Host $latest.FullName

Copy-Item $latest.FullName $dst -Force

$file = Get-Item $dst

Write-Host ""
Write-Host "[OK] Updated successfully" -ForegroundColor Green
Write-Host ""

Write-Host "Target :" -ForegroundColor Cyan -NoNewline
Write-Host " $($file.FullName)"

Write-Host "Size   :" -ForegroundColor Cyan -NoNewline
Write-Host (" {0:N0} bytes" -f $file.Length)

Write-Host "Time   :" -ForegroundColor Cyan -NoNewline
Write-Host " $($file.LastWriteTime)"

Write-Host ""
Write-Host "Ready to run TESSY" -ForegroundColor Green