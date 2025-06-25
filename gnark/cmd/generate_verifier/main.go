package main

import (
	"crypto/sha256"
	"log"
	"os"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/backend/solidity"
)

func main() {
	// Load verifying key generated during setup step
	vk := groth16.NewVerifyingKey(ecc.BN254)
	file, err := os.Open("/out/verifying.key")
	if err != nil {
		log.Fatal("Failed to open verifying.key:", err)
	}
	_, err = vk.ReadFrom(file)
	file.Close()
	if err != nil {
		log.Fatal("Failed to read verifying key:", err)
	}

	// Ensure src directory exists
	err = os.MkdirAll("src", 0755)
	if err != nil {
		log.Fatal("Failed to create src directory:", err)
	}

	// Create output file for the Solidity verifier
	solidityFile, err := os.Create("src/Groth16Verifier.sol")
	if err != nil {
		log.Fatal("Failed to create Solidity verifier file:", err)
	}
	defer solidityFile.Close()

	// Use gnark's built-in ExportSolidity method to generate the proper verifier
	err = vk.ExportSolidity(solidityFile, solidity.WithHashToFieldFunction(sha256.New()))
	if err != nil {
		log.Fatal("Failed to export Solidity verifier:", err)
	}

	log.Println("✓ Solidity verifier generated successfully")
}
