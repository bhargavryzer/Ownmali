$ErrorActionPreference = "Stop"

# Define the directory containing the contracts
$contractsDir = "lib\t-rex\contracts"

# Get all .sol files
$files = Get-ChildItem -Path $contractsDir -Filter "*.sol" -Recurse -File

# Pattern to match @onchain-id/solidity/ and replace with @onchain-id/
$pattern = '@onchain-id/solidity/'
$replacement = '@onchain-id/'

$count = 0

foreach ($file in $files) {
    $content = Get-Content -Path $file.FullName -Raw
    if ($content -match [regex]::Escape($pattern)) {
        $newContent = $content -replace [regex]::Escape($pattern), $replacement
        Set-Content -Path $file.FullName -Value $newContent -NoNewline
        Write-Host "Updated imports in $($file.FullName)"
        $count++
    }
}

Write-Host "Updated $count files."
