# ramjet

A fast, lightweight CLI tool for macOS that reports system-wide RAM usage using Mach APIs.

## Features

- **Fast**: Single system query per run, minimal overhead
- **Zero allocations**: Stack-only memory usage
- **Native**: Direct Mach API integration for accurate statistics
- **Clean output**: Human-readable memory values (MB/GB)
- **Watch mode**: Continuous monitoring with configurable interval
- **Interactive TUI**: Full-screen terminal interface with keyboard navigation
- **Memory leak detection**: Automatically detect processes with growing memory usage
- **Process listing**: Top memory-consuming processes
- **Detailed breakdown**: Active, wired, inactive, speculative, compressed memory
- **Color output**: Color-coded by usage level (green/yellow/red)
- **JSON output**: Machine-readable JSON format for scripting
- **Swap statistics**: Swap usage information
- **Memory pressure**: System memory pressure indicator

## Requirements

- macOS (any version with Mach APIs)
- Zig 0.15.2 or later

## Building

```bash
zig build
```

The binary will be created at `zig-out/bin/ramjet`.

## Running

```bash
# Basic usage
./zig-out/bin/ramjet

# Watch mode (updates every 2 seconds)
./zig-out/bin/ramjet --watch

# Watch mode with custom interval (5 seconds)
./zig-out/bin/ramjet --watch 5

# Compact single-line output
./zig-out/bin/ramjet --compact

# Show top 10 processes by memory
./zig-out/bin/ramjet --top 10

# Show detailed memory breakdown
./zig-out/bin/ramjet --breakdown

# Disable colors
./zig-out/bin/ramjet --no-color

# Combine options
./zig-out/bin/ramjet --watch 3 --top 5 --breakdown

# Interactive TUI mode
./zig-out/bin/ramjet --interactive

# Interactive TUI with leak detection
./zig-out/bin/ramjet --interactive --detect-leaks

# Watch mode with leak detection
./zig-out/bin/ramjet --watch --detect-leaks

# JSON output (for scripting)
./zig-out/bin/ramjet --json
```

## Command-Line Options

- `-w, --watch [SECONDS]` - Watch mode (update every N seconds, default: 2)
- `-c, --compact` - Compact single-line output format
- `-i, --interactive` - Interactive TUI mode with keyboard controls
- `--detect-leaks` - Detect memory leaks (requires watch or interactive mode)
- `--top N` - Show top N processes by memory usage (1-100)
- `-b, --breakdown` - Show detailed memory breakdown
- `--json` - Output in JSON format
- `--no-color` - Disable colored output
- `-v, --version` - Show version information
- `-h, --help` - Show help message

## Output Examples

### Standard Output
```
Total:    24.0 GB
Used:     11.8 GB (49.1%)
Free:     332.7 MB
Cached:   9.3 GB
Swap:     0.0 MB / 0.0 MB
Pressure: Normal
```

### Compact Output
```
24.0G total, 11.8G used (49.1%), 332.7M free, 9.3G cached
```

### With Breakdown
```
Total:    24.0 GB
Used:     11.8 GB (49.1%)
Free:     332.7 MB
Cached:   9.3 GB
Swap:     0.0 MB / 0.0 MB
Pressure: Normal
Memory Breakdown:
  Active:     9.3 GB
  Wired:      2.5 GB
  Inactive:   9.1 GB
  Speculative: 179.8 MB
  Compressed: 2.1 GB
```

### With Top Processes
```
Total:    24.0 GB
Used:     11.8 GB (49.1%)
...
Top 5 Processes by Memory:
    1234  Chrome             2.1 GB
    5678  Xcode              1.8 GB
    9012  Slack              512.3 MB
    3456  Terminal           128.5 MB
    7890  Finder             64.2 MB
```

### JSON Output
```json
{
  "total": 25769803776,
  "used": 12666736640,
  "free": 357171200,
  "cached": 10000000000,
  "swap_used": 0,
  "swap_total": 0,
  "pressure": "Normal"
}
```

### Interactive TUI Mode

The interactive TUI provides a full-screen interface with real-time updates:

