class Ctype < Formula
  desc "Terminal typing test"
  homepage "https://github.com/en9inerd/ctype"
  license "MIT"
  version "VERSION_PLACEHOLDER"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/en9inerd/ctype/releases/download/vVERSION_PLACEHOLDER/ctype_aarch64-macos.tar.gz"
      sha256 "SHA256_MACOS_ARM64"
    else
      url "https://github.com/en9inerd/ctype/releases/download/vVERSION_PLACEHOLDER/ctype_x86_64-macos.tar.gz"
      sha256 "SHA256_MACOS_X86_64"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/en9inerd/ctype/releases/download/vVERSION_PLACEHOLDER/ctype_aarch64-linux.tar.gz"
      sha256 "SHA256_LINUX_ARM64"
    else
      url "https://github.com/en9inerd/ctype/releases/download/vVERSION_PLACEHOLDER/ctype_x86_64-linux.tar.gz"
      sha256 "SHA256_LINUX_X86_64"
    end
  end

  def install
    bin.install "ctype"
    (share/"ctype").install "words.txt"
  end

  test do
    assert_match "ctype", shell_output("#{bin}/ctype --version")
  end
end
