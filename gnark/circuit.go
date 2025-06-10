package main

import (
	"github.com/consensys/gnark/frontend"
	"github.com/consensys/gnark/std/algebra/emulated/sw_emulated"
	"github.com/consensys/gnark/std/math/emulated"
	"github.com/consensys/gnark/std/signature/ecdsa"
)

// ECDSACircuit defines the circuit for ECDSA P-256 signature verification
type ECDSACircuit struct {
	// Signature components (r, s) as emulated field elements
	R emulated.Element[emulated.P256Fr] `gnark:",secret"`
	S emulated.Element[emulated.P256Fr] `gnark:",secret"`

	// Message hash as emulated field element
	MsgHash emulated.Element[emulated.P256Fr] `gnark:",secret"`

	// Public key coordinates (x, y) as emulated field elements
	PubKeyX emulated.Element[emulated.P256Fp] `gnark:",public"`
	PubKeyY emulated.Element[emulated.P256Fp] `gnark:",public"`
}

// Define declares the circuit constraints for ECDSA signature verification
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
