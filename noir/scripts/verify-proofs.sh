#!/bin/bash

set -e

CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_message() {
  local color=$1
  local message=$2
  echo -e "${color}${message}${NC}"
}

# Source Barretenberg environment if it exists
if [ -f "$HOME/.bb/env" ]; then
  print_message "$CYAN" "Sourcing Barretenberg environment"
  source "$HOME/.bb/env"
fi

# Check if bb is available
if ! command -v bb &> /dev/null; then
  print_message "$RED" "❌ Error: bb command not found"
  print_message "$CYAN" "Make sure Barretenberg (bb) is installed and in your PATH"
  print_message "$CYAN" "You can install it with: curl -L https://raw.githubusercontent.com/AztecProtocol/aztec-packages/master/barretenberg/bbup/install | bash"
  print_message "$CYAN" "Then source the environment: source ~/.bb/env"
  exit 1
fi

print_message "$CYAN" "🔍 Starting proof verification for Noir ECDSA test cases..."

# Create persistent output directories
mkdir -p /out/verification

# Check if proofs exist
if [ ! -d "/out/proofs" ] || [ -z "$(find /out/proofs -name 'proof' -type f)" ]; then
    print_message "$RED" "❌ Proofs not found in /out/proofs"
    print_message "$RED" "   Please run the proof generation step first."
    exit 1
fi

# Count total test cases
TOTAL_PROOFS=$(find /out/proofs -name "test_case_*" -type d | wc -l)
if [ "$TOTAL_PROOFS" -eq 0 ]; then
    print_message "$RED" "❌ No proof directories found in /out/proofs"
    print_message "$RED" "   Please run the proof generation step first."
    exit 1
fi

print_message "$CYAN" "📊 Found $TOTAL_PROOFS test cases to verify"

# Check if verification has already been completed
VERIFICATION_SUMMARY="/out/verification/verification_summary.json"
if [ -f "$VERIFICATION_SUMMARY" ]; then
    COMPLETED_VERIFICATIONS=$(jq -r '.results | length' "$VERIFICATION_SUMMARY" 2>/dev/null || echo "0")
    if [ "$COMPLETED_VERIFICATIONS" -eq "$TOTAL_PROOFS" ]; then
        print_message "$GREEN" "✅ All proofs already verified, skipping verification step."
        print_message "$GREEN" "   Found: $VERIFICATION_SUMMARY with $COMPLETED_VERIFICATIONS results"
        print_message "$GREEN" "   To re-verify, delete the '/out/verification' directory first."
        exit 0
    fi
fi

CURRENT_TEST=0
VERIFICATION_RESULTS=()

# Find all proof directories and verify each one
for proof_dir in /out/proofs/test_case_*; do
  if [ -d "$proof_dir" ]; then
    CURRENT_TEST=$((CURRENT_TEST + 1))
    BASENAME=$(basename "$proof_dir")
    
    PROOF_FILE="$proof_dir/proof"
    VK_FILE="$proof_dir/vk"
    
    # Check if required files exist
    if [ ! -f "$PROOF_FILE" ] || [ ! -f "$VK_FILE" ]; then
        print_message "$RED" "❌ [$CURRENT_TEST/$TOTAL_PROOFS] Missing files for $BASENAME"
        print_message "$RED" "   Expected: $PROOF_FILE and $VK_FILE"
        exit 1
    fi
    
    print_message "$CYAN" "🔍 [$CURRENT_TEST/$TOTAL_PROOFS] Verifying proof for $BASENAME..."
    
    # Change to the proof directory for verification
    cd "$proof_dir"
    
    # Measure verification time
    START_TIME=$(date +%s.%N)
    
    # Verify the proof
    if bb verify -k vk -p proof -i public_inputs --oracle_hash keccak; then
        END_TIME=$(date +%s.%N)
        VERIFICATION_TIME=$(echo "$END_TIME - $START_TIME" | bc -l)
        
        print_message "$GREEN" "✅ [$CURRENT_TEST/$TOTAL_PROOFS] Proof for $BASENAME verified successfully (${VERIFICATION_TIME}s)"
        
        # Store result for summary
        VERIFICATION_RESULTS+=("{\"test_case\":\"$BASENAME\",\"verification_time\":$VERIFICATION_TIME,\"status\":\"success\"}")
    else
        print_message "$RED" "❌ [$CURRENT_TEST/$TOTAL_PROOFS] Proof verification failed for $BASENAME"
        exit 1
    fi
    
    # Return to root directory
    cd /app
  fi
done

# Generate verification summary
print_message "$CYAN" "📊 Generating verification summary..."

# Create JSON summary
cat > "$VERIFICATION_SUMMARY" << EOF
{
  "total_test_cases": $TOTAL_PROOFS,
  "timestamp": "$(date -u --iso-8601=seconds)",
  "results": [
    $(IFS=','; echo "${VERIFICATION_RESULTS[*]}")
  ]
}
EOF

# Calculate and display aggregate statistics
if [ ${#VERIFICATION_RESULTS[@]} -gt 0 ]; then
    print_message "$CYAN" "📈 Calculating aggregate statistics..."
    
    # Calculate average, min, max verification times
    avg_time=$(jq -r '[.results[].verification_time] | add / length' "$VERIFICATION_SUMMARY")
    min_time=$(jq -r '[.results[].verification_time] | min' "$VERIFICATION_SUMMARY")
    max_time=$(jq -r '[.results[].verification_time] | max' "$VERIFICATION_SUMMARY")
    std_dev=$(jq -r '
        .results | 
        map(.verification_time) | 
        (add / length) as $mean |
        map(($mean - .) * ($mean - .)) |
        (add / length) | 
        sqrt
    ' "$VERIFICATION_SUMMARY")
    
    # Create summary report
    cat > "/out/verification/verification_report.txt" << EOF
Noir ECDSA Proof Verification Report
====================================

Total Test Cases: $TOTAL_PROOFS
All Verifications: Successful

Verification Time Statistics:
  Average: $(printf "%.6f" $avg_time) seconds
  Minimum: $(printf "%.6f" $min_time) seconds  
  Maximum: $(printf "%.6f" $max_time) seconds
  Std Dev: $(printf "%.6f" $std_dev) seconds

Generated at: $(date -u --iso-8601=seconds)
EOF

    print_message "$GREEN" "✅ All proofs verified successfully!"
    print_message "$GREEN" "📁 Verification results: /out/verification/"
    print_message "$CYAN" "📈 Verification Statistics:"
    echo "----------------------------------------"
    printf "Average Time: %.6f ± %.6f seconds\n" $avg_time $std_dev
    printf "Min Time: %.6f seconds\n" $min_time
    printf "Max Time: %.6f seconds\n" $max_time
    echo "----------------------------------------"
else
    print_message "$RED" "❌ No verification results to summarize"
    exit 1
fi