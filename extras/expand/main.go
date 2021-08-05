package main

import (
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"github.com/vmihailenco/msgpack"
	"io"
	"os"
)

// dynflow_steps
// 0                   1  2         3    4     5          6        7         8              9             10              11    12    13           14       15
// execution_plan_uuid,id,action_id,data,state,started_at,ended_at,real_time,execution_time,progress_done,progress_weight,class,error,action_class,children,queue
//
// encoded columns are:
// 3 - data
// 12 - error
// 14 - children

// dynflow_actions
// 0                   1  2    3                        4                5     6     7      8            9           10
// execution_plan_uuid,id,data,caller_execution_plan_id,caller_action_id,class,input,output,plan_step_id,run_step_id,finalize_step_id
//
// encoded columns are:
// 2 - data
// 6 - input
// 7 - output

// dynflow_execution_plans
// Without msgpack
// 0    1    2     3      4          5        6         7              8     9     10       11            12                13                14
// uuid,data,state,result,started_at,ended_at,real_time,execution_time,label,class,run_flow,finalize_flow,execution_history,root_plan_step_id,step_ids

// With msgpack
// 0    1    2     3      4          5        6         7              8     9     10                11       12            13                14
// uuid,data,state,result,started_at,ended_at,real_time,execution_time,label,class,root_plan_step_id,run_flow,finalize_flow,execution_history,step_ids
//
// 1 - data
// 11 - run_flow
// 12 - finalize_flow
// 13 - execution_history
// 14 - step_ids

func main() {
	reader := csv.NewReader(os.Stdin)
	writer := csv.NewWriter(os.Stdout)
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
	// Execution plan exports have 15 fields, other exports have different counts
	if len(record) == 15 {
		record = expandExecutionPlan(record)
	}

	for i, r := range record {
		record[i] = reencodeField(r)
	}

	return record
}

func expandExecutionPlan(record []string) []string {
	var flow_columns [2]int

	// The step_ids field should be a safe indicator
	if isHexEncoded(record[14]) {
		flow_columns = [...]int{11, 12}
	} else {
		flow_columns = [...]int{10, 11}
	}

	for _, i := range flow_columns {
		record[i] = expandFlow(record[i])
	}
	return record
}

func isHexEncoded(field string) bool {
	return len(field) >= 2 && field[0:2] == "\\x"
}

func reencodeField(field string) string {
	decoded, err := decode(field)
	if err != nil {
		return field
	}

	return encode(decoded)
}

func decode(field string) (interface{}, error) {
	var intermediate interface{}
	bytes := []byte(field)

	if isHexEncoded(field) {
		decoded_bytes, err := hex.DecodeString(field[2:])
		if err != nil {
			return "", err
		}

		err = msgpack.Unmarshal(decoded_bytes, &intermediate)
		if err != nil {
			return "", err
		}

		return intermediate, nil
	}

	err := json.Unmarshal(bytes, &intermediate)
	if err != nil {
		return "", err
	}

	return intermediate, nil
}

func encode(data interface{}) string {
	result, err := json.Marshal(data)
	if err != nil {
		panic(err)
	}

	return string(result)
}

func expandFlow(field string) string {
	intermediate, err := decode(field)
	if err != nil {
		return field
	}

	var result map[string]interface{}
	switch intermediate.(type) {
	// old style hash
	case map[string]interface{}:
		result = intermediate.(map[string]interface{})
	// newer compact S-expression like representation
	case []interface{}, float64:
		result = expandCompactFlow(intermediate)
	}

	return encode(result)
}

func expandCompactFlow(flow interface{}) map[string]interface{} {
	result := make(map[string]interface{})
	switch flow.(type) {
	case []interface{}:
		switch flow.([]interface{})[0] {
		case "S":
			result["class"] = "Dynflow::Flows::Sequence"
		case "C":
			result["class"] = "Dynflow::Flows::Concurrence"
		default:
			panic("Unknown flow type")
		}
		var subflows []interface{}
		for subflow := range flow.([]interface{})[1:] {
			subflows = append(subflows, expandCompactFlow(subflow))
		}
		result["flows"] = subflows
	case float64, int:
		result["class"] = "Dynflow::Flows::Atom"
		result["step_id"] = flow
	default:
		panic("Unknown flow type")
	}
	return result
}