```
ramjet - Memory Monitor
Total: 24.0 GB  Used: 12.1 GB (50.3%)  Free: 1.1 GB
Pressure: Normal

Processes (Sorted by: memory) - 20 shown
------------------------------------------------------------
>    1234  Chrome                             2.1 GB
     5678  Xcode                              1.8 GB
     9012  Slack                             512.3 MB
     ...

Controls: [↑↓] Navigate  [s] Sort  [l] Toggle Leaks  [r] Refresh  [q] Quit  [h] Help
```

**Keyboard Controls:**
- `↑` / `↓` - Navigate up/down through process list
- `s` - Cycle sort mode (memory → PID → name)
- `l` - Toggle leak detection display
- `r` - Refresh data
- `q` - Quit
- `h` - Help

**Note**: Keys are detected immediately - no need to press Enter!

### Memory Leak Detection

When enabled with `--detect-leaks`, ramjet tracks process memory over time and alerts you to potential leaks:

```
⚠ Potential Memory Leaks:
  1234 Chrome: 2.0 GB -> 2.5 GB (+512.0 MB over 10s)
  5678 Node: 128.0 MB -> 256.0 MB (+128.0 MB over 8s)
```

A process is flagged as a potential leak if:
- Memory growth > 50MB, or
- Memory growth > 20% of original size

Leak detection requires at least 2 snapshots, so it works best with `--watch` or `--interactive` mode.

## How It Works

- Uses `sysctlbyname("hw.memsize")` to get total physical memory
- Queries Mach APIs (`host_statistics64`) for detailed VM statistics
- Converts page counts to bytes using system page size
- Calculates used (active + wired), free, and cached (inactive + speculative) memory
- Uses `proc_pidinfo` with `PROC_PIDTASKINFO` for process memory statistics (no special privileges required)
- Uses `sysctlbyname("vm.memory_pressure")` for memory pressure information

## Color Coding

- **Green**: Memory usage < 50%
- **Yellow**: Memory usage 50-80%
- **Red**: Memory usage > 80%

## Interactive TUI Mode

The interactive TUI mode (`--interactive` or `-i`) provides a full-screen terminal interface with:

- **Real-time updates**: Memory statistics and process list update automatically
- **Keyboard navigation**: Navigate through processes with arrow keys
- **Multiple sort modes**: Sort by memory usage, PID, or process name
- **Visual selection**: Highlighted process indicator
- **Scrollable list**: View up to 20 processes at a time with automatic scrolling
- **Leak detection display**: Toggle leak warnings on/off with the 'l' key
- **Immediate key response**: Keys are detected instantly without pressing Enter

The TUI automatically restores your terminal settings when you exit, so your terminal will return to normal operation.

## Memory Leak Detection

The `--detect-leaks` option enables automatic detection of processes with growing memory usage. This feature:

- **Tracks memory over time**: Maintains a history of process memory snapshots
- **Detects significant growth**: Flags processes with >50MB growth or >20% increase
- **Shows growth details**: Displays old size, new size, growth amount, and time span
- **Works with watch/interactive modes**: Requires continuous monitoring to build history

**Usage:**
```bash
# Watch mode with leak detection
ramjet --watch --detect-leaks

# Interactive TUI with leak detection
ramjet --interactive --detect-leaks
```

## Process Listing

Note: Process memory information requires appropriate permissions. Some system processes (like WindowServer, kernel_task) may not be accessible via `proc_pidinfo` without special privileges due to macOS security restrictions. These processes will not appear in the process list. Activity Monitor can show them because it runs with system entitlements. The tool will gracefully handle inaccessible processes and show all processes it can access.

## Installation

### Homebrew (Recommended)

Install via Homebrew:

```bash
brew tap maximbilan/ramjet https://github.com/maximbilan/ramjet
brew install ramjet
```

Or install in one command:

```bash
brew install maximbilan/ramjet/ramjet
```

After installation, you can use `ramjet` from anywhere:

```bash
ramjet
ramjet --watch
ramjet --top 10
```

### Manual Installation

Build from source:

```bash
git clone https://github.com/maximbilan/ramjet.git
cd ramjet
zig build
sudo cp zig-out/bin/ramjet /usr/local/bin/
```

Then run from anywhere:

```bash
ramjet
ramjet --watch
ramjet --top 10
```

## License

See [LICENSE](LICENSE) file.
