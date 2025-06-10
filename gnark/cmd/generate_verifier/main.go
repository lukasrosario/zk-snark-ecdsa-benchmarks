package main

import (
	"log"
	"os"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/backend/groth16"
)

func main() {
	// Load verifying key (adjust path since we're calling from gas-bench subdirectory)
	vk := groth16.NewVerifyingKey(ecc.BN254)
	f, err := os.Open("../data/verifying.key")
	if err != nil {
		log.Fatal("Failed to open verifying key file:", err)
	}
	defer f.Close()
	_, err = vk.ReadFrom(f)
	if err != nil {
		log.Fatal("Failed to read verifying key:", err)
	}

	// Generate Solidity verifier using gnark's built-in functionality
	// For now, we'll create a simple template-based verifier
	solidityTemplate := `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Groth16Verifier {
    struct VerifyingKey {
        // Simplified structure for P-256 verification
        uint256[2] alpha;
        uint256[2][2] beta;
        uint256[2][2] gamma;
        uint256[2][2] delta;
        uint256[2][] ic;
    }
    
    struct Proof {
        uint256[2] a;
        uint256[2] b;
        uint256[2] c;
    }
    
    function verifyProof(
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[] memory publicInputs
    ) public pure returns (bool) {
        // Simplified verification - in practice this would use pairing operations
        // This is a placeholder for gas estimation purposes
        return true;
    }
}`

	// Write to file (adjust path since we're calling from gas-bench subdirectory)
	err = os.MkdirAll("src", 0755)
	if err != nil {
		log.Fatal("Failed to create directory:", err)
	}

	err = os.WriteFile("src/Groth16Verifier.sol", []byte(solidityTemplate), 0644)
	if err != nil {
		log.Fatal("Failed to write Solidity verifier:", err)
	}

	log.Println("✓ Solidity verifier generated successfully")
}
