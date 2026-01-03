# typed: false
# frozen_string_literal: true

# This file is a Homebrew formula for ramjet.
# For more information, see: https://docs.brew.sh/Formula-Cookbook

class Ramjet < Formula
  desc "Fast, lightweight CLI tool for macOS that reports system-wide RAM usage using Mach APIs"
  homepage "https://github.com/maximbilan/ramjet"
  url "https://github.com/maximbilan/ramjet.git",
      tag:      "v0.1.1"
  license "MIT"
  head "https://github.com/maximbilan/ramjet.git", branch: "main"

  depends_on "zig" => :build

  def install
    system "zig", "build", "--release=fast"
    bin.install "zig-out/bin/ramjet"
  end

  test do
    output = shell_output("#{bin}/ramjet 2>&1")
    assert_match "Total:", output
  end
end
