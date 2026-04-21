# Automation-Commands-Plink.ps1
# GUI runner for Check Point clish commands via plink.
# - Synchronous execution on UI thread — no BackgroundWorker complexity
# - Auto-detects login shell: tries plain commands first (clish shell),
#   retries with 'clish -c' wrapping if CLINFR0329 returned (bash/expert shell)
# - PSScriptRoot fallback for irm | iex ($PWD used when no file on disk)
# - Per-host logs written to <script-or-cwd>\logs\<host>.log
# - Host key accepted via leading 'y' in stdin (PuTTY 0.72 compatible)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- CONFIG ---
$Hosts = @(
    '10.1.1.101',
    '10.1.1.1',
    '10.1.1.2',
    '10.1.1.3',
    '10.1.1.111',
    '10.1.1.130'
)

$Commands = @(
    'lock database override',
    'set user admin shell /bin/bash',
    'set inactivity-timeout 720',
    'save config'
)

$User            = 'admin'
$DefaultPassword = 'Chkp!234'
$PlinkPath       = 'C:\Program Files\PuTTY\plink.exe'

# $PSScriptRoot is empty under irm | iex — fall back to current directory
$ScriptRoot = if ($PSScriptRoot -and $PSScriptRoot -ne '') { $PSScriptRoot } else { $PWD.Path }
$LogFolder  = Join-Path $ScriptRoot 'logs'
New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
# --------------

#region ── UI BUILD ──────────────────────────────────────────────────────────

$form = New-Object System.Windows.Forms.Form
$form.Text            = 'Plink Automation Runner'
$form.Size            = New-Object System.Drawing.Size(840, 680)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox     = $false

# ── Hosts panel ──────────────────────────────────────────────────────────────
$lblHosts          = New-Object System.Windows.Forms.Label
$lblHosts.Text     = 'Select host(s):'
$lblHosts.Location = New-Object System.Drawing.Point(10, 10)
$lblHosts.AutoSize = $true
$form.Controls.Add($lblHosts)

$clbHosts              = New-Object System.Windows.Forms.CheckedListBox
$clbHosts.Location     = New-Object System.Drawing.Point(10, 32)
$clbHosts.Size         = New-Object System.Drawing.Size(360, 300)
$clbHosts.CheckOnClick = $true
foreach ($h in $Hosts) { [void]$clbHosts.Items.Add([string]$h) }
$form.Controls.Add($clbHosts)

$btnAllHosts          = New-Object System.Windows.Forms.Button
$btnAllHosts.Text     = 'Select All'
$btnAllHosts.Location = New-Object System.Drawing.Point(10, 338)
$btnAllHosts.Size     = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($btnAllHosts)

$btnNoneHosts          = New-Object System.Windows.Forms.Button
$btnNoneHosts.Text     = 'Select None'
$btnNoneHosts.Location = New-Object System.Drawing.Point(108, 338)
$btnNoneHosts.Size     = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($btnNoneHosts)

$btnAllHosts.Add_Click({
    for ($i = 0; $i -lt $clbHosts.Items.Count; $i++) { $clbHosts.SetItemChecked($i, $true) }
})
$btnNoneHosts.Add_Click({
    for ($i = 0; $i -lt $clbHosts.Items.Count; $i++) { $clbHosts.SetItemChecked($i, $false) }
})

# ── Commands panel ───────────────────────────────────────────────────────────
$lblCmds          = New-Object System.Windows.Forms.Label
$lblCmds.Text     = 'Select command(s):'
$lblCmds.Location = New-Object System.Drawing.Point(390, 10)
$lblCmds.AutoSize = $true
$form.Controls.Add($lblCmds)

$clbCmds              = New-Object System.Windows.Forms.CheckedListBox
$clbCmds.Location     = New-Object System.Drawing.Point(390, 32)
$clbCmds.Size         = New-Object System.Drawing.Size(420, 230)
$clbCmds.CheckOnClick = $true
foreach ($c in $Commands) { [void]$clbCmds.Items.Add([string]$c) }
$form.Controls.Add($clbCmds)

$btnAllCmds          = New-Object System.Windows.Forms.Button
$btnAllCmds.Text     = 'Select All'
$btnAllCmds.Location = New-Object System.Drawing.Point(390, 268)
$btnAllCmds.Size     = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($btnAllCmds)

