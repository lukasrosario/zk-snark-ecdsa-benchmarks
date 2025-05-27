#!/bin/bash

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print a colored message
print_message() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

# Function to print a section header
print_section() {
  local message=$1
  echo ""
  print_message "$PURPLE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  print_message "$CYAN" "🔍 $message"
  print_message "$PURPLE" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Function to ask for user confirmation
confirm() {
  local prompt=$1
  local response
  
  echo -e "${YELLOW}$prompt${NC} (y/n): "
  read -r response
  
  case "$response" in
    [yY]|[yY][eE][sS]) 
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Detect operating system
detect_os() {
  case "$(uname -s)" in
    Darwin*)
      echo "macos"
      ;;
    Linux*)
      if grep -q Microsoft /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi
      ;;
    CYGWIN*|MINGW*|MSYS*)
      echo "windows"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}

OS=$(detect_os)

#########################
# Git Installation
#########################

check_git() {
  print_section "Checking Git"
  
  if command -v git &> /dev/null; then
    git_version=$(git --version)
    print_message "$GREEN" "✅ Git is already installed: $git_version"
    return 0
  else
    print_message "$YELLOW" "⚠️ Git is not installed or not in your PATH"
    return 1
  fi
}

install_git() {
  case "$OS" in
    macos)
      print_message "$BLUE" "Installing Git using Homebrew (recommended) or using the installer..."
      print_message "$YELLOW" "Option 1: Install Homebrew and then Git:"
      echo "  /bin/bash -c \$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      echo "  brew install git"
      print_message "$YELLOW" "Option 2: Download the Git installer from:"
      echo "  https://git-scm.com/download/mac"
      ;;
    linux)
      print_message "$BLUE" "Installing Git using your package manager:"
      print_message "$YELLOW" "For Ubuntu/Debian:"
      echo "  sudo apt-get update"
      echo "  sudo apt-get install git"
      print_message "$YELLOW" "For Fedora:"
      echo "  sudo dnf install git"
      print_message "$YELLOW" "For CentOS/RHEL:"
      echo "  sudo yum install git"
      ;;
    wsl)
      print_message "$BLUE" "Installing Git in WSL:"
      print_message "$YELLOW" "Run:"
      echo "  sudo apt-get update"
      echo "  sudo apt-get install git"
      ;;
    windows)
      print_message "$BLUE" "Installing Git on Windows:"
      print_message "$YELLOW" "Download the Git installer from:"
      echo "  https://git-scm.com/download/win"
      ;;
    *)
      print_message "$YELLOW" "Please install Git manually from: https://git-scm.com/downloads"
      ;;
  esac
}

#########################
# Node.js Installation
#########################

check_nodejs() {
  print_section "Checking Node.js"
  
  if command -v node &> /dev/null; then
    node_version=$(node --version)
    print_message "$GREEN" "✅ Node.js is already installed: $node_version"
    
    if command -v npm &> /dev/null; then
      npm_version=$(npm --version)
      print_message "$GREEN" "✅ npm is already installed: $npm_version"
    else
      print_message "$YELLOW" "⚠️ npm is not installed or not in your PATH"
    fi
    
    return 0
  else
    print_message "$YELLOW" "⚠️ Node.js is not installed or not in your PATH"
    return 1
  fi
}

install_nodejs() {
  print_message "$BLUE" "We recommend installing Node.js using NVM (Node Version Manager):"
  
  print_message "$YELLOW" "1. Install NVM:"
  echo "  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
  
  print_message "$YELLOW" "2. Close and reopen your terminal, then install Node.js:"
  echo "  nvm install --lts"
  echo "  nvm use --lts"
  
  case "$OS" in
    macos)
      print_message "$YELLOW" "Alternatively, you can install Node.js using Homebrew:"
      echo "  brew install node"
      ;;
    linux | wsl)
      print_message "$YELLOW" "Alternatively, you can install Node.js using your package manager:"
      echo "  For Ubuntu/Debian: sudo apt-get install nodejs npm"
      echo "  For Fedora: sudo dnf install nodejs"
      ;;
    windows)
      print_message "$YELLOW" "Alternatively, you can download the installer from:"
      echo "  https://nodejs.org/en/download/"
      ;;
  esac
  
  print_message "$YELLOW" "After installation, restart this script to continue setup."
}

#########################
# Bun Installation
#########################

check_bun() {
  print_section "Checking Bun"
  
  if command -v bun &> /dev/null; then
    bun_version=$(bun --version)
    print_message "$GREEN" "✅ Bun is already installed: $bun_version"
    return 0
  else
    print_message "$YELLOW" "⚠️ Bun is not installed or not in your PATH"
    return 1
  fi
}

