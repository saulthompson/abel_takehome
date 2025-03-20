$sourceDir = "C:\CAP_Output"
$sftpHost = "s-17abc5d808224a2ea.server.transfer.us-east-1.amazonaws.com"
$sftpUser = "sftpuser"
$sftpPath = "/cap-sftp-bucket-saul/$sftpUser"
$logFile = "C:\Scripts\CAPStreamLog.txt"

if (-not (Test-Path "C:\Scripts")) { New-Item -Path "C:\Scripts" -ItemType Directory }
function Write-Log {
    param ([string]$message)
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $message" | Out-File -FilePath $logFile -Append
}

# Avoid race conditions by ensuring files created by the CAP simulator finish writing before being passed to Process-File() 
function Wait-ForFile {
    param ($filePath)
    $maxAttempts = 10
    $delaySeconds = 1
    for ($i = 0; $i -lt $maxAttempts; $i++) {
        try {
            [System.IO.File]::Open($filePath, 'Open', 'Read', 'None').Close()
            return $true
        }
        catch {
            Write-Log "File $filePath still locked, waiting... (Attempt $i)"
            Start-Sleep -Seconds $delaySeconds
        }
    }
    throw "File $filePath remained locked after $maxAttempts attempts"
}

function Process-File {
    param ($filePath, $fileName)
    Write-Log "Processing file: $fileName"
    try {
        Wait-ForFile -filePath $filePath
        $keyPath = "C:\Scripts\temp_key"
        $keyContent = & "C:\Program Files\Amazon\AWSCLIV2\aws" secretsmanager get-secret-value --secret-id "cap-sftp-private-key" --query SecretString --output text
        $keyContent | Out-File $keyPath -Encoding ASCII
        $sftpCmd = "C:\OpenSSH\sftp.exe"
        $batchFile = "C:\Scripts\sftp_batch.txt"
        "put `"$filePath`" `"$sftpPath/$fileName`"" | Out-File $batchFile -Encoding ASCII
        $sftpArgs = "-i $keyPath -b $batchFile $sftpUser@$sftpHost"
        $process = Start-Process -FilePath $sftpCmd -ArgumentList $sftpArgs -NoNewWindow -Wait -PassThru -RedirectStandardError "C:\Scripts\sftp_error.txt"
        if ($process.ExitCode -ne 0) {
            $errorContent = Get-Content "C:\Scripts\sftp_error.txt" -ErrorAction SilentlyContinue
            throw "SFTP failed with exit code $($process.ExitCode): $errorContent"
        }
        Write-Log "Uploaded $fileName to $sftpHost$sftpPath"
        Move-Item -Path $filePath -Destination "C:\CAP_Output\Processed\$fileName" -Force
    }
    catch {
        Write-Log "Error uploading $fileName : $_"
    }
    finally {
        if (Test-Path $keyPath) { Remove-Item $keyPath }
        if (Test-Path "C:\Scripts\sftp_error.txt") { Remove-Item "C:\Scripts\sftp_error.txt" }
        if (Test-Path $batchFile) { Remove-Item $batchFile }
    }
}

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $sourceDir
$watcher.Filter = "*.*"
$watcher.EnableRaisingEvents = $true

Write-Log "Starting CAP file streaming service..."

while ($true) {
    $event = Get-EventSubscriber -SourceIdentifier "FileCreated" -ErrorAction SilentlyContinue
    if (-not $event) {
        Write-Log "Registering file creation event..."
        # Re-register event watcher to mitigate against winserv2016's tendency to drop event watchers
        Register-ObjectEvent $watcher "Created" -SourceIdentifier "FileCreated" -Action {
            $filePath = $Event.SourceEventArgs.FullPath
            $fileName = $Event.SourceEventArgs.Name
            . $PSScriptRoot\CAPFileStreamer.ps1
            Process-File -filePath $filePath -fileName $fileName
        }
    }

    # "manual" retry mechanism that scans for any files that were not picked up by the event
    $files = Get-ChildItem $sourceDir -File
    foreach ($file in $files) {
        Write-Log "Manual detection of file: $($file.Name)"
        Process-File -filePath $file.FullName -fileName $file.Name
    }

    Start-Sleep -Seconds 10
}