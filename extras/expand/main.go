package main

import (
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"github.com/vmihailenco/msgpack/v5"
	"io"
	"os"
)

func main() {
	reader := csv.NewReader(os.Stdin)
	defer os.Stdin.Close()

	writer := csv.NewWriter(os.Stdout)
	defer os.Stdout.Close()
	defer writer.Flush()

	for {
		record, err := reader.Read()
		if err == io.EOF {
			break
		}

		writer.Write(processRow(record))
	}
}

func processRow(record []string) []string {
	for i, r := range record {
		if isHexEncoded(r) {
			record[i] = reencodeField(r)
		}
	}

	return record
}

func isHexEncoded(field string) bool {
	return len(field) >= 2 && field[0:2] == "\\x"
}

func reencodeField(field string) string {
	decoded_bytes, err := hex.DecodeString(field[2:])
	if err != nil {
		return field
	}

	var intermediate interface{}
	err = msgpack.Unmarshal(decoded_bytes, &intermediate)
	if err != nil {
		return field
	}

	return encode(intermediate)
}

func encode(data interface{}) string {
	result, err := json.Marshal(data)
	if err != nil {
		panic(err)
	}

	return string(result)
}
