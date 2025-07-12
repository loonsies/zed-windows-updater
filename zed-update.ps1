# Settings
$owner = "sonercirit"
$repo = "zed-windows-stable"
$zedPath = "E:\Softs\zed.exe"
$zedShortcutPath = "E:\Softs\zed.lnk"
$repoReleasesUrl = "https://github.com/$owner/$repo/releases/latest"
$tempExe = "$env:TEMP\zed-latest.exe"

function Write-Status($msg) {
    Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] $msg"
}

# Function: Check if Zed is running
function Check-ZedRunning {
    $process = Get-Process -Name "zed" -ErrorAction SilentlyContinue
    if ($process) {
        Write-Status "Zed is currently running. Please close Zed before updating."
        Start-Sleep -Seconds 1
        exit 1
    }
}

# Function: Get latest tag from redirects or HTML
function Get-LatestTag {
    Write-Status "Checking latest Zed version online..."
    $response = Invoke-WebRequest -Uri $repoReleasesUrl -MaximumRedirection 0 -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 302) {
        $location = $response.Headers.Location
        if ($location -match "/tag/(.+)$") {
            return $Matches[1]
        }
    }
    # Fallback: get via HTML content
    $html = Invoke-WebRequest -Uri $repoReleasesUrl
    if ($html.Content -match "/tag/(zed-windows-v[\d\.]+)") {
        return $Matches[1]
    }
    throw "Could not determine latest tag."
}

# Function: Get Product Version from EXE
function Get-ExeVersion($exePath) {
    if (Test-Path $exePath) {
        try {
            return (Get-Item $exePath).VersionInfo.ProductVersion
        } catch {
            return $null
        }
    }
    return $null
}

# Function: Download with progress
function Download-WithProgress($url, $outPath) {
    $request = [System.Net.HttpWebRequest]::Create($url)
    $request.Method = "GET"
    $response = $request.GetResponse()
    $totalLength = $response.ContentLength
    $stream = $response.GetResponseStream()
    $fileStream = [System.IO.File]::OpenWrite($outPath)

    $buffer = New-Object byte[] 8192
    $totalRead = 0
    $lastPercent = -1
    do {
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) { break }
        $fileStream.Write($buffer, 0, $read)
        $totalRead += $read
        $percent = [math]::Floor(100 * $totalRead / $totalLength)
        if ($percent -ne $lastPercent) {
            $mbNow = "{0:N2}" -f ($totalRead/1MB)
            $mbTotal = "{0:N2}" -f ($totalLength/1MB)
            Write-Progress -Activity "Downloading Zed ($mbNow MB / $mbTotal MB)" -Status "$percent% Complete" -PercentComplete $percent
            $lastPercent = $percent
        }
    } while ($read -gt 0)
    $fileStream.Close()
    $stream.Close()
    Write-Progress -Activity "Downloading Zed" -Completed
}

try {
    # Check if Zed is running (before any update/launch)
    Check-ZedRunning

    Write-Status "Reading latest available version info..."
    $latestTag = Get-LatestTag
    if (-not $latestTag) { Write-Status "Could not get latest tag"; exit 1 }

    # Parse latest version
    if ($latestTag -match "v([\d\.]+)$") {
        $latestVersion = $Matches[1]
    } else {
        Write-Status "Could not parse latest version"
        exit 1
    }
    Write-Status "Latest available: $latestVersion"

    # Get current EXE version
    Write-Status "Checking installed Zed version..."
    $currentVersion = Get-ExeVersion $zedPath
    if ($currentVersion) {
        Write-Status "Installed version: $currentVersion"
    } else {
        Write-Status "No existing install detected."
    }

    # If update needed, download new EXE
    if ($currentVersion -ne $latestVersion) {
        Write-Status "Zed update required. Downloading $latestVersion..."
        $downloadUrl = "https://github.com/$owner/$repo/releases/download/$latestTag/zed-windows-v$latestVersion.exe"
        Download-WithProgress $downloadUrl $tempExe

        # Replace current exe (backup old just in case)
        if (Test-Path $zedPath) {
            $backupPath = "$zedPath.bak"
            Write-Status "Backing up old Zed.exe to $backupPath"
            Copy-Item $zedPath $backupPath -Force
        }
        Write-Status "Updating Zed.exe..."
        Copy-Item $tempExe -Destination $zedPath -Force
        Remove-Item $tempExe
        Write-Status "Zed updated to version $latestVersion."
    } else {
        Write-Status "Zed is up-to-date ($currentVersion)"
    }

    # Launch Zed
    Write-Status "Launching Zed editor"
    Start-Process -FilePath $zedShortcutPath

} catch {
    Write-Status "Error: $_"
    exit 1
}
