function Get-StringHash($str) {
  $md5 = new-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
  $utf8 = new-object -TypeName System.Text.UTF8Encoding
  return [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($str)))
}

function Test-NewerFile($file1, $file2) {
  if (!(Test-Path $file1)) {
    return $FALSE
  }
  if (!(Test-Path $file2)) {
    return $TRUE
  }
  $mod1 = (Get-ChildItem $file1).LastWriteTimeUtc
  $mod2 = (Get-ChildItem $file2).LastWriteTimeUtc
  return $mod1 -gt $mod2
}

function Invoke-Clojure {
  $ErrorActionPreference = 'Stop'

  # Set dir containing the installed files
  $InstallDir = $PSScriptRoot
  $Version = '${project.version}'
  $ToolsCp = "$InstallDir\clojure-tools-$Version.jar"


  # Extract opts
  $PrintClassPath = $FALSE
  $Describe = $FALSE
  $Verbose = $FALSE
  $Trace = $FALSE
  $Force = $FALSE
  $Repro = $FALSE
  $Tree = $FALSE
  $Pom = $FALSE
  $ResolveTags = $FALSE
  $Prep = $FALSE
  $Help = $FALSE
  $JvmOpts = @()
  $ResolveAliases = @()
  $ClasspathAliases = @()
  $JvmAliases = @()
  $MainAliases = @()
  $ToolAliases = @()
  $AllAliases = @()
  $ExecAlias = @()

  $params = $args
  while ($params.Count -gt 0) {
    $arg, $params = $params
    if ($arg.StartsWith('-J')) {
      $JvmOpts += $arg.Substring(2)
    } elseif ($arg.StartsWith('-R')) {
      $aliases, $params = $params
      if ($aliases) {
        $ResolveAliases += ":$aliases"
      }
    } elseif ($arg.StartsWith('-C')) {
      $aliases, $params = $params
      if ($aliases) {
        $ClassPathAliases += ":$aliases"
      }
    } elseif ($arg.StartsWith('-O')) {
      $aliases, $params = $params
      if ($aliases) {
        $JvmAliases += ":$aliases"
      }
    } elseif ($arg.StartsWith('-M')) {
      $aliases, $params = $params
      if ($aliases) {
        $MainAliases += ":$aliases"
      }
    } elseif ($arg.StartsWith('-T')) {
      $aliases, $params = $params
      if ($aliases) {
        $ToolAliases += ":$aliases"
      }
    } elseif ($arg.StartsWith('-A')) {
      $aliases, $params = $params
      if ($aliases) {
        $AllAliases += ":$aliases"
      }
    } elseif ($arg -eq '-X:') {
      # Windows splits on the : in -X:foo as an option
      $kw, $params = $params
      $ExecAlias += "${arg}$kw"
      $ExecAlias += $params
      break
    } elseif ($arg.StartsWith('-X')) {
      $ExecAlias += $arg, $params
      break
    } elseif ($arg.StartsWith('-F')) {
      $ExecAlias += $arg, $params
      break
    } elseif ($arg -eq '-D') {
      $Prep = $TRUE
    } elseif ($arg -eq '-Sdeps') {
      $DepsData, $params = $params
    } elseif ($arg -eq '-Scp') {
      $ForceCP, $params = $params
    } elseif ($arg -eq '-Spath') {
      $PrintClassPath = $TRUE
    } elseif ($arg -eq '-Sverbose') {
      $Verbose = $TRUE
    } elseif ($arg -eq '-Sthreads') {
      $Threads, $params = $params
    } elseif ($arg -eq '-Strace') {
      $Trace = $TRUE
    } elseif ($arg -eq '-Sdescribe') {
      $Describe = $TRUE
    } elseif ($arg -eq '-Sforce') {
      $Force = $TRUE
    } elseif ($arg -eq '-Srepro') {
      $Repro = $TRUE
    } elseif ($arg -eq '-Stree') {
      $Tree = $TRUE
    } elseif ($arg -eq '-Spom') {
      $Pom = $TRUE
    } elseif ($arg -eq '-Sresolve-tags') {
      $ResolveTags = $TRUE
    } elseif ($arg.StartsWith('-S')) {
      Write-Error "Invalid option: $arg"
      return
    } elseif ($arg -in '-h', '--help', '-?') {
      if ($MainAliases -or $AllAliases) {
        $ClojureArgs += $arg, $params
        break
      } else {
        $Help = $TRUE
      }
    } elseif ($arg -eq '--') {
      $ClojureArgs += $params
      break
    } else {
      $ClojureArgs += $arg, $params
      break
    }
  }

  # Find java executable
  $JavaCmd = (Get-Command java -ErrorAction SilentlyContinue).Path
  if (-not $JavaCmd) {
    $CandidateJavas = "$env:JAVA_HOME\bin\java.exe", "$env:JAVA_HOME\bin\java"
    $JavaCmd = $CandidateJavas | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not ($env:JAVA_HOME -and $JavaCmd)) {
      Write-Error "Couldn't find 'java'. Please set JAVA_HOME."
      return
    }
  }

  if ($Help) {
    Write-Host @'
Version: ${project.version}

You use the Clojure tools ('clj' or 'clojure') to run Clojure programs
on the JVM, e.g. to start a REPL or invoke a specific function with data.
The Clojure tools will configure the JVM process by defining a classpath
(of desired libraries), an execution environment (JVM options) and
specifying a main class and args.

Using a deps.edn file (or files), you tell Clojure where your source code
resides and what libraries you need. Clojure will then calculate the full
set of required libraries and a classpath, caching expensive parts of this
process for better performance.

The internal steps of the Clojure tools, as well as the Clojure functions
you intend to run, are parameterized by data structures, often maps. Shell
command lines are not optimized for passing nested data, so instead you
will put the data structures in your deps.edn file and refer to them on the
command line via 'aliases' - keywords that name data structures.

'clj' and 'clojure' differ in that 'clj' has extra support for use as a REPL
in a terminal, and should be preferred unless you don't want that support,
then use 'clojure'.

Usage:
  Start a REPL   clj     [clj-opt*] [-A:aliases] [init-opt*]
  Exec function  clojure [clj-opt*] -X[:aliases] [a/fn] [kpath v]*
  Run main       clojure [clj-opt*] -M[:aliases] [init-opt*] [main-opt] [arg*]
  Prepare        clojure [clj-opt*] -P [other exec opts]

exec-opts:
  -A:aliases     Use aliases to modify classpath
  -X[:aliases]   Use aliases to modify classpath or supply exec fn/args
  -M[:aliases]   Use aliases to modify classpath or supply main opts
  -P             Prepare deps - download libs, cache classpath, but don't exec

clj-opts:
  -Jopt          Pass opt through in java_opts, ex: -J-Xmx512m
  -Sdeps EDN     Deps data to use as the final deps file
  -Spath         Compute classpath and echo to stdout only
  -Scp CP        Do NOT compute or cache classpath, use this one instead
  -Srepro        Use only the local deps.edn (ignore other config files)
  -Sforce        Force recomputation of the classpath (don't use the cache)
  -Sverbose      Print important path info to console
  -Sdescribe     Print environment and command parsing info as data
  -Sthreads      Set specific number of download threads
  -Strace        Write a trace.edn file that traces deps expansion
  --             Stop parsing dep options and pass remaining arguments to clojure.main

init-opt:
  -i, --init path     Load a file or resource
  -e, --eval string   Eval exprs in string; print non-nil values
  --report target     Report uncaught exception to "file" (default), "stderr", or "none"

main-opt:
  -m, --main ns-name  Call the -main function from namespace w/args
  -r, --repl          Run a repl
  path                Run a script from a file or resource
  -                   Run a script from standard input
  -h, -?, --help      Print this help message and exit

Programs provided by :deps alias:
 -X:deps tree              Print dependency tree
 -X:deps mvn-pom           Generate (or update) pom.xml with deps and paths
 -X:deps mvn-install       Install a maven jar to the local repository cache
 -X:deps git-resolve-tags  Resolve git coord tags to shas and update deps.edn

For more info, see:
  https://clojure.org/guides/deps_and_cli
  https://clojure.org/reference/repl_and_main
'@
    return
  }

  # Execute resolve-tags command
  if ($ResolveTags) {
    if (Test-Path deps.edn) {
      & $JavaCmd -classpath $ToolsCP clojure.main -m clojure.tools.deps.alpha.script.resolve-tags --deps-file=deps.edn
      return
    } else {
      Write-Error 'deps.edn does not exist'
      return
    }
  }

  # Determine user config directory
  if ($env:CLJ_CONFIG) {
    $ConfigDir = $env:CLJ_CONFIG
  } elseif ($env:HOME) {
    $ConfigDir = "$env:HOME\.clojure"
  } else {
    $ConfigDir = "$env:USERPROFILE\.clojure"
  }

  # If user config directory does not exist, create it
  if (!(Test-Path "$ConfigDir")) {
    New-Item -Type Directory "$ConfigDir" | Out-Null
  }
  if (!(Test-Path "$ConfigDir\deps.edn")) {
    Copy-Item "$InstallDir\example-deps.edn" "$ConfigDir\deps.edn"
  }

  # Determine user cache directory
  if ($env:CLJ_CACHE) {
    $UserCacheDir = $env:CLJ_CACHE
  } else {
    $UserCacheDir = "$ConfigDir\.cpcache"
  }

  # Chain deps.edn in config paths. repro=skip config dir
  $ConfigProject='deps.edn'
  if ($Repro) {
    $ConfigPaths = "$InstallDir\deps.edn", 'deps.edn'
  } else {
    $ConfigUser = "$ConfigDir\deps.edn"
    $ConfigPaths = "$InstallDir\deps.edn", "$ConfigDir\deps.edn", 'deps.edn'
  }
  $ConfigStr = $ConfigPaths -join ','

  # Determine whether to use user or project cache
  if (Test-Path deps.edn) {
    $CacheDir = '.cpcache'
  } else {
    $CacheDir = $UserCacheDir
  }

  # Construct location of cached classpath file
  $CacheKey = "$($ResolveAliases -join '')|$($ClassPathAliases -join '')|$($AllAliases -join '')|$($JvmAliases -join '')|$($MainAliases -join '')|$($ToolAliases -join '')|$DepsData|$($ConfigPaths -join '|')"
  $CacheKeyHash = (Get-StringHash $CacheKey) -replace '-', ''

  $LibsFile = "$CacheDir\$CacheKeyHash.libs"
  $CpFile = "$CacheDir\$CacheKeyHash.cp"
  $JvmFile = "$CacheDir\$CacheKeyHash.jvm"
  $MainFile = "$CacheDir\$CacheKeyHash.main"
  $BasisFile = "$CacheDir\$CacheKeyHash.basis"

  # Print paths in verbose mode
  if ($Verbose) {
    Write-Output @"
version      = $Version
install_dir  = $InstallDir
config_dir   = $ConfigDir
config_paths = $ConfigPaths
cache_dir    = $CacheDir
cp_file      = $CpFile
"@
  }

  # Check for stale classpath file
  $Stale = $FALSE
  if ($Force -or $Trace -or $Prep -or !(Test-Path $CpFile)) {
    $Stale = $TRUE
  } elseif ($ConfigPaths | Where-Object { Test-NewerFile $_ $CpFile }) {
    $Stale = $TRUE
  }

  # Make tools args if needed
  if ($Stale -or $Pom) {
    $ToolsArgs = @()
    if ($DepsData) {
      $ToolsArgs += '--config-data'
      $ToolsArgs += $DepsData
    }
    if ($ResolveAliases) {
      $ToolsArgs += "-R$($ResolveAliases -join '')"
    }
    if ($ClassPathAliases) {
      $ToolsArgs += "-C$($ClassPathAliases -join '')"
    }
    if ($JvmAliases) {
      $ToolsArgs += "-J$($JvmAliases -join '')"
    }
    if ($MainAliases) {
      $ToolsArgs += "-M$($MainAliases -join '')"
    }
    if ($ToolAliases) {
      $ToolsArgs += "-T$($ToolAliases -join '')"
    }
    if ($AllAliases) {
      $ToolsArgs += "-A$($AllAliases -join '')"
    }
    if ($ForceCp) {
      $ToolsArgs += '--skip-cp'
    }
    if ($Threads) {
      $ToolsArgs += '--threads'
      $ToolsArgs += $Threads
    }
    if ($Trace) {
      $ToolsArgs += '--trace'
    }
  }

  # If stale, run make-classpath to refresh cached classpath
  if ($Stale -and (-not $Describe)) {
    if ($Verbose) {
      Write-Host "Refreshing classpath"
    }
    & $JavaCmd -classpath $ToolsCp clojure.main -m clojure.tools.deps.alpha.script.make-classpath2 --config-user $ConfigUser --config-project $ConfigProject --basis-file $BasisFile --libs-file $LibsFile --cp-file $CpFile --jvm-file $JvmFile --main-file $MainFile @ToolsArgs
    if ($LastExitCode -ne 0) {
      return
    }
  }

  if ($Describe) {
    $CP = ''
  } elseif ($ForceCp) {
    $CP = $ForceCp
  } else {
    $CP = Get-Content $CpFile
  }

  if ($Prep) {
    # Already done
  } elseif ($Pom) {
    & $JavaCmd -classpath $ToolsCp clojure.main -m clojure.tools.deps.alpha.script.generate-manifest2 --config-user $ConfigUser --config-project $ConfigProject --gen=pom @ToolsArgs
  } elseif ($PrintClassPath) {
    Write-Output $CP
  } elseif ($Describe) {
    $PathVector = ($ConfigPaths | ForEach-Object { "`"$_`"" }) -join ' '
    Write-Output @"
{:version "$Version"
 :config-files [$PathVector]
 :config-user "$ConfigUser"
 :config-project "$ConfigProject"
 :install-dir "$InstallDir"
 :config-dir "$ConfigDir"
 :cache-dir "$CacheDir"
 :force $Force
 :repro $Repro
 :resolve-aliases "$($ResolveAliases -join ' ')"
 :classpath-aliases "$($ClasspathAliases -join ' ')"
 :jvm-aliases "$($JvmAliases -join ' ')"
 :main-aliases "$($MainAliases -join ' ')"
 :tool-aliases "$($ToolAliases -join ' ')"
 :all-aliases "$($AllAliases -join ' ')"}
"@
  } elseif ($Tree) {
    & $JavaCmd -classpath $ToolsCp clojure.main -m clojure.tools.deps.alpha.script.print-tree --libs-file $LibsFile
  } elseif ($Trace) {
    Write-Host "Writing trace.edn"
  } else {
    if (Test-Path $JvmFile) {
      # TODO this seems dangerous
      $JvmCacheOpts = (Get-Content $JvmFile) -split '\s+'
    }

    if ($ExecAlias) {
      & $JavaCmd @JvmOpts "-Dclojure.basis=$BasisFile" -classpath "$CP;$InstallDir" clojure.main -m clj-exec @ExecAlias
    } else {
      if (Test-Path $MainFile) {
        # TODO this seems dangerous
        $MainCacheOpts = ((Get-Content $MainFile) -split '\s+') -replace '"', '\"'
      }
      & $JavaCmd @JvmCacheOpts @JvmOpts "-Dclojure.basis=$BasisFile" "-Dclojure.libfile=$LibsFile" -classpath $CP clojure.main @MainCacheOpts @ClojureArgs
    }
  }
}

New-Alias -Name clj -Value Invoke-Clojure
New-Alias -Name clojure -Value Invoke-Clojure