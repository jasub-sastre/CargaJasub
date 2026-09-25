<#
.SYNOPSIS
  Muestrea /actuator/prometheus cada N segundos y guarda un CSV con las metricas
  del SERVIDOR mientras k6 genera carga. Detener con Ctrl+C.

.EXAMPLE
  # Desde la raiz del repo, en una segunda terminal, ANTES de lanzar k6:
  powershell -ExecutionPolicy Bypass -File perf/scripts/sample_actuator.ps1 -Out perf/results/actuator-load-prefix.csv

Columnas:
  ts                 hora local de la muestra
  srv_p50_ms/p95/p99 percentiles del servidor para POST /register status 200
                     (ventana deslizante de Micrometer, ~2 min; no es acumulado)
  req_count          peticiones acumuladas (POST /register, 200)
  req_avg_ms_cum     latencia media acumulada desde que arranco el servicio
  threads_live       jvm.threads.live
  gc_pause_count     numero acumulado de pausas de GC
  gc_pause_total_ms  tiempo total acumulado en pausas de GC
  heap_used_mb       memoria heap usada (suma de las regiones del heap)
  cpu_process        process.cpu.usage (0..1)
  tomcat_busy        hilos de Tomcat ocupados AHORA (saturacion real)
  tomcat_current     hilos de Tomcat creados (incluye ociosos)
  tomcat_max         maximo configurado (por defecto 200)
  scrape_ms          lo que tardo esta lectura de /actuator/prometheus
  hikari_active      conexiones del pool en uso ahora (solo version corregida)
  hikari_pending     hilos esperando una conexion del pool (solo version corregida)
#>
param(
  [string]$Url = "http://localhost:8080/actuator/prometheus",
  [int]$IntervalSec = 10,
  [string]$Out = "perf/results/actuator-samples.csv"
)

$culture = [System.Globalization.CultureInfo]::InvariantCulture

function Get-Val([string]$line) {
  # El valor es el ultimo token de la linea: "nombre{labels} 12.34"
  $tok = ($line -split '\s+')[-1]
  return [double]::Parse($tok, $culture)
}

function Sum-Lines($lines) {
  $s = 0.0
  foreach ($l in $lines) { $s += (Get-Val $l) }
  return $s
}

"ts,srv_p50_ms,srv_p95_ms,srv_p99_ms,req_count,req_avg_ms_cum,threads_live,gc_pause_count,gc_pause_total_ms,heap_used_mb,cpu_process,tomcat_busy,tomcat_current,tomcat_max,scrape_ms,hikari_active,hikari_pending" |
  Out-File -FilePath $Out -Encoding ascii

Write-Host "Muestreando $Url cada $IntervalSec s -> $Out  (Ctrl+C para detener)"

while ($true) {
  try {
    $sw    = [System.Diagnostics.Stopwatch]::StartNew()
    $text  = (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 60).Content
    $sw.Stop()
    $lines = $text -split "`n"

    # Solo el endpoint bajo prueba: POST /register con status 200
    $reg = $lines | Where-Object { $_ -match 'uri="/register"' -and $_ -match 'status="200"' }

    $q50 = $reg | Where-Object { $_ -like 'http_server_requests_seconds{*' -and $_ -match 'quantile="0.5"'  }
    $q95 = $reg | Where-Object { $_ -like 'http_server_requests_seconds{*' -and $_ -match 'quantile="0.95"' }
    $q99 = $reg | Where-Object { $_ -like 'http_server_requests_seconds{*' -and $_ -match 'quantile="0.99"' }
    $cnt = $reg | Where-Object { $_ -like 'http_server_requests_seconds_count*' }
    $sum = $reg | Where-Object { $_ -like 'http_server_requests_seconds_sum*' }

    $p50 = if ($q50) { [math]::Round((Get-Val ($q50 | Select-Object -First 1)) * 1000, 2) } else { "" }
    $p95 = if ($q95) { [math]::Round((Get-Val ($q95 | Select-Object -First 1)) * 1000, 2) } else { "" }
    $p99 = if ($q99) { [math]::Round((Get-Val ($q99 | Select-Object -First 1)) * 1000, 2) } else { "" }

    $n   = if ($cnt) { Sum-Lines $cnt } else { 0 }
    $t   = if ($sum) { Sum-Lines $sum } else { 0 }
    $avg = if ($n -gt 0) { [math]::Round(($t / $n) * 1000, 3) } else { "" }

    $thr = $lines | Where-Object { $_ -like 'jvm_threads_live_threads*' } | Select-Object -First 1
    $thr = if ($thr) { Get-Val $thr } else { "" }

    $gcN = Sum-Lines ($lines | Where-Object { $_ -like 'jvm_gc_pause_seconds_count*' })
    $gcT = [math]::Round((Sum-Lines ($lines | Where-Object { $_ -like 'jvm_gc_pause_seconds_sum*' })) * 1000, 1)

    $heapLines = $lines | Where-Object { $_ -like 'jvm_memory_used_bytes*' -and $_ -match 'area="heap"' }
    $heap = [math]::Round((Sum-Lines $heapLines) / 1MB, 1)

    $cpu = $lines | Where-Object { $_ -like 'process_cpu_usage*' } | Select-Object -First 1
    $cpu = if ($cpu) { [math]::Round((Get-Val $cpu), 3) } else { "" }

    # Hilos de Tomcat (requiere server.tomcat.mbeanregistry.enabled=true)
    $tb = $lines | Where-Object { $_ -like 'tomcat_threads_busy_threads*' }    | Select-Object -First 1
    $tc = $lines | Where-Object { $_ -like 'tomcat_threads_current_threads*' } | Select-Object -First 1
    $tm = $lines | Where-Object { $_ -like 'tomcat_threads_config_max_threads*' } | Select-Object -First 1
    $tb = if ($tb) { Get-Val $tb } else { "" }
    $tc = if ($tc) { Get-Val $tc } else { "" }
    $tm = if ($tm) { Get-Val $tm } else { "" }

    # Pool HikariCP (solo existe en la version CORREGIDA; en la original queda vacio)
    $ha = $lines | Where-Object { $_ -like 'hikaricp_connections_active*' }  | Select-Object -First 1
    $hp = $lines | Where-Object { $_ -like 'hikaricp_connections_pending*' } | Select-Object -First 1
    $ha = if ($ha) { Get-Val $ha } else { "" }
    $hp = if ($hp) { Get-Val $hp } else { "" }

    $row = "{0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14},{15},{16}" -f (Get-Date -Format "HH:mm:ss"), $p50, $p95, $p99, $n, $avg, $thr, $gcN, $gcT, $heap, $cpu, $tb, $tc, $tm, $sw.ElapsedMilliseconds, $ha, $hp
    $row | Out-File -FilePath $Out -Append -Encoding ascii
    Write-Host $row
  }
  catch {
    Write-Host ("[{0}] sin respuesta del servicio: {1}" -f (Get-Date -Format "HH:mm:ss"), $_.Exception.Message)
  }
  Start-Sleep -Seconds $IntervalSec
}