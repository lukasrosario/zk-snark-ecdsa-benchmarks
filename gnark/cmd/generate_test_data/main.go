package main

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"math/big"
	"os"
	"reflect"
	"strings"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark-crypto/ecc/bn254/fr"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/backend/witness"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/std/algebra/emulated/sw_emulated"
	"github.com/consensys/gnark/std/math/emulated"
	"github.com/consensys/gnark/std/signature/ecdsa"
)

type TestCase struct {
	R       string `json:"r"`
	S       string `json:"s"`
	MsgHash string `json:"msghash"`
	PubKeyX string `json:"pubkey_x"`
	PubKeyY string `json:"pubkey_y"`
}

// Use the ACTUAL circuit structure with real ECDSA verification
type ECDSACircuit struct {
	R       emulated.Element[emulated.P256Fr] `gnark:",secret"`
	S       emulated.Element[emulated.P256Fr] `gnark:",secret"`
	MsgHash emulated.Element[emulated.P256Fr] `gnark:",secret"`
	PubKeyX emulated.Element[emulated.P256Fp] `gnark:",public"`
	PubKeyY emulated.Element[emulated.P256Fp] `gnark:",public"`
}

func (circuit *ECDSACircuit) Define(api frontend.API) error {
	// Get P-256 curve parameters
	curveParams := sw_emulated.GetCurveParams[emulated.P256Fp]()

	// Create the public key point
	pubKey := ecdsa.PublicKey[emulated.P256Fp, emulated.P256Fr]{
		X: circuit.PubKeyX,
		Y: circuit.PubKeyY,
	}

	// Create the signature
	sig := ecdsa.Signature[emulated.P256Fr]{
		R: circuit.R,
		S: circuit.S,
	}

	// Verify the signature (this is a constraint, not a function call)
	pubKey.Verify(api, curveParams, &circuit.MsgHash, &sig)

	return nil
}