install_bun() {
  print_message "$BLUE" "Installing Bun..."
  
  if confirm "Would you like to install Bun using curl now?"; then
    if curl -fsSL https://bun.sh/install | bash; then
      print_message "$GREEN" "✅ Bun installed successfully!"
      # Source the Bun environment
      export BUN_INSTALL="$HOME/.bun"
      export PATH="$BUN_INSTALL/bin:$PATH"
      return 0
    else
      print_message "$RED" "❌ Failed to install Bun. Please check your internet connection and try again."
      return 1
    fi
  else
    print_message "$YELLOW" "⚠️ Bun installation skipped."
    print_message "$YELLOW" "You can manually install Bun by running: curl -fsSL https://bun.sh/install | bash"
    return 1
  fi
}

#########################
# Rust Installation
#########################

check_rust() {
  print_section "Checking Rust"
  
  if command -v rustc &> /dev/null && command -v cargo &> /dev/null; then
    rustc_version=$(rustc --version)
    print_message "$GREEN" "✅ Rust is already installed: $rustc_version"
    
    cargo_version=$(cargo --version)
    print_message "$GREEN" "✅ Cargo is already installed: $cargo_version"
    
    return 0
  else
    print_message "$YELLOW" "⚠️ Rust is not installed or not in your PATH"
    return 1
  fi
}

install_rust() {
  print_message "$BLUE" "Installing Rust using rustup..."
  
  if confirm "Would you like to install Rust now?"; then
    # Download and run rustup-init
    if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
      print_message "$GREEN" "✅ Rust installed successfully!"
      # Source the cargo environment
      source "$HOME/.cargo/env" || {
        print_message "$RED" "❌ Failed to source Cargo environment"
        print_message "$YELLOW" "Please restart your terminal or run: source \"$HOME/.cargo/env\""
        exit 1
      }
      
      # Verify Rust is now accessible
      if ! command -v rustc &> /dev/null || ! command -v cargo &> /dev/null; then
        print_message "$RED" "❌ Rust installation completed but Rust is not accessible"
        print_message "$YELLOW" "Please restart your terminal or run: source \"$HOME/.cargo/env\""
        exit 1
      fi
      
      return 0
    else
      print_message "$RED" "❌ Failed to install Rust. Please check your internet connection and try again."
      print_message "$YELLOW" "You can manually install Rust by visiting: https://www.rust-lang.org/tools/install"
      return 1
    fi
  else
    print_message "$YELLOW" "⚠️ Rust installation skipped. You'll need Rust to install circom."
    return 1
  fi
}

#########################
# Circom Installation
#########################

check_circom() {
  print_section "Checking Circom"
  
  if command -v circom &> /dev/null; then
    circom_version=$(circom --version 2>&1 || echo "version unknown")
    print_message "$GREEN" "✅ circom is already installed: $circom_version"
    return 0
  else
    print_message "$YELLOW" "⚠️ circom is not installed or not in your PATH"
    return 1
  fi
}

install_circom() {
  print_message "$BLUE" "Installing circom using cargo..."
  
  if confirm "Would you like to install circom now?"; then
    if cargo install --git https://github.com/iden3/circom.git circom; then
      print_message "$GREEN" "✅ circom installed successfully!"
      return 0
    else
      print_message "$RED" "❌ Failed to install circom."
      print_message "$YELLOW" "You can manually install circom by visiting: https://github.com/iden3/circom"
      return 1
    fi
  else
    print_message "$YELLOW" "⚠️ circom installation skipped."
    print_message "$YELLOW" "You'll need circom to compile the circuits."
    return 1
  fi
}

#########################
# Snarkjs Installation
#########################

check_snarkjs() {
  print_section "Checking snarkjs"
  
  if command -v snarkjs &> /dev/null; then
    snarkjs_version=$(snarkjs --version 2>&1 || echo "version unknown")
    print_message "$GREEN" "✅ snarkjs is already installed: $snarkjs_version"
    return 0
  else
    print_message "$YELLOW" "⚠️ snarkjs is not installed or not in your PATH"
    return 1
  fi
}

install_snarkjs() {
  print_message "$BLUE" "Installing snarkjs globally using npm..."
  
  if confirm "Would you like to install snarkjs now?"; then
    if npm install -g snarkjs@latest; then
      print_message "$GREEN" "✅ snarkjs installed successfully!"
      return 0
    else
      print_message "$RED" "❌ Failed to install snarkjs."
      print_message "$YELLOW" "You can manually install snarkjs by running: npm install -g snarkjs"
      return 1
    fi
  else
    print_message "$YELLOW" "⚠️ snarkjs installation skipped."
    print_message "$YELLOW" "You'll need snarkjs to generate and verify proofs."
    return 1
  fi
}

