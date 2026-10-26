# S0.5, the Windows leg of p99.sh: the server on CPUs 0-3 and k6 on the others, both at High priority so
# the box's other (Normal) work can't preempt them; arms interleaved, the order rotating each round.
#   .\p99.ps1 -Bin s05.exe -Rounds 6 -Rps 2000 -Secs 15 -Out dir [-Arms base,pool,idle]
# One line per run, in p99.sh's format; cpu_server_other is the server's CPU use (cores x 100) and k6's.
param(
	[string]$Bin, [int]$Rounds = 6, [int]$Rps = 2000, [int]$Secs = 15, [string]$Out,
	[string[]]$Arms = @('base', 'pool', 'idle'), [int]$Port0 = 22000, [string]$K6 = 'k6.exe'
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
$js = Join-Path $PSScriptRoot 'p99.js'
$port = $Port0
$n = $Arms.Count
for ($r = 1; $r -le $Rounds; $r++) {
	for ($j = 0; $j -lt $n; $j++) {
		$arm = $Arms[($j + $r - 1) % $n]
		$env:THREADS = '2'; $env:ACCOUNTS_ARGON_THREADS = '2'; $env:INLINE = '0'; $env:ARGON_SCHED = ''
		$env:PORT = "$port"; $logins = 50
		switch ($arm) {
			'base'   { $logins = 0 }
			'inline' { $env:INLINE = '1' }
			'idle'   { $env:ARGON_SCHED = 'idle' }
			'pool1'  { $env:ACCOUNTS_ARGON_THREADS = '1' }
		}
		$srv = Start-Process -FilePath $Bin -PassThru -NoNewWindow -RedirectStandardOutput "$Out\server-$arm-$r.log"
		$srv.PriorityClass = 'High'
		$srv.ProcessorAffinity = [IntPtr]0xF
		do {
			Start-Sleep -Milliseconds 100
			$c = New-Object System.Net.Sockets.TcpClient
			$up = $c.ConnectAsync('127.0.0.1', $port).Wait(500) -and $c.Connected
			$c.Dispose()
		} until ($up)

		$cpu0 = $srv.TotalProcessorTime.TotalSeconds
		$t0 = Get-Date
		$win = Start-Job { (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples $using:Secs).CounterSamples | Measure-Object CookedValue -Average | ForEach-Object Average }
		$k6p = Start-Process -FilePath $K6 -PassThru -NoNewWindow -RedirectStandardOutput "$Out\k6-$arm-$r.out" -ArgumentList @(
			'run', '-q', '-e', "BASE=http://127.0.0.1:$port", '-e', "PING_RPS=$Rps", '-e', "LOGINS=$logins",
			'-e', 'WARM=5s', '-e', "DUR=${Secs}s", '-e', "OUT=$Out\k6-$arm-$r.json", $js)
		$k6p.PriorityClass = 'High'
		$k6p.ProcessorAffinity = [IntPtr]0xFFF0
		$k6p.WaitForExit()
		$el = ((Get-Date) - $t0).TotalSeconds
		$srv.Refresh()
		$cpuS = 100 * ($srv.TotalProcessorTime.TotalSeconds - $cpu0) / $el
		$cpuK = 100 * $k6p.TotalProcessorTime.TotalSeconds / $el
		$stats = (Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$port/stats").Content
		Stop-Process -Id $srv.Id
		$wincpu = Receive-Job $win -Wait -AutoRemoveJob
		$k6json = (Get-Content "$Out\k6-$arm-$r.json" -Raw).Trim()
		'{0} round={1} k6={2} server={3} cpu_server_other={4:F1} {5:F1} cpu_win={6:F1}' -f $arm, $r, $k6json, $stats, $cpuS, $cpuK, $wincpu
		$port++
	}
}