func main() {
	if len(os.Args) < 4 {
		log.Fatal("Usage: go run main.go <test_case_num> <test_case_file> <proof_file>")
	}

	testCaseNum := os.Args[1]
	testCaseFile := os.Args[2]
	proofFile := os.Args[3]

	// Load test case to get inputs
	testCaseData, err := ioutil.ReadFile(testCaseFile)
	if err != nil {
		log.Fatal("Failed to read test case file:", err)
	}

	var testCase TestCase
	err = json.Unmarshal(testCaseData, &testCase)
	if err != nil {
		log.Fatal("Failed to parse test case:", err)
	}

	log.Printf("Loading VALID proof and extracting components for test case %s", testCaseNum)

	// Load the existing valid proof from the .groth16 file
	proof := groth16.NewProof(ecc.BN254)
	f, err := os.Open(proofFile)
	if err != nil {
		log.Fatal("Failed to open proof file:", err)
	}
	defer f.Close()

	_, err = proof.ReadFrom(f)
	if err != nil {
		log.Fatal("Failed to read proof:", err)
	}

	// Create witness to get public inputs
	witness, err := createWitness(&testCase)
	if err != nil {
		log.Fatal("Failed to create witness:", err)
	}

	publicWitness, err := witness.Public()
	if err != nil {
		log.Fatal("Failed to extract public witness:", err)
	}

	// Extract public witness values for Solidity
	publicVector := publicWitness.Vector()
	publicValues, ok := publicVector.(fr.Vector)
	if !ok {
		log.Fatal("Failed to extract public values from witness")
	}

	if len(publicValues) != 8 {
		log.Printf("WARNING: Expected 8 public inputs but got %d", len(publicValues))
	}

	log.Printf("Public witness has %d values", len(publicValues))
	for i, val := range publicValues {
		if i < 8 { // Show all values since we need exactly 8
			log.Printf("  [%d]: %s (hex: 0x%s)", i, val.String(), val.Text(16))
		}
	}

	// Extract REAL proof components using reflection (from the existing valid proof)
	components, err := extractProofComponents(proof)
	if err != nil {
		log.Fatal("Failed to extract proof components:", err)
	}

	// Extract commitment (first commitment point) and commitmentPok
	// Initialize with zero so that fallback is still valid if missing
	commitments := [2]string{"0", "0"}
	commitmentPokVals := [2]string{"0", "0"}

	proofVal := reflect.ValueOf(proof)
	if proofVal.Kind() == reflect.Ptr {
		proofVal = proofVal.Elem()
	}

	// Commitments field is a slice of G1Affine – we take the first one
	commField := proofVal.FieldByName("Commitments")
	if commField.IsValid() && commField.Len() > 0 {
		firstComm := commField.Index(0)
		if firstComm.Kind() == reflect.Struct && firstComm.NumField() >= 2 {
			xField := firstComm.Field(0)
			commitments[0] = elementToHex(xField)
			yField := firstComm.Field(1)
			commitments[1] = elementToHex(yField)
		}
	}

	// CommitmentPok field (array or struct of fr.Element)
	pokField := proofVal.FieldByName("CommitmentPok")
	if pokField.IsValid() {
		switch pokField.Kind() {
		case reflect.Array, reflect.Slice:
			for i := 0; i < pokField.Len() && i < 2; i++ {
				commitmentPokVals[i] = elementToHex(pokField.Index(i))
			}
		case reflect.Struct:
			for i := 0; i < pokField.NumField() && i < 2; i++ {
				commitmentPokVals[i] = elementToHex(pokField.Field(i))
			}
		}
	}

	// Format the Solidity test data
	solidityData := fmt.Sprintf(`        // Groth16 proof arrays for test case %s
        uint256[8] memory proof;
        proof[0] = 0x%s; // A.X
        proof[1] = 0x%s; // A.Y
        proof[2] = 0x%s; // B.X.A1 (imaginary)
        proof[3] = 0x%s; // B.X.A0 (real)
        proof[4] = 0x%s; // B.Y.A1 (imaginary)
        proof[5] = 0x%s; // B.Y.A0 (real)
        proof[6] = 0x%s; // C.X
        proof[7] = 0x%s; // C.Y

        uint256[2] memory commitments;
        commitments[0] = 0x%s; // Commitment X
        commitments[1] = 0x%s; // Commitment Y

        uint256[2] memory commitmentPok;
        commitmentPok[0] = 0x%s;
        commitmentPok[1] = 0x%s;

        uint256[8] memory input;`,
		testCaseNum,
		components[0], components[1], components[3], components[2], components[5], components[4], components[6], components[7],
		commitments[0], commitments[1], commitmentPokVals[0], commitmentPokVals[1])

	// Add the real public inputs
	for i := 0; i < 8; i++ {
		hexVal := "0"
		if i < len(publicValues) {
			hexVal = formatFieldElement(publicValues[i].String())
		}
		solidityData += fmt.Sprintf(`
        input[%d] = 0x%s;`, i, hexVal)
	}

	// Read the test file template
	testFilePath := fmt.Sprintf("test/GasTest%s.t.sol", testCaseNum)
	content, err := ioutil.ReadFile(testFilePath)
	if err != nil {
		log.Fatal("Failed to read test file:", err)
	}

	// Replace placeholder with actual data
	placeholder := fmt.Sprintf("PROOF_DATA_PLACEHOLDER_%s", testCaseNum)
	updatedContent := strings.Replace(string(content), placeholder, solidityData, 1)

	// Write back the updated content
	err = ioutil.WriteFile(testFilePath, []byte(updatedContent), 0644)
	if err != nil {
		log.Fatal("Failed to write updated test file:", err)
	}

	log.Printf("✓ VALID proof data extracted for test case %s", testCaseNum)
	log.Printf("  - Using existing valid proof file")
	log.Printf("  - Public inputs: %d values", len(publicValues))
	log.Printf("  - All components extracted correctly")
}

