# Data Pipeline for Windows Server 2016 -> remote SFTP Server

# Overview

This project automates the transfer of incident files from a Windows Server 2016 Server Core VM to an AWS S3 bucket via an AWS Transfer Family SFTP server. The solution consists of two PowerShell scripts running on the VM:

CAPSimulator.ps1: Generates mock incident files (e.g., incident_20250319_094946.json) every 30 seconds in C:\CAP_Output.
CAPFileStreamer.ps1: Monitors C:\CAP_Output using a FileSystemWatcher and a manual Get-ChildItem loop, uploading files to the SFTP server (s-17abc5d808224a2ea.server.transfer.us-east-1.amazonaws.com) with OpenSSH’s sftp.exe, then moving them to C:\CAP_Output\Processed.

# Production Considerations

This project is a simulation for a real problem - how to create a robust data pipeline between a Windows Server 2016 instance and a commercial remote system that absolutely relies on this data being available and intact.

There are some important differences between how I approached implementation in this mock project, and real-world production considerations.

# SFTP

But first, one feature of this project that is in fact suitable for production is the use of AWS's Transfer Family SFTP server with openSSH. It ensures proper data encryption, integrity, organization, and a built-in retry system.

# Network Share - Possible Implementations for Production

Now, a couple of important production considerations. I installed my powershell script on the Windows Server 2016 instance using Oracle Virtualbox's Guest Additions driver, which mounts a folder on my host machine in the virtual machine.

In the real world, files might need to be shared remotely, over the network. One possible implementation would be to reuse the SFTP server for bi-directional file-sharing. For example, you could create a shared directory on the SFTP server, and write a script for the third-party VM to pull those files down.

Of course, there are many other possible implementations, each with their own set of tradeoffs. In particular, RDP would be simpler in terms of ensuring shared files are moved to the right location without needing to run scripts or manual commands on the third-party machine.

# SSH Key Storage and Security

Another important consideration for replicating this system for production - in my implementation, the SSH private key is stored as a plain-text file in C:\Scripts on the Windows Server 2016 instance. This is obviously insecure to a greater or lesser extent, depending on how much you trust the third-party system where it's stored. A more secure implementation would be to use AWS Secrets Manager. The file-streaming powershell script would be updated to make a call to Secrets Manager via the AWS CLI or SDK, and fetch the private key dynamically. In this setup, the exposure-window of the private key on the VM would be reduced dramatically, at the cost of some additional setup complexity. In fact, not only the SSH private key, but also other SFTP credentials and access data could be stored in AWS secrets, which also would make it easier for credentials to be rotated or otherwise updated remotely, in line with security best practices.

# Infrastructure Deployment

I chose to use AWS services to build the infrastructure for this project, specifically S3 Bucket for object storage, and Transfer Family for SFTP. I automated this deployment using Terraform for reusability and convenience. You can find the Terraform code in main.tf in this repo. I configured this script to create a local backend for state storage. In production, a remote backend with a dedicated S3 bucket could be implemented to facilite team collaboration.

# Code Walkthrough for CAPFileStreamer.ps1 

Initialization:
$watcher = New-Object System.IO.FileSystemWatcher: Creates a watcher instance.
$watcher.Path = $sourceDir: Sets the directory to monitor (C:\CAP_Output).
$watcher.Filter = "*.*": Watches all files (no specific extension filter).
$watcher.EnableRaisingEvents = $true: Activates the watcher to start listening.
Event Registration:
Get-EventSubscriber -SourceIdentifier "FileCreated": Checks if the Created event is already subscribed.
if (-not $event): If not, registers it with Register-ObjectEvent.
Register-ObjectEvent $watcher "Created" -SourceIdentifier "FileCreated" -Action { ... }:
Ties the Created event to an action block.
-SourceIdentifier "FileCreated": Names the event for tracking.
Action Block:
$filePath = $Event.SourceEventArgs.FullPath: Gets the full path (e.g., C:\CAP_Output\incident_20250319_094946.json).
$fileName = $Event.SourceEventArgs.Name: Gets the filename (e.g., incident_20250319_094946.json).
. $PSScriptRoot\CAPFileStreamer.ps1: Dot-sources the script to access Process-File.
Process-File: Uploads the file via SFTP and moves it to C:\CAP_Output\Processed.
Why the Check/Re-Register?
Earlier, we found the watcher stopped after one event (a PowerShell 5.1 quirk). Re-registering ensures it keeps working if the subscription drops.
Manual Fallback:
Get-ChildItem $sourceDir -File: Scans for files missed by the watcher.
Ensures no file is overlooked, especially if the watcher fails or lags.
How It Operates Under the Hood
Event Queue: When CAPSimulator.ps1 creates a file (e.g., Out-File "C:\CAP_Output\incident_..."), the OS notifies FileSystemWatcher, which queues a Created event.
Threading: The action block runs on a separate thread, so it doesn’t block the main loop. This is why Start-Sleep -Seconds 10 doesn’t delay event handling.
Buffering: The watcher has an internal buffer (default 8KB) to store events. If too many files are created too quickly (overflow), events can be dropped—hence your manual Get-ChildItem backup.