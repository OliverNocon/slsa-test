package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/secure-systems-lab/go-securesystemslib/dsse"
	// intoto "github.com/in-toto/in-toto-golang/in_toto"
)

func main() {
	filename := "./samples/generic.intoto.jsonl"
	f, err := os.ReadFile(filename)
	if err != nil {
		log.Fatal("failed to read file", err)
	}

	var envelope dsse.Envelope

	if err := json.Unmarshal(f, &envelope); err != nil {
		log.Fatal("failed to unmarshal ", filename, ": ", err)
	}

	contentBytes, err := envelope.DecodeB64Payload()
	if err != nil {
		log.Fatal("failed to decode payload", err)
	}

	var payload map[string]any
	if err := json.Unmarshal(contentBytes, &payload); err != nil {
		log.Fatal("failed to decode payload", err)
	}

	out, _ := json.MarshalIndent(payload, "", "    ")
	fmt.Print(string(out))
}