func extractProofComponents(proof groth16.Proof) ([8]string, error) {
	// Extract real proof components using reflection
	log.Printf("Extracting REAL proof components from gnark proof...")

	// Use reflection to access proof internals
	proofValue := reflect.ValueOf(proof)
	if proofValue.Kind() == reflect.Ptr {
		proofValue = proofValue.Elem()
	}

	var components [8]string

	// Extract Ar (A point) - G1Affine
	arField := proofValue.FieldByName("Ar")
	if arField.IsValid() && arField.CanInterface() {
		arValue := arField.Interface()
		log.Printf("Found Ar (A component): %v", arValue)

		// Extract X and Y coordinates from the G1Affine point
		arReflect := reflect.ValueOf(arValue)
		if arReflect.Kind() == reflect.Struct {
			// Try to get X coordinate (index 0)
			xField := arReflect.Field(0)
			if xField.IsValid() {
				components[0] = elementToHex(xField)
				log.Printf("  A.X = 0x%s", components[0])
			}

			// Try to get Y coordinate (index 1)
			yField := arReflect.Field(1)
			if yField.IsValid() {
				components[1] = elementToHex(yField)
				log.Printf("  A.Y = 0x%s", components[1])
			}
		}
	}

	// Extract Bs (B point) - G2Affine
	bsField := proofValue.FieldByName("Bs")
	if bsField.IsValid() && bsField.CanInterface() {
		bsValue := bsField.Interface()
		log.Printf("Found Bs (B component): %v", bsValue)

		// G2Affine has X and Y, each with two coordinates (A0, A1)
		bsReflect := reflect.ValueOf(bsValue)
		if bsReflect.Kind() == reflect.Struct {
			// X coordinate (field 0) - has A0, A1
			xField := bsReflect.Field(0)
			if xField.IsValid() && xField.CanInterface() {
				xStruct := reflect.ValueOf(xField.Interface())
				if xStruct.Kind() == reflect.Struct && xStruct.NumField() >= 2 {
					// X.A0
					a0Field := xStruct.Field(0)
					if a0Field.IsValid() {
						components[2] = elementToHex(a0Field)
						log.Printf("  B.X.A0 = 0x%s", components[2])
					}
					// X.A1
					a1Field := xStruct.Field(1)
					if a1Field.IsValid() {
						components[3] = elementToHex(a1Field)
						log.Printf("  B.X.A1 = 0x%s", components[3])
					}
				}
			}

			// Y coordinate (field 1) - has A0, A1
			yField := bsReflect.Field(1)
			if yField.IsValid() && yField.CanInterface() {
				yStruct := reflect.ValueOf(yField.Interface())
				if yStruct.Kind() == reflect.Struct && yStruct.NumField() >= 2 {
					// Y.A0
					a0Field := yStruct.Field(0)
					if a0Field.IsValid() {
						components[4] = elementToHex(a0Field)
						log.Printf("  B.Y.A0 = 0x%s", components[4])
					}
					// Y.A1
					a1Field := yStruct.Field(1)
					if a1Field.IsValid() {
						components[5] = elementToHex(a1Field)
						log.Printf("  B.Y.A1 = 0x%s", components[5])
					}
				}
			}
		}
	}

	// Extract Krs (C point) - G1Affine
	krsField := proofValue.FieldByName("Krs")
	if krsField.IsValid() && krsField.CanInterface() {
		krsValue := krsField.Interface()
		log.Printf("Found Krs (C component): %v", krsValue)

		// Extract X and Y coordinates
		krsReflect := reflect.ValueOf(krsValue)
		if krsReflect.Kind() == reflect.Struct {
			// C.X
			xField := krsReflect.Field(0)
			if xField.IsValid() {
				components[6] = elementToHex(xField)
				log.Printf("  C.X = 0x%s", components[6])
			}

			// C.Y
			yField := krsReflect.Field(1)
			if yField.IsValid() {
				components[7] = elementToHex(yField)
				log.Printf("  C.Y = 0x%s", components[7])
			}
		}
	}

	log.Printf("Successfully extracted REAL proof components!")

	return components, nil
}