#########################
# Hyperfine Installation
#########################

check_hyperfine() {
  print_section "Checking Hyperfine"
  
  if command -v hyperfine &> /dev/null; then
    hyperfine_version=$(hyperfine --version 2>&1 || echo "version unknown")
    print_message "$GREEN" "✅ Hyperfine is already installed: $hyperfine_version"
    return 0
  else
    print_message "$YELLOW" "⚠️ Hyperfine is not installed or not in your PATH"
    return 1
  fi
}

install_hyperfine() {
  print_message "$BLUE" "Installing Hyperfine..."
  
  if confirm "Would you like to install Hyperfine now?"; then
    case "$OS" in
      macos)
        if command -v brew &> /dev/null; then
          print_message "$BLUE" "Installing Hyperfine using Homebrew..."
          if brew install hyperfine; then
            print_message "$GREEN" "✅ Hyperfine installed successfully!"
            return 0
          else
            print_message "$RED" "❌ Failed to install Hyperfine using Homebrew."
          fi
        elif command -v cargo &> /dev/null; then
          print_message "$BLUE" "Installing Hyperfine using Cargo..."
          if cargo install hyperfine; then
            print_message "$GREEN" "✅ Hyperfine installed successfully!"
            return 0
          else
            print_message "$RED" "❌ Failed to install Hyperfine using Cargo."
          fi
        else
          print_message "$RED" "❌ Neither Homebrew nor Cargo is available to install Hyperfine."
        fi
        ;;
      linux | wsl)
        if command -v cargo &> /dev/null; then
          print_message "$BLUE" "Installing Hyperfine using Cargo..."
          if cargo install hyperfine; then
            print_message "$GREEN" "✅ Hyperfine installed successfully!"
            return 0
          else
            print_message "$RED" "❌ Failed to install Hyperfine using Cargo."
          fi
        else
          print_message "$RED" "❌ Cargo is not available to install Hyperfine."
          print_message "$YELLOW" "For Ubuntu/Debian, you can try: sudo apt install hyperfine (if available)"
          print_message "$YELLOW" "For other distributions, see: https://github.com/sharkdp/hyperfine#installation"
        fi
        ;;
      *)
        print_message "$RED" "❌ Automatic installation of Hyperfine is not supported for your OS."
        print_message "$YELLOW" "Please visit https://github.com/sharkdp/hyperfine#installation for manual installation instructions."
        ;;
    esac
    return 1
  else
    print_message "$YELLOW" "⚠️ Hyperfine installation skipped."
    print_message "$YELLOW" "You'll need Hyperfine for benchmarking."
    return 1
  fi
}

#########################
# Foundry Installation
#########################

check_foundry() {
  print_section "Checking Foundry"
  
  if command -v forge &> /dev/null && command -v cast &> /dev/null && command -v anvil &> /dev/null; then
    forge_version=$(forge --version 2>&1 | head -n 1 || echo "version unknown")
    print_message "$GREEN" "✅ Foundry (forge) is already installed: $forge_version"
    
    cast_version=$(cast --version 2>&1 | head -n 1 || echo "version unknown")
    print_message "$GREEN" "✅ Foundry (cast) is already installed: $cast_version"
    
    anvil_version=$(anvil --version 2>&1 | head -n 1 || echo "version unknown")
    print_message "$GREEN" "✅ Foundry (anvil) is already installed: $anvil_version"
    
    return 0
  else
    print_message "$YELLOW" "⚠️ Foundry is not installed or not in your PATH"
    return 1
  fi
}

install_foundry() {
  print_message "$BLUE" "Installing Foundry using foundryup..."
  
  if confirm "Would you like to install Foundry now?"; then
    # Download and run foundryup
    if curl -L https://foundry.paradigm.xyz | bash; then
      # Source the foundryup environment
      if [ -f "$HOME/.foundry/bin/foundryup" ]; then
        "$HOME/.foundry/bin/foundryup"
        print_message "$GREEN" "✅ Foundry installed successfully!"
        return 0
      elif [ -f "$HOME/.cargo/bin/foundryup" ]; then
        "$HOME/.cargo/bin/foundryup"
        print_message "$GREEN" "✅ Foundry installed successfully!"
        return 0
      else
        print_message "$YELLOW" "⚠️ foundryup installed but not found in expected locations."
        print_message "$YELLOW" "Please run 'foundryup' manually to complete installation."
        return 1
      fi
    else
      print_message "$RED" "❌ Failed to install Foundry."
      print_message "$YELLOW" "You can manually install Foundry by visiting: https://book.getfoundry.sh/getting-started/installation"
      return 1
    fi
  else
    print_message "$YELLOW" "⚠️ Foundry installation skipped."
    print_message "$YELLOW" "You'll need Foundry for Ethereum contract development and testing."
    return 1
  fi
}

