package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"os"
	"reflect"
	"strings"
	"text/template"

	"github.com/consensys/gnark-crypto/ecc"
	"github.com/consensys/gnark-crypto/ecc/bn254/fr"
	"github.com/consensys/gnark/backend/groth16"
	"github.com/consensys/gnark/backend/witness"
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/std/algebra/emulated/sw_emulated"
	"github.com/consensys/gnark/std/math/emulated"
	"github.com/consensys/gnark/std/signature/ecdsa"
)

const numPublicInputs = 4

type TestCase struct {
	R       string `json:"r"`
	S       string `json:"s"`
	MsgHash string `json:"msghash"`
	PubKeyX string `json:"pubkey_x"`
	PubKeyY string `json:"pubkey_y"`
}

type ECDSACircuit struct {
	R       emulated.Element[emulated.P256Fr] `gnark:",secret"`
	S       emulated.Element[emulated.P256Fr] `gnark:",secret"`
	MsgHash emulated.Element[emulated.P256Fr] `gnark:",public"`
	PubKeyX emulated.Element[emulated.P256Fp] `gnark:",secret"`
	PubKeyY emulated.Element[emulated.P256Fp] `gnark:",secret"`
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
	testCaseData, err := os.ReadFile(testCaseFile)
	if err != nil {
		log.Fatal("Failed to read test case file:", err)
	}

	var testCase TestCase
	err = json.Unmarshal(testCaseData, &testCase)
	if err != nil {
		log.Fatal("Failed to parse test case:", err)
	}

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

	if len(publicValues) != numPublicInputs {
		log.Printf("WARNING: Expected %d public inputs but got %d", numPublicInputs, len(publicValues))
	}

	components, err := extractProofComponents(proof)
	if err != nil {
		log.Fatal("Failed to extract proof components:", err)
	}

	// Extract commitment and commitmentPok values.
	commitments, commitmentPokVals, err := extractCommitmentData(proof)
	if err != nil {
		log.Fatal("Failed to extract commitment data:", err)
	}

	// Prepare data for the template
	templateData := struct {
		TestCaseNum   string
		Proof         [8]string
		Commitments   [2]string
		CommitmentPok [2]string
		PublicInputs  []string
	}{
		TestCaseNum:   testCaseNum,
		Commitments:   commitments,
		CommitmentPok: commitmentPokVals,
	}

	// The order for B G2 point is [X.A1, X.A0, Y.A1, Y.A0] for Solidity
	templateData.Proof = [8]string{
		components[0], // A.X
		components[1], // A.Y
		components[3], // B.X.A1 (imaginary)
		components[2], // B.X.A0 (real)
		components[5], // B.Y.A1 (imaginary)
		components[4], // B.Y.A0 (real)
		components[6], // C.X
		components[7], // C.Y
	}

	for i := 0; i < numPublicInputs; i++ {
		hexVal := "0"
		if i < len(publicValues) {
			hexVal = formatFieldElement(publicValues[i].String())
		}
		templateData.PublicInputs = append(templateData.PublicInputs, hexVal)
	}

	// Define the Go template for the Solidity test file
	const solTemplate = `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/GasTest.sol";

contract GasTestTest is Test {
    GasTest gasTest;
    
    function setUp() public {
        gasTest = new GasTest();
    }
    
    function testVerifyProof{{.TestCaseNum}}() public {
        uint256[8] memory proofArr;
        proofArr[0] = 0x{{index .Proof 0}}; // A.X
        proofArr[1] = 0x{{index .Proof 1}}; // A.Y
        proofArr[2] = 0x{{index .Proof 2}}; // B.X.A1
        proofArr[3] = 0x{{index .Proof 3}}; // B.X.A0
        proofArr[4] = 0x{{index .Proof 4}}; // B.Y.A1
        proofArr[5] = 0x{{index .Proof 5}}; // B.Y.A0
        proofArr[6] = 0x{{index .Proof 6}}; // C.X
        proofArr[7] = 0x{{index .Proof 7}}; // C.Y

        uint256[2] memory commitmentsArr;
        commitmentsArr[0] = 0x{{index .Commitments 0}};
        commitmentsArr[1] = 0x{{index .Commitments 1}};

        uint256[2] memory commitmentPokArr;
        commitmentPokArr[0] = 0x{{index .CommitmentPok 0}};
        commitmentPokArr[1] = 0x{{index .CommitmentPok 1}};

        uint256[4] memory inputArr;
{{range $i, $val := .PublicInputs}}
        inputArr[{{$i}}] = 0x{{$val}};
{{end}}
        
        gasTest.verifyProof(proofArr, commitmentsArr, commitmentPokArr, inputArr);
    }
}
`

	// Parse and execute the template
	tmpl, err := template.New("solidityTest").Parse(solTemplate)
	if err != nil {
		log.Fatalf("failed to parse template: %v", err)
	}

	var buf bytes.Buffer
	err = tmpl.Execute(&buf, templateData)
	if err != nil {
		log.Fatalf("failed to execute template: %v", err)
	}

	// Print the result to stdout so it can be redirected by the shell script
	fmt.Println(buf.String())
}

func extractCommitmentData(proof groth16.Proof) (commitments [2]string, commitmentPokVals [2]string, err error) {
	// Initialize with zero so that fallback is still valid if missing
	commitments = [2]string{"0", "0"}
	commitmentPokVals = [2]string{"0", "0"}

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

	// CommitmentPok field is a G1Affine point
	pokField := proofVal.FieldByName("CommitmentPok")
	if pokField.IsValid() {
		if pokField.Kind() == reflect.Struct && pokField.NumField() >= 2 {
			xField := pokField.Field(0)
			commitmentPokVals[0] = elementToHex(xField)
			yField := pokField.Field(1)
			commitmentPokVals[1] = elementToHex(yField)
		}
	}

	return
}

func extractProofComponents(proof groth16.Proof) ([8]string, error) {
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

		// Extract X and Y coordinates from the G1Affine point
		arReflect := reflect.ValueOf(arValue)
		if arReflect.Kind() == reflect.Struct {
			// Try to get X coordinate (index 0)
			xField := arReflect.Field(0)
			if xField.IsValid() {
				components[0] = elementToHex(xField)
			}

			// Try to get Y coordinate (index 1)
			yField := arReflect.Field(1)
			if yField.IsValid() {
				components[1] = elementToHex(yField)
			}
		}
	}

	// Extract Bs (B point) - G2Affine
	bsField := proofValue.FieldByName("Bs")
	if bsField.IsValid() && bsField.CanInterface() {
		bsValue := bsField.Interface()

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
					}
					// X.A1
					a1Field := xStruct.Field(1)
					if a1Field.IsValid() {
						components[3] = elementToHex(a1Field)
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
					}
					// Y.A1
					a1Field := yStruct.Field(1)
					if a1Field.IsValid() {
						components[5] = elementToHex(a1Field)
					}
				}
			}
		}
	}

	// Extract Krs (C point) - G1Affine
	krsField := proofValue.FieldByName("Krs")
	if krsField.IsValid() && krsField.CanInterface() {
		krsValue := krsField.Interface()

		// Extract X and Y coordinates
		krsReflect := reflect.ValueOf(krsValue)
		if krsReflect.Kind() == reflect.Struct {
			// C.X
			xField := krsReflect.Field(0)
			if xField.IsValid() {
				components[6] = elementToHex(xField)
			}

			// C.Y
			yField := krsReflect.Field(1)
			if yField.IsValid() {
				components[7] = elementToHex(yField)
			}
		}
	}

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
