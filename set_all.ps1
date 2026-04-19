param (
    [Parameter(Mandatory=$true, Position=0)] [string]$HexColor,
    [Parameter(Mandatory=$true, Position=1)] [int]$BrightnessPercent
)

# process hex and brightness input
$cleanHex = $HexColor -replace '#', ''
$R = [convert]::ToInt32($cleanHex.Substring(0,2), 16)
$G = [convert]::ToInt32($cleanHex.Substring(2,2), 16)
$B = [convert]::ToInt32($cleanHex.Substring(4,2), 16)

# we only have the ability to set brightness as these predefined levels, so map the % input to nearest one
$mappedBrightness = switch ($BrightnessPercent) {
    {$_ -le 10} { 0 }   # 0%
    {$_ -le 35} { 64 }  # 25%
    {$_ -le 60} { 128 } # 50%
    {$_ -le 85} { 192 } # 75%
    Default     { 255 } # 100%
}

# initialise hardware client
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.Web.Extensions
$client = New-Object System.Net.Http.HttpClient
$jss = New-Object System.Web.Script.Serialization.JavaScriptSerializer

# find the controller
$syncResp = $client.PostAsync("http://localhost:11021/?action=SyncControllerList", (New-Object System.Net.Http.StringContent(""))).Result
$dict = $jss.Deserialize($syncResp.Content.ReadAsStringAsync().Result, [System.Collections.Generic.Dictionary[string,object]])
$devicePath = $dict.Keys | Select-Object -First 1

if ($null -eq $devicePath) { Write-Host "controller not found" -ForegroundColor Red; return }
$encDevPath = [Uri]::EscapeDataString([Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($devicePath)))

# discover mac addresses of wireless devices
$statusUrl = "http://localhost:11021/?action=Device&devicePath=$encDevPath&type=FanGroupStatus"
$statusResp = $client.PostAsync($statusUrl, (New-Object System.Net.Http.StringContent("{}", [System.Text.Encoding]::UTF8, "application/json"))).Result
$devices = $jss.Deserialize($statusResp.Content.ReadAsStringAsync().Result, [System.Collections.Generic.List[object]])

# debug section, you can remove this and hardcode your device mac addresses once found if you want
Write-Host "`ndiscovered devices:" -ForegroundColor Cyan
$macList = @()
$dirList = @()

foreach ($dev in $devices) {
    $currentMac = $dev.MacStr
    $devName = $dev.GroupName
    Write-Host "found: $devName [$currentMac]" -ForegroundColor Gray
    $macList += $currentMac
    $dirList += 0
}
Write-Host "total devices: $($macList.Count)" -ForegroundColor Cyan
Write-Host "`n"
#

if ($macList.Count -eq 0) {
    Write-Host "no devices found" -ForegroundColor Yellow
    return
}

# apply lighting
$bodyObj = @{
    PortOrderList = $macList
    DirectionList = $dirList
    MergeMode     = 3
    Scope         = 2
    Speed         = 5
    Direction     = 0
    Brightness    = $mappedBrightness
    Color         = @(
        @{
            ColorContext = $null
            A            = 255
            R            = $R
            G            = $G
            B            = $B
            ScA          = 1.0
        }
    )
}

$bodyJson = $bodyObj | ConvertTo-Json -Depth 10 -Compress

$applyUrl = "http://localhost:11021/?action=Device&devicePath=$encDevPath&type=FanMergeLightingSetting"
$resp = $client.PostAsync($applyUrl, (New-Object System.Net.Http.StringContent($bodyJson, [System.Text.Encoding]::UTF8, "application/json"))).Result

$resultText = $resp.Content.ReadAsStringAsync().Result
if ($resultText -match "true" -or $resp.IsSuccessStatusCode) {
    Write-Host "applied #$cleanHex to $($macList.Count) devices" -ForegroundColor Green
} else {
    Write-Host "error: $resultText" -ForegroundColor Red
}