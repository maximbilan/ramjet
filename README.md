# ramjet

A fast, lightweight CLI tool for macOS that reports system-wide RAM usage using Mach APIs.

## Features

- **Fast**: Single system query per run, minimal overhead
- **Zero allocations**: Stack-only memory usage
- **Native**: Direct Mach API integration for accurate statistics
- **Clean output**: Human-readable memory values (MB/GB)

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
# Build and run in one command
zig build run

# Or run the binary directly
./zig-out/bin/ramjet
```

## Output Example

```
Total:    24.0 GB
Used:     11.8 GB (49.3%)
Free:     539.8 MB
Cached:   9.4 GB
```

## How It Works

- Uses `sysctlbyname("hw.memsize")` to get total physical memory
- Queries Mach APIs (`host_statistics64`) for detailed VM statistics
- Converts page counts to bytes using system page size
- Calculates used (active + wired), free, and cached (inactive + speculative) memory

## Installation (Optional)

To install system-wide:

```bash
sudo cp zig-out/bin/ramjet /usr/local/bin/
```

Then run from anywhere:

```bash
ramjet
```

## License

See [LICENSE](LICENSE) file.
