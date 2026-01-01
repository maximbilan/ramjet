# Homebrew Installation

## Quick Setup (Using Script)

**Important**: Before setting up the tap, create your first version tag:

```bash
git tag v0.1.0
git push --tags
```

Then proceed with the setup:

1. **Run the setup script**:
   ```bash
   ./setup-homebrew-tap.sh
   ```

2. **Run the setup script**:
   ```bash
   ./setup-homebrew-tap.sh
   ```

3. **Create the GitHub repository** for your tap:
   - Go to https://github.com/new
   - Repository name: `homebrew-ramjet` (Homebrew automatically adds the `homebrew-` prefix)
   - Make it public
   - Don't initialize with README (the script creates the repo structure)

4. **Push the tap repository**:
   ```bash
   cd $(brew --repository maximbilan/ramjet)
   git remote set-url origin git@github.com:maximbilan/homebrew-ramjet.git
   git push -u origin main
   ```

5. **Users can then install with**:
   ```bash
   brew tap maximbilan/ramjet
   brew install ramjet
   ```

## Manual Setup

1. **Create a git tag**:
   ```bash
   git tag v0.1.0
   git push --tags
   ```

2. **Create the tap**:
   ```bash
   brew tap-new maximbilan/ramjet
   ```

3. **Copy the formula**:
   ```bash
   cp Formula/ramjet.rb $(brew --repository maximbilan/ramjet)/Formula/ramjet.rb
   ```

4. **Create GitHub repository** `homebrew-ramjet` and push:
   ```bash
   cd $(brew --repository maximbilan/ramjet)
   git remote add origin git@github.com:maximbilan/homebrew-ramjet.git
   git add Formula/ramjet.rb
   git commit -m "Add ramjet formula"
   git push -u origin main
   ```

## Option 2: Submit to Homebrew Core

For wider distribution, you can submit to the main Homebrew repository:

1. Fork the [homebrew-core](https://github.com/Homebrew/homebrew-core) repository
2. Create a new formula file: `Formula/r/ramjet.rb`
3. Submit a pull request

**Requirements for homebrew-core:**
- Project must have at least 30 stars on GitHub
- Project must have been tagged with a stable version
- Project must have been around for at least 30 days
- Must have a clear description and documentation

## Formula Details

The formula (`Formula/ramjet.rb`) includes:
- Dependency on Zig (build requirement)
- Builds using `zig build -Doptimize=ReleaseFast`
- Installs the binary to `bin/ramjet`
- Includes a basic test

## Updating the Formula

When you release a new version:

1. Create a git tag:
   ```bash
   git tag v0.1.0
   git push --tags
   ```

2. Update the formula's `url` and `version` fields

3. Update the SHA256 checksum (if using tarball releases)

## Testing the Formula Locally

After setting up the tap:

```bash
# Test installation from the tap
brew install --build-from-source maximbilan/ramjet/ramjet

# Or test directly from the formula file (if in a tap repo)
brew install --build-from-source Formula/ramjet.rb
```

## Updating the Formula for New Versions

1. **Create a new git tag**:
   ```bash
   git tag v0.2.0
   git push --tags
   ```

2. **Update the formula** (`Formula/ramjet.rb`):
   - Change the `tag` value to the new version
   - Optionally update the `revision` if needed

3. **Commit and push to the tap repository**:
   ```bash
   cd $(brew --repository maximbilan/ramjet)
   git add Formula/ramjet.rb
   git commit -m "Update ramjet to v0.2.0"
   git push
   ```