$btnNoneCmds          = New-Object System.Windows.Forms.Button
$btnNoneCmds.Text     = 'Select None'
$btnNoneCmds.Location = New-Object System.Drawing.Point(488, 268)
$btnNoneCmds.Size     = New-Object System.Drawing.Size(90, 26)
$form.Controls.Add($btnNoneCmds)

$btnAllCmds.Add_Click({
    for ($i = 0; $i -lt $clbCmds.Items.Count; $i++) { $clbCmds.SetItemChecked($i, $true) }
})
$btnNoneCmds.Add_Click({
    for ($i = 0; $i -lt $clbCmds.Items.Count; $i++) { $clbCmds.SetItemChecked($i, $false) }
})

# ── Add-command row ───────────────────────────────────────────────────────────
$txtNewCmd          = New-Object System.Windows.Forms.TextBox
$txtNewCmd.Location = New-Object System.Drawing.Point(390, 302)
$txtNewCmd.Size     = New-Object System.Drawing.Size(310, 24)
$form.Controls.Add($txtNewCmd)

$btnAddCmd          = New-Object System.Windows.Forms.Button
$btnAddCmd.Text     = 'Add'
$btnAddCmd.Location = New-Object System.Drawing.Point(708, 300)
$btnAddCmd.Size     = New-Object System.Drawing.Size(60, 26)
$form.Controls.Add($btnAddCmd)

$lblAddNote          = New-Object System.Windows.Forms.Label
$lblAddNote.Text     = 'Type a command and click Add — it will be checked automatically.'
$lblAddNote.Location = New-Object System.Drawing.Point(390, 330)
$lblAddNote.Size     = New-Object System.Drawing.Size(420, 20)
$form.Controls.Add($lblAddNote)

