# Copyright Materialize, Inc. and contributors. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

#
# Test persistent kafka topics in the context of exactly-once sinks
#

$ set keyschema={
    "type": "record",
    "name": "Key",
    "fields": [
        {"name": "f1", "type": "long"}
    ]
  }

$ set schema={
        "type" : "record",
        "name" : "test",
        "fields" : [
            {"name":"f2", "type":"long"}
        ]
    }

$ kafka-create-topic topic=exactly-once

$ kafka-ingest format=avro topic=exactly-once key-format=avro key-schema=${keyschema} schema=${schema} repeat=2
{"f1": ${kafka-ingest.iteration}} {"f2": ${kafka-ingest.iteration}}

> CREATE CONNECTION kafka_conn FOR KAFKA BROKER '${testdrive.kafka-addr}';

> CREATE SOURCE exactly_once
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-exactly-once-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
  ENVELOPE UPSERT

> CREATE CONNECTION IF NOT EXISTS csr_conn
  FOR CONFLUENT SCHEMA REGISTRY
  URL '${testdrive.schema-registry-url}';

> CREATE SINK exactly_once_sink FROM exactly_once
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-exactly-once-sink-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn;

$ kafka-ingest format=avro topic=exactly-once key-format=avro key-schema=${keyschema} schema=${schema} repeat=2 start-iteration=10
{"f1": ${kafka-ingest.iteration}} {"f2": ${kafka-ingest.iteration}}

> SELECT COUNT(*) FROM exactly_once;
4

$ kafka-ingest format=avro topic=exactly-once key-format=avro key-schema=${keyschema} schema=${schema} repeat=2 start-iteration=20
{"f1": ${kafka-ingest.iteration}} {"f2": ${kafka-ingest.iteration}}

$ kafka-ingest format=avro topic=exactly-once key-format=avro key-schema=${keyschema} schema=${schema} repeat=2 start-iteration=30
{"f1": ${kafka-ingest.iteration}} {"f2": ${kafka-ingest.iteration}}

# Make sure that we have produced stuff to the sink before we restart


$ kafka-verify format=avro sink=materialize.public.exactly_once_sink sort-messages=true
{"before":null,"after":{"row":{"f1":0,"f2":0}}}
{"before":null,"after":{"row":{"f1":1,"f2":1}}}
{"before":null,"after":{"row":{"f1":10,"f2":10}}}
{"before":null,"after":{"row":{"f1":11,"f2":11}}}
