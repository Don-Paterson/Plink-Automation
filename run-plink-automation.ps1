# Automation-Commands-Plink.ps1
# Single-file GUI runner focused on plink.
# - Writes commands with LF only (no CR)
# - Allows adding commands via textbox
# - Uses plink via argument array and captures output
# - Writes per-host logs to .\logs\<host>.log

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# --- CONFIG: edit as needed ---
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

$User = 'admin'
$DefaultPassword = 'Chkp!234'   # remove or leave blank to prefer SSH keys
$PlinkPath = 'plink.exe'        # change to full path if not in PATH
$LogFolder = Join-Path (Get-Location) 'logs'
New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
# ------------------------------

# Build UI
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Plink Automation Runner'
$form.Size = New-Object System.Drawing.Size(820,640)
$form.StartPosition = 'CenterScreen'

# Hosts checklist
$lblHosts = New-Object System.Windows.Forms.Label
$lblHosts.Text = 'Select host(s):'
$lblHosts.Location = New-Object System.Drawing.Point(10,10)
$lblHosts.AutoSize = $true
$form.Controls.Add($lblHosts)

$clbHosts = New-Object System.Windows.Forms.CheckedListBox
$clbHosts.Location = New-Object System.Drawing.Point(10,32)
$clbHosts.Size = New-Object System.Drawing.Size(360,380)
$clbHosts.CheckOnClick = $true
foreach ($h in $Hosts) { [void]$clbHosts.Items.Add([string]$h) }
$form.Controls.Add($clbHosts)

# Commands checklist
$lblCmds = New-Object System.Windows.Forms.Label
$lblCmds.Text = 'Select command(s):'
$lblCmds.Location = New-Object System.Drawing.Point(390,10)
$lblCmds.AutoSize = $true
$form.Controls.Add($lblCmds)

$clbCmds = New-Object System.Windows.Forms.CheckedListBox
$clbCmds.Location = New-Object System.Drawing.Point(390,32)
$clbCmds.Size = New-Object System.Drawing.Size(400,260)
$clbCmds.CheckOnClick = $true
foreach ($c in $Commands) { [void]$clbCmds.Items.Add([string]$c) }
$form.Controls.Add($clbCmds)

# Add-command textbox + button
$txtNewCmd = New-Object System.Windows.Forms.TextBox
$txtNewCmd.Location = New-Object System.Drawing.Point(390,300)
$txtNewCmd.Size = New-Object System.Drawing.Size(300,24)
$form.Controls.Add($txtNewCmd)

$btnAddCmd = New-Object System.Windows.Forms.Button
$btnAddCmd.Text = 'Add command'
$btnAddCmd.Location = New-Object System.Drawing.Point(700,298)
$btnAddCmd.Size = New-Object System.Drawing.Size(90,26)
$form.Controls.Add($btnAddCmd)

$lblAddNote = New-Object System.Windows.Forms.Label
$lblAddNote.Text = 'Type a command and click Add. It appears in the list and can be checked.'
$lblAddNote.Location = New-Object System.Drawing.Point(390,330)
$lblAddNote.Size = New-Object System.Drawing.Size(400,24)
$form.Controls.Add($lblAddNote)