$btnAddCmd.Add_Click({
    $v = $txtNewCmd.Text.Trim()
    if ($v -ne '') {
        [void]$clbCmds.Items.Add([string]$v)
        $clbCmds.SetItemChecked($clbCmds.Items.Count - 1, $true)
        $txtNewCmd.Clear()
        $txtNewCmd.Focus()
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            'Enter a non-empty command.', 'Add command',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
})

# ── Password row ──────────────────────────────────────────────────────────────
$lblPw          = New-Object System.Windows.Forms.Label
$lblPw.Text     = 'Password (leave blank to use SSH keys):'
$lblPw.Location = New-Object System.Drawing.Point(10, 375)
$lblPw.AutoSize = $true
$form.Controls.Add($lblPw)

$txtPw                       = New-Object System.Windows.Forms.TextBox
$txtPw.Location              = New-Object System.Drawing.Point(10, 395)
$txtPw.Size                  = New-Object System.Drawing.Size(360, 24)
$txtPw.UseSystemPasswordChar = $true
$txtPw.Text                  = $DefaultPassword
$form.Controls.Add($txtPw)

# ── Run / Close buttons ───────────────────────────────────────────────────────
$btnRun          = New-Object System.Windows.Forms.Button
$btnRun.Text     = 'Run'
$btnRun.Location = New-Object System.Drawing.Point(390, 375)
$btnRun.Size     = New-Object System.Drawing.Size(100, 36)
$form.Controls.Add($btnRun)

$btnClose          = New-Object System.Windows.Forms.Button
$btnClose.Text     = 'Close'
$btnClose.Location = New-Object System.Drawing.Point(500, 375)
$btnClose.Size     = New-Object System.Drawing.Size(90, 36)
$form.Controls.Add($btnClose)
$btnClose.Add_Click({ $form.Close() })

# ── Output box ────────────────────────────────────────────────────────────────
$txtOutput             = New-Object System.Windows.Forms.TextBox
$txtOutput.Location    = New-Object System.Drawing.Point(10, 440)
$txtOutput.Size        = New-Object System.Drawing.Size(800, 200)
$txtOutput.Multiline   = $true
$txtOutput.ScrollBars  = 'Vertical'
$txtOutput.ReadOnly    = $true
$txtOutput.Font        = New-Object System.Drawing.Font('Consolas', 9)
$txtOutput.BackColor   = [System.Drawing.Color]::FromArgb(30, 30, 30)
$txtOutput.ForeColor   = [System.Drawing.Color]::FromArgb(204, 204, 204)
$form.Controls.Add($txtOutput)

#endregion

#region ── HELPERS ───────────────────────────────────────────────────────────

function Get-CheckedStrings([System.Windows.Forms.CheckedListBox]$clb) {
    $arr = @()
    foreach ($it in $clb.CheckedItems) { $arr += [string]$it }
    return $arr
}

# Append to output box and pump the UI so it updates during synchronous run
function Write-OutputBox([string]$text) {
    $txtOutput.AppendText($text)
    $txtOutput.SelectionStart = $txtOutput.Text.Length
    $txtOutput.ScrollToCaret()
    $form.Refresh()
    [System.Windows.Forms.Application]::DoEvents()
}

#endregion

#region ── RUN LOGIC ─────────────────────────────────────────────────────────

$btnRun.Add_Click({

    $selectedHosts = Get-CheckedStrings -clb $clbHosts
    $selectedCmds  = Get-CheckedStrings -clb $clbCmds

    if (($selectedHosts.Count -eq 0) -or ($selectedCmds.Count -eq 0)) {
        [System.Windows.Forms.MessageBox]::Show(
            'Please select at least one host and one command.', 'Missing selection',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    if (-not (Test-Path $PlinkPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "plink.exe not found at:`n$PlinkPath`n`nInstall PuTTY or update `$PlinkPath.",
            'Plink not found',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }

    $btnRun.Enabled  = $false
    $btnClose.Enabled = $false

    $password = $txtPw.Text

    # 'y' answers the PuTTY 0.72 host key prompt on first connection; ignored thereafter
    $clishPayload = "y`n" + ($selectedCmds -join "`n")

    $clishWrapped  = ($selectedCmds | ForEach-Object {
        "-c `"$($_ -replace '"','\"')`""
    }) -join ' '
    $expertPayload = "y`nclish $clishWrapped"

    Write-OutputBox "Starting run at $([DateTime]::Now)`r`n"
    Write-OutputBox "Hosts   : $($selectedHosts -join ', ')`r`n"
    Write-OutputBox "Commands:`r`n"
    foreach ($c in $selectedCmds) { Write-OutputBox "  $c`r`n" }
    Write-OutputBox "`r`n"

    foreach ($targetHost in $selectedHosts) {

        Write-OutputBox "-> $targetHost`r`n"
        $logfile = Join-Path $LogFolder "$targetHost.log"

        try {
            $plinkArgs = @('-batch')
            if ($password -ne '') {
                $plinkArgs += '-pw'
                $plinkArgs += $password
            }
            $plinkArgs += "$User@$targetHost"

            $displayArgs = ($plinkArgs -join ' ') -replace [regex]::Escape($password), '********'
            Write-OutputBox "  cmd   : $PlinkPath $displayArgs`r`n"
            Write-OutputBox "  stdin : $($selectedCmds -join ' | ')`r`n"

            # First attempt — plain commands via stdin (clish login shell)
            $procOutput = $clishPayload | & $PlinkPath @plinkArgs 2>&1
            $exitCode   = $LASTEXITCODE
            $outText    = ($procOutput | ForEach-Object { $_.ToString() }) -join "`r`n"

            # CLINFR0329 means login shell is bash — retry with explicit clish -c
            if ($outText -match 'CLINFR0329') {
                Write-OutputBox "  [login shell is bash — retrying with clish -c]`r`n"
                $procOutput = $expertPayload | & $PlinkPath @plinkArgs 2>&1
                $exitCode   = $LASTEXITCODE
                $outText    = ($procOutput | ForEach-Object { $_.ToString() }) -join "`r`n"
            }

            if ($outText -ne '') {
                $outText | Out-File -FilePath $logfile -Encoding UTF8
                Write-OutputBox "$outText`r`n"
            } else {
                Write-OutputBox "  [no output]`r`n"
                '' | Out-File -FilePath $logfile -Encoding UTF8
            }

            $status = if ($exitCode -eq 0) { 'OK' } else { "EXIT $exitCode" }
            Write-OutputBox "  status: $status  |  log: $logfile`r`n`r`n"

        } catch {
            Write-OutputBox "  ERROR: $_`r`n`r`n"
        }
    }

    Write-OutputBox "Finished at $([DateTime]::Now)`r`n"

    $btnRun.Enabled  = $true
    $btnClose.Enabled = $true

    [System.Windows.Forms.MessageBox]::Show(
        "Run complete.`nLogs in: $LogFolder",
        'Done',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
})

#endregion

[void]$form.ShowDialog()
