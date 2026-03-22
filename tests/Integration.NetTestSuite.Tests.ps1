Describe 'NetTestSuite integration tests' {
  It 'DryRun exits without error' {
    $output = pwsh -NoProfile -NonInteractive -File "$PSScriptRoot/../NetTestSuite.ps1" -DryRun -Quiet 2>&1
    $LASTEXITCODE | Should -Be 0
  }

  It 'DryRun with IPv4 only' {
    $output = pwsh -NoProfile -NonInteractive -File "$PSScriptRoot/../NetTestSuite.ps1" -DryRun -Quiet -Protocols IPv4 2>&1
    $LASTEXITCODE | Should -Be 0
  }

  It 'DryRun with specific round' {
    $output = pwsh -NoProfile -NonInteractive -File "$PSScriptRoot/../NetTestSuite.ps1" -DryRun -Quiet -Rounds Standard 2>&1
    $LASTEXITCODE | Should -Be 0
  }

  It 'DryRun with custom host' {
    $output = pwsh -NoProfile -NonInteractive -File "$PSScriptRoot/../NetTestSuite.ps1" -DryRun -Quiet -HostsIPv4 localhost 2>&1
    $LASTEXITCODE | Should -Be 0
  }

  It 'DryRun output includes planned run count' {
    $output = pwsh -NoProfile -NonInteractive -File "$PSScriptRoot/../NetTestSuite.ps1" -DryRun 2>&1
    ($output | Out-String) | Should -Match 'Planned runs: \d+'
  }
}

Describe 'NetTestSuite new feature tests' {
  It '-Version prints version' {
    $output = pwsh -NoProfile -NonInteractive -File "$PSScriptRoot/../NetTestSuite.ps1" -Version 2>&1
    ($output | Out-String) | Should -Match 'v1\.1\.0'
  }

  It '-ListRounds prints round names' {
    $output = pwsh -NoProfile -NonInteractive -File "$PSScriptRoot/../NetTestSuite.ps1" -ListRounds 2>&1
    ($output | Out-String) | Should -Match 'Standard'
    ($output | Out-String) | Should -Match 'MTU1400_DF'
    ($output | Out-String) | Should -Match 'TTL64_Timeout5s'
  }

  It '-ListProtocols prints IPv4 and IPv6' {
    $output = pwsh -NoProfile -NonInteractive -File "$PSScriptRoot/../NetTestSuite.ps1" -ListProtocols 2>&1
    ($output | Out-String) | Should -Match 'IPv4'
    ($output | Out-String) | Should -Match 'IPv6'
  }
}
