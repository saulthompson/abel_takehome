$outputDir = "C:\CAP_Output"
if (-not (Test-Path $outputDir)) { New-Item -Path $outputDir -ItemType Directory -Force }
while ($true) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $fileName = "incident_$timestamp.json"
    $filePath = "$outputDir\$fileName"
    $incident = @{
        "id" = Get-Random -Minimum 1000 -Maximum 9999
        "type" = "Traffic Stop"
        "location" = "Main St"
        "time" = (Get-Date).ToString("o")
    }
    $incident | ConvertTo-Json | Out-File $filePath
    Start-Sleep -Seconds 30  # Emit every 30 seconds
}