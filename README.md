# ramjet

A fast, lightweight CLI tool for macOS that reports system-wide RAM usage using Mach APIs.

## Features

- **Fast**: Single system query per run, minimal overhead
- **Zero allocations**: Stack-only memory usage
- **Native**: Direct Mach API integration for accurate statistics
- **Clean output**: Human-readable memory values (MB/GB)
- **Watch mode**: Continuous monitoring with configurable interval
- **Process listing**: Top memory-consuming processes
- **Detailed breakdown**: Active, wired, inactive, speculative, compressed memory
- **Color output**: Color-coded by usage level (green/yellow/red)
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
```

## Command-Line Options

- `-w, --watch [SECONDS]` - Watch mode (update every N seconds, default: 2)
- `-c, --compact` - Compact single-line output format
- `--top N` - Show top N processes by memory usage
- `-b, --breakdown` - Show detailed memory breakdown
- `--no-color` - Disable colored output
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

## Process Listing

Note: Process memory information requires appropriate permissions. Some system processes (like WindowServer, kernel_task) may not be accessible via `proc_pidinfo` without special privileges due to macOS security restrictions. These processes will not appear in the process list. Activity Monitor can show them because it runs with system entitlements. The tool will gracefully handle inaccessible processes and show all processes it can access.

## Installation

### Homebrew (Recommended)

Install via Homebrew:

```bash
brew tap maximbilan/ramjet
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
```

### Setting Up Homebrew Tap (For Contributors)

See [HOMEBREW.md](HOMEBREW.md) for instructions on creating a Homebrew tap or submitting to homebrew-core.

## License

See [LICENSE](LICENSE) file.
