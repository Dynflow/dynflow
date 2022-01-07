# expand

For a long time, Dynflow's database schema remained stable. To optimize Dynflow
a bit, we started changing it. One of the changes was changing how we encode
flows, resulting in flows taking roughly 10x less space.

The other change is not merged yet, but has potentionally bigger impact. We
store certain columns as JSON objects. The upcoming change uses msgpack instead
of JSON, resulting in faster encoding and decoding times and smaller storage
footprint when encoded. The drawback is it is a binary format, so if someone
dumps the tables from DB as CSV, they won't be human readable.

This tool processes CSV DB dumps and decodes msgpack to json.

## Usage

```shell
# cat dynflow_execution_plans.csv
2065cc55-6b03-44b7-947a-e999dcb9057f,,stopped,error,,2021-04-16 09:50:33.826,0,0,,Dynflow::ExecutionPlan,1,\x91a143,\x91a153,\x9283a474696d65ce60795de9a46e616d65a564656c6179a8776f726c645f6964d92435626536643435662d363732342d343666652d393035662d34363565316466346561306183a474696d65ce60795de9a46e616d65a774696d656f7574a8776f726c645f6964d92435626536643435662d363732342d343666652d393035662d343635653164663465613061,\x9101
6667374a-beab-4b0b-80c8-3d0392cdde40,,scheduled,pending,,,0,,,Dynflow::ExecutionPlan,1,\x91a143,\x91a153,\x9183a474696d65ce60795de9a46e616d65a564656c6179a8776f726c645f6964d92435626536643435662d363732342d343666652d393035662d343635653164663465613061,\x9101

# expand < dynflow_execution_plans.csv
2065cc55-6b03-44b7-947a-e999dcb9057f,,stopped,error,,2021-04-16 09:50:33.826,0,0,,Dynflow::ExecutionPlan,1,"[""C""]","[""S""]","[{""name"":""delay"",""time"":1618566633,""world_id"":""5be6d45f-6724-46fe-905f-465e1df4ea0a""},{""name"":""timeout"",""time"":1618566633,""world_id"":""5be6d45f-6724-46fe-905f-465e1df4ea0a""}]",[1]
6667374a-beab-4b0b-80c8-3d0392cdde40,,scheduled,pending,,,0,,,Dynflow::ExecutionPlan,1,"[""C""]","[""S""]","[{""name"":""delay"",""time"":1618566633,""world_id"":""5be6d45f-6724-46fe-905f-465e1df4ea0a""}]",[1]
```