$btnAddCmd.Add_Click({
    $v = $txtNewCmd.Text.Trim()
    if ($v -ne '') {
        [void]$clbCmds.Items.Add([string]$v)
        # check newly added item
        $clbCmds.SetItemChecked($clbCmds.Items.Count - 1, $true)
        $txtNewCmd.Clear()
        $txtNewCmd.Focus()
    } else {
        [System.Windows.Forms.MessageBox]::Show('Enter a non-empty command.', 'Add command', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
})

# Password label + textbox (secure)
$lblPw = New-Object System.Windows.Forms.Label
$lblPw.Text = 'Password (leave blank to use SSH keys):'
$lblPw.Location = New-Object System.Drawing.Point(10,420)
$lblPw.AutoSize = $true
$form.Controls.Add($lblPw)

$txtPw = New-Object System.Windows.Forms.TextBox
$txtPw.Location = New-Object System.Drawing.Point(10,440)
$txtPw.Size = New-Object System.Drawing.Size(360,24)
$txtPw.UseSystemPasswordChar = $true
$txtPw.Text = $DefaultPassword
$form.Controls.Add($txtPw)

# Run and Cancel buttons
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Run (Plink)'
$btnRun.Location = New-Object System.Drawing.Point(390,380)
$btnRun.Size = New-Object System.Drawing.Size(120,36)
$form.Controls.Add($btnRun)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = 'Cancel'
$btnCancel.Location = New-Object System.Drawing.Point(520,380)
$btnCancel.Size = New-Object System.Drawing.Size(90,36)
$form.Controls.Add($btnCancel)
$btnCancel.Add_Click({ $form.Close() })

# Status/output textbox
$txtOutput = New-Object System.Windows.Forms.TextBox
$txtOutput.Location = New-Object System.Drawing.Point(10,480)
$txtOutput.Size = New-Object System.Drawing.Size(780,140)
$txtOutput.Multiline = $true
$txtOutput.ScrollBars = 'Vertical'
$txtOutput.ReadOnly = $true
$form.Controls.Add($txtOutput)

# Helper: convert CheckedListBox.CheckedItems to string array
function Get-CheckedItemsAsStrings {
    param([System.Windows.Forms.CheckedListBox]$clb)
    $arr = @()
    foreach ($it in $clb.CheckedItems) { $arr += [string]$it }
    return $arr
}

# Run logic - Plink only (sequential)
$btnRun.Add_Click({
    # collect selections
    $selectedHosts = Get-CheckedItemsAsStrings -clb $clbHosts
    $selectedCmds  = Get-CheckedItemsAsStrings -clb $clbCmds

    if (($selectedHosts.Count -eq 0) -or ($selectedCmds.Count -eq 0)) {
        [System.Windows.Forms.MessageBox]::Show('Please select at least one host and one command.', 'Missing selection', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    # check plink
    if (-not (Get-Command $PlinkPath -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show("plink.exe not found at '$PlinkPath' or not in PATH. Install PuTTY or update PlinkPath.", 'Plink not found', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }

    # disable UI while running
    $btnRun.Enabled = $false
    $btnCancel.Enabled = $false
    $txtPw.Enabled = $false
    $txtNewCmd.Enabled = $false
    $btnAddCmd.Enabled = $false

    $password = $txtPw.Text
    $lf = [char]10   # LF only

    $txtOutput.AppendText("Starting run at $([DateTime]::Now)`r`n")
    $txtOutput.AppendText("Hosts: $($selectedHosts -join ', ')`r`n")
    $txtOutput.AppendText("Commands:`r`n")
    foreach ($c in $selectedCmds) { $txtOutput.AppendText("  $c`r`n") }
    $txtOutput.AppendText("`r`n")

    foreach ($targetHost in $selectedHosts) {
        $txtOutput.AppendText("-> $targetHost ...`r`n")
        $logfile = Join-Path $LogFolder ("$targetHost.log")

        # compose LF-only content
        $content = ($selectedCmds -join $lf) + $lf

        # create temp file and write ASCII LF-only
        $tmpFile = [System.IO.Path]::GetTempFileName()
        try {
            [System.IO.File]::WriteAllText($tmpFile, $content, [System.Text.Encoding]::ASCII)

            # build plink args
            $plinkArgs = @()
            $plinkArgs += "$User@$targetHost"
            if ($password -ne '') { $plinkArgs += '-pw'; $plinkArgs += $password }
            $plinkArgs += '-batch'; $plinkArgs += '-m'; $plinkArgs += $tmpFile

            # invoke plink and capture all output (stdout+stderr)
            $txtOutput.AppendText("Executing: $PlinkPath $($plinkArgs -join ' ')`r`n")
            $procOutput = & $PlinkPath @plinkArgs 2>&1

            # write log and show on UI
            if ($procOutput) {
                $procOutput | Out-File -FilePath $logfile -Encoding UTF8
                $txtOutput.AppendText(($procOutput -join [Environment]::NewLine) + "`r`n")
            } else {
                $txtOutput.AppendText("[no output]`r`n")
                '' | Out-File -FilePath $logfile -Encoding UTF8
            }
            $txtOutput.AppendText("  done (log: $logfile)`r`n`r`n")
        } catch {
            $txtOutput.AppendText("  ERROR: $_`r`n")
        } finally {
            # ensure temp file removed
            if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue }
        }

        Start-Sleep -Milliseconds 200
    }

    $txtOutput.AppendText("Finished at $([DateTime]::Now)`r`n")
    # re-enable UI
    $btnRun.Enabled = $true
    $btnCancel.Enabled = $true
    $txtPw.Enabled = $true
    $txtNewCmd.Enabled = $true
    $btnAddCmd.Enabled = $true

    [System.Windows.Forms.MessageBox]::Show("Run complete. Logs (if any) are in:`n$LogFolder", "Done", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
})

# show UI
[void]$form.ShowDialog()