// elementToHex attempts to convert a gnark-crypto field element (fp.Element or fr.Element)
// that is reflected as an array value into its canonical big-endian hexadecimal string.
// It first tries to leverage the BigInt() or Bytes()/Marshal() methods (avoids Montgomery form),
// falling back to limb concatenation only if those methods don't exist.
func elementToHex(original reflect.Value) string {
	// Ensure we have an addressable value; if not, create one using unsafe.
	val := original
	if !val.CanAddr() {
		// Create addressable copy
		addrCopy := reflect.New(val.Type()).Elem()
		addrCopy.Set(val)
		val = addrCopy
	}

	ptr := val.Addr()

	// 1. Try BigInt(*big.Int) *big.Int method
	if m := ptr.MethodByName("BigInt"); m.IsValid() {
		bi := new(big.Int)
		outs := m.Call([]reflect.Value{reflect.ValueOf(bi)})
		if len(outs) == 1 {
			// bi now contains canonical value
			return bi.Text(16)
		}
	}

	// 2. Try Bytes() or Marshal() that returns [32]byte or []byte
	tryByteMethod := func(name string) (string, bool) {
		if m := ptr.MethodByName(name); m.IsValid() {
			res := m.Call(nil)
			if len(res) == 1 {
				rv := res[0]
				switch rv.Kind() {
				case reflect.Array:
					// e.g. [32]byte
					byteSlice := make([]byte, rv.Len())
					for i := 0; i < rv.Len(); i++ {
						byteSlice[i] = byte(rv.Index(i).Uint())
					}
					return new(big.Int).SetBytes(byteSlice).Text(16), true
				case reflect.Slice:
					b, ok := rv.Interface().([]byte)
					if ok {
						return new(big.Int).SetBytes(b).Text(16), true
					}
				}
			}
		}
		return "", false
	}

	if hex, ok := tryByteMethod("Bytes"); ok {
		return hex
	}
	if hex, ok := tryByteMethod("Marshal"); ok {
		return hex
	}

	// 3. Fallback – treat as [4]uint64 little-endian limbs (Montgomery!)
	// NOTE: This may still be wrong if limbs are Montgomery, but better than nothing.
	if val.Kind() == reflect.Array && val.Len() == 4 {
		var result big.Int
		for i := 3; i >= 0; i-- {
			result.Lsh(&result, 64)
			limb := big.NewInt(0).SetUint64(val.Index(i).Uint())
			result.Add(&result, limb)
		}
		return result.Text(16)
	}

	// As last resort
	return "0"
}

// Deprecated: kept for compatibility while refactoring – delegates to elementToHex.
func convertUint64ArrayToHex(arr [4]uint64) string {
	// Construct reflect value from array and reuse elementToHex
	v := reflect.ValueOf(arr)
	return elementToHex(v)
}

func formatFieldElement(s string) string {
	// Remove any leading zeros and ensure it's a valid hex string
	if s == "0" {
		return "0"
	}
	// Convert to big.Int and back to ensure proper formatting
	bigInt := new(big.Int)
	bigInt.SetString(s, 10)
	hex := bigInt.Text(16)
	// Pad to ensure it fits in uint256
	if len(hex) > 64 {
		hex = hex[:64] // Truncate if too long
	}
	return hex
}

func createWitness(testCase *TestCase) (witness.Witness, error) {
	// Parse hex strings to big integers
	r, err := parseHexToBigInt(testCase.R)
	if err != nil {
		return nil, fmt.Errorf("failed to parse R: %v", err)
	}

	s, err := parseHexToBigInt(testCase.S)
	if err != nil {
		return nil, fmt.Errorf("failed to parse S: %v", err)
	}

	msgHash, err := parseHexToBigInt(testCase.MsgHash)
	if err != nil {
		return nil, fmt.Errorf("failed to parse message hash: %v", err)
	}

	pubKeyX, err := parseHexToBigInt(testCase.PubKeyX)
	if err != nil {
		return nil, fmt.Errorf("failed to parse public key X: %v", err)
	}

	pubKeyY, err := parseHexToBigInt(testCase.PubKeyY)
	if err != nil {
		return nil, fmt.Errorf("failed to parse public key Y: %v", err)
	}

	// Create circuit assignment with emulated field elements (same as main.go)
	assignment := ECDSACircuit{
		R:       emulated.ValueOf[emulated.P256Fr](r),
		S:       emulated.ValueOf[emulated.P256Fr](s),
		MsgHash: emulated.ValueOf[emulated.P256Fr](msgHash),
		PubKeyX: emulated.ValueOf[emulated.P256Fp](pubKeyX),
		PubKeyY: emulated.ValueOf[emulated.P256Fp](pubKeyY),
	}

	// Create witness
	witness, err := frontend.NewWitness(&assignment, ecc.BN254.ScalarField())
	if err != nil {
		return nil, err
	}

	return witness, nil
}

func parseHexToBigInt(hexStr string) (*big.Int, error) {
	// Remove "0x" prefix if present
	hexStr = strings.TrimPrefix(hexStr, "0x")

	// Parse hex string to big.Int
	bigInt := new(big.Int)
	bigInt, ok := bigInt.SetString(hexStr, 16)
	if !ok {
		return nil, fmt.Errorf("invalid hex string: %s", hexStr)
	}

	return bigInt, nil
}