#########################
# Main Script
#########################

print_message "$BLUE" "🚀 Starting zk-SNARK ECDSA Benchmarks Setup"
print_message "$BLUE" "Detected OS: $OS"

# Check Git
check_git
if [ $? -ne 0 ]; then
  install_git
  print_message "$YELLOW" "Please install Git and run this script again."
  exit 1
fi

# Check Node.js
check_nodejs
if [ $? -ne 0 ]; then
  install_nodejs
  print_message "$YELLOW" "Please install Node.js and run this script again."
  # Don't exit here, let's check other dependencies
fi

# Check Bun
check_bun
if [ $? -ne 0 ]; then
  install_bun
fi

# Check Rust
check_rust
if [ $? -ne 0 ]; then
  install_rust
fi

# Check circom (only if Rust is available)
if command -v cargo &> /dev/null; then
  check_circom
  if [ $? -ne 0 ]; then
    install_circom
  fi
else
  print_message "$RED" "❌ Cannot check/install circom: Rust/cargo is not available."
  print_message "$YELLOW" "Please install Rust first, then run this script again to install circom."
fi

# Check snarkjs (only if Node.js is available)
if command -v npm &> /dev/null; then
  check_snarkjs
  if [ $? -ne 0 ]; then
    install_snarkjs
  fi
else
  print_message "$RED" "❌ Cannot check/install snarkjs: npm is not available."
  print_message "$YELLOW" "Please install Node.js first, then run this script again to install snarkjs."
fi

# Check Hyperfine
check_hyperfine
if [ $? -ne 0 ]; then
  install_hyperfine
fi

# Check Foundry
check_foundry
if [ $? -ne 0 ]; then
  install_foundry
fi

# Summary
print_section "Setup Summary"

missing_deps=0

# Check all dependencies one more time for the summary
if ! command -v git &> /dev/null; then
  print_message "$RED" "❌ Git: Not installed"
  missing_deps=1
else
  print_message "$GREEN" "✅ Git: Installed"
fi

if ! command -v node &> /dev/null; then
  print_message "$RED" "❌ Node.js: Not installed"
  missing_deps=1
else
  print_message "$GREEN" "✅ Node.js: Installed"
fi

if ! command -v bun &> /dev/null; then
  print_message "$RED" "❌ Bun: Not installed"
  missing_deps=1
else
  print_message "$GREEN" "✅ Bun: Installed"
fi

if ! command -v cargo &> /dev/null; then
  print_message "$RED" "❌ Rust/Cargo: Not installed"
  missing_deps=1
else
  print_message "$GREEN" "✅ Rust/Cargo: Installed"
fi

if ! command -v circom &> /dev/null; then
  print_message "$RED" "❌ circom: Not installed"
  missing_deps=1
else
  print_message "$GREEN" "✅ circom: Installed"
fi

if ! command -v snarkjs &> /dev/null; then
  print_message "$RED" "❌ snarkjs: Not installed"
  missing_deps=1
else
  print_message "$GREEN" "✅ snarkjs: Installed"
fi

if ! command -v hyperfine &> /dev/null; then
  print_message "$RED" "❌ Hyperfine: Not installed"
  missing_deps=1
else
  print_message "$GREEN" "✅ Hyperfine: Installed"
fi

if ! command -v forge &> /dev/null || ! command -v cast &> /dev/null || ! command -v anvil &> /dev/null; then
  print_message "$RED" "❌ Foundry: Not installed"
  missing_deps=1
else
  print_message "$GREEN" "✅ Foundry: Installed"
fi

if [ $missing_deps -eq 0 ]; then
  print_message "$GREEN" "🎉 All dependencies are installed! You're ready to start the benchmarks."
  print_message "$BLUE" "Next steps:"
  print_message "$BLUE" "1. Return to the project root: cd .."
  print_message "$BLUE" "2. Install project dependencies: bun install"
  print_message "$BLUE" "3. Generate test cases: bun run tests:generate"
  print_message "$BLUE" "4. Run benchmarks: cd snarkjs && ./scripts/run.sh"
else
  print_message "$YELLOW" "⚠️ Some dependencies are missing. Please install them and run this script again."
fi

