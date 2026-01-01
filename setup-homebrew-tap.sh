#!/bin/bash
# Script to set up a Homebrew tap for ramjet

set -e

TAP_NAME="maximbilan/ramjet"
FORMULA_NAME="ramjet"

echo "Setting up Homebrew tap: $TAP_NAME"

# Create the tap
echo "Creating tap..."
brew tap-new "$TAP_NAME"

# Get the tap repository path
TAP_REPO=$(brew --repository "$TAP_NAME")

# Copy the formula
echo "Copying formula..."
cp Formula/ramjet.rb "$TAP_REPO/Formula/$FORMULA_NAME.rb"

# Navigate to tap repo
cd "$TAP_REPO"

# Check if git is initialized
if [ ! -d .git ]; then
    echo "Initializing git repository..."
    git init
    git remote add origin "https://github.com/$TAP_NAME.git" || true
fi

# Add and commit
echo "Committing formula..."
git add "Formula/$FORMULA_NAME.rb"
git commit -m "Add $FORMULA_NAME formula" || echo "No changes to commit"

echo ""
echo "✅ Tap setup complete!"
echo ""
echo "Next steps:"
echo "1. Create a GitHub repository: https://github.com/new"
echo "   Repository name: homebrew-ramjet"
echo "   (Homebrew automatically adds 'homebrew-' prefix)"
echo ""
echo "2. Push the tap repository:"
echo "   cd $TAP_REPO"
echo "   git remote set-url origin git@github.com:maximbilan/homebrew-ramjet.git"
echo "   git push -u origin main"
echo ""
echo "3. Users can then install with:"
echo "   brew tap $TAP_NAME"
echo "   brew install $FORMULA_NAME"
