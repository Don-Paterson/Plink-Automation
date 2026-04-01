# Automation-Commands-Plink.ps1
# GUI runner using plink stdin piping for Check Point clish.
# - Commands piped via stdin (newline-separated) — no 'clish' prefix needed
# - Per-host logs written to .\logs\<host>.log (relative to script location)
# - Runs on a BackgroundWorker so the UI stays responsive
# - Host key auto-accepted via -auto-store-sshkey (PuTTY >= 0.77)

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

# Log folder next to the script, not CWD (avoids System32 when run via shortcut)
$LogFolder = Join-Path $PSScriptRoot 'logs'
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

$txtPw                      = New-Object System.Windows.Forms.TextBox
$txtPw.Location             = New-Object System.Drawing.Point(10, 395)
$txtPw.Size                 = New-Object System.Drawing.Size(360, 24)
$txtPw.UseSystemPasswordChar = $true
$txtPw.Text                 = $DefaultPassword
$form.Controls.Add($txtPw)

# ── Run / Cancel buttons ──────────────────────────────────────────────────────
$btnRun          = New-Object System.Windows.Forms.Button
$btnRun.Text     = 'Run'
$btnRun.Location = New-Object System.Drawing.Point(390, 375)
$btnRun.Size     = New-Object System.Drawing.Size(100, 36)
$form.Controls.Add($btnRun)

$btnCancel          = New-Object System.Windows.Forms.Button
$btnCancel.Text     = 'Close'
$btnCancel.Location = New-Object System.Drawing.Point(500, 375)
$btnCancel.Size     = New-Object System.Drawing.Size(90, 36)
$form.Controls.Add($btnCancel)
$btnCancel.Add_Click({ $form.Close() })

# ── Output box ────────────────────────────────────────────────────────────────
$txtOutput          = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object System.Drawing.Point(10, 440)
$txtOutput.Size     = New-Object System.Drawing.Size(800, 200)
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

# Thread-safe append + auto-scroll
function Append([string]$text) {
    if ($txtOutput.InvokeRequired) {
        $txtOutput.Invoke([Action[string]] {
            param($t)
            $txtOutput.AppendText($t)
            $txtOutput.SelectionStart = $txtOutput.Text.Length
            $txtOutput.ScrollToCaret()
        }, $text)
    } else {
        $txtOutput.AppendText($text)
        $txtOutput.SelectionStart = $txtOutput.Text.Length
        $txtOutput.ScrollToCaret()
    }
}

function Set-UIEnabled([bool]$enabled) {
    foreach ($ctrl in @($btnRun, $btnCancel, $txtPw, $txtNewCmd, $btnAddCmd,
                         $clbHosts, $clbCmds, $btnAllHosts, $btnNoneHosts,
                         $btnAllCmds, $btnNoneCmds)) {
        if ($ctrl.InvokeRequired) {
            $ctrl.Invoke([Action[bool]] { param($e); $ctrl.Enabled = $e }, $enabled)
        } else {
            $ctrl.Enabled = $enabled
        }
    }
}

#endregion

#region ── RUN LOGIC (BackgroundWorker) ──────────────────────────────────────

$worker                     = New-Object System.ComponentModel.BackgroundWorker
$worker.WorkerReportsProgress = $true

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

    Set-UIEnabled $false

    # Pass data into the worker via a hashtable
    $worker.RunWorkerAsync([PSCustomObject]@{
        Hosts    = $selectedHosts
        Commands = $selectedCmds
        Password = $txtPw.Text
    })
})

$worker.Add_DoWork({
    param($sender, $e)
    $args      = $e.Argument
    $hosts     = $args.Hosts
    $cmds      = $args.Commands
    $password  = $args.Password

    Append "Starting run at $([DateTime]::Now)`r`n"
    Append "Hosts   : $($hosts -join ', ')`r`n"
    Append "Commands:`r`n"
    foreach ($c in $cmds) { Append "  $c`r`n" }
    Append "`r`n"

    # Commands joined by newlines — piped into plink stdin
    # Check Point login shell IS clish, so no 'clish' prefix needed
    $stdinPayload = $cmds -join "`n"

    foreach ($targetHost in $hosts) {
        Append "-> $targetHost`r`n"
        $logfile = Join-Path $LogFolder ("$targetHost.log")

        try {
            $plinkArgs = @('-batch', '-auto-store-sshkey')
            if ($password -ne '') {
                $plinkArgs += '-pw'
                $plinkArgs += $password
            }
            $plinkArgs += "$User@$targetHost"

            # Redact password in display line
            $displayArgs = $plinkArgs -replace [regex]::Escape($password), '********'
            Append "  cmd : $PlinkPath $($displayArgs -join ' ')`r`n"
            Append "  stdin> $($cmds -join ' | ')`r`n"

            # Pipe commands via stdin
            $procOutput = $stdinPayload | & $PlinkPath @plinkArgs 2>&1
            $exitCode   = $LASTEXITCODE

            if ($procOutput) {
                $outText = ($procOutput | ForEach-Object { $_.ToString() }) -join "`r`n"
                $outText | Out-File -FilePath $logfile -Encoding UTF8
                Append "$outText`r`n"
            } else {
                Append "  [no output]`r`n"
                '' | Out-File -FilePath $logfile -Encoding UTF8
            }

            $status = if ($exitCode -eq 0) { 'OK' } else { "EXIT $exitCode" }
            Append "  status: $status  |  log: $logfile`r`n`r`n"
        } catch {
            Append "  ERROR: $_`r`n`r`n"
        }

        Start-Sleep -Milliseconds 300
    }

    Append "Finished at $([DateTime]::Now)`r`n"
})

$worker.Add_RunWorkerCompleted({
    Set-UIEnabled $true
    [System.Windows.Forms.MessageBox]::Show(
        "Run complete.`nLogs in: $LogFolder",
        'Done',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
})

#endregion

[void]$form.ShowDialog()
