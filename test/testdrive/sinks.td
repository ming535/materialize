# Copyright Materialize, Inc. and contributors. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.



$ kafka-create-topic topic=test partitions=1
$ kafka-ingest topic=test format=bytes
jack,jill
goofus,gallant

> CREATE CONNECTION kafka_conn
  FOR KAFKA BROKER '${testdrive.kafka-addr}';

> CREATE CONNECTION IF NOT EXISTS csr_conn
  FOR CONFLUENT SCHEMA REGISTRY
  URL '${testdrive.schema-registry-url}';

> CREATE SOURCE src (a, b)
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-test-${testdrive.seed}')
  FORMAT CSV WITH 2 COLUMNS
  INCLUDE OFFSET

> CREATE SOURCE src_materialized (a, b)
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-test-${testdrive.seed}')
  FORMAT CSV WITH 2 COLUMNS
  INCLUDE OFFSET

> CREATE VIEW v1 AS
  SELECT a || b AS c FROM src

> CREATE VIEW v2 AS
  SELECT a || b AS c FROM src_materialized

> CREATE MATERIALIZED VIEW v3 AS
  SELECT a || b AS c FROM src

# We should refuse to create a sink with invalid WITH options

! CREATE SINK invalid_with_option FROM src
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk1-${testdrive.seed}')
  WITH (badoption=true)
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
contains:Expected one of SNAPSHOT

> SHOW SINKS
name
----

# # We should refuse to create a sink with an invalid schema registry URL.
#
# # Invalid in that the address is not well formed
# ! CREATE SINK bad_schema_registry FROM v3
#   INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk1-${testdrive.seed}')
#   FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.kafka-addr}'
# contains:cannot construct a CCSR client with a cannot-be-a-base URL
#
# # Invalid in that the address points to an invalid host
# ! CREATE SINK bad_schema_registry FROM v3
#   INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk1-${testdrive.seed}')
#   FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY 'http://no-such-host'
# contains:unable to publish value schema to registry in kafka sink
#
# # Invalid in that the address is not for a schema registry
# ! CREATE SINK bad_schema_registry FROM v3
#   INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk1-${testdrive.seed}')
#   FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY 'http://materialized:6875'
# contains:unable to publish value schema to registry in kafka sink
#
# ! CREATE SINK bad_view FROM v1
#   INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk1-${testdrive.seed}')
#   FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
# contains:v1 is a view, which cannot be exported as a sink
#
# # ...Even if that view is based on a materialized source
# ! CREATE SINK bad_view2 FROM v2
#   INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk1-${testdrive.seed}')
#   WITH (retention_ms=1000000)
#   FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
# contains:v2 is a view, which cannot be exported as a sink

> SHOW SINKS
name
----

# N.B. it is important to test sinks that depend on sources directly vs. sinks
# that depend on views, as the code paths are different.

> CREATE SINK snk1 FROM src
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk1-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

> CREATE SINK snk2 FROM src_materialized
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk2-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

> CREATE SINK snk3 FROM v3
  INTO KAFKA CONNECTION kafka_conn (RETENTION BYTES = 1000000000000, TOPIC 'testdrive-snk3-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

> SHOW SINKS
name
----
snk1
snk2
snk3

$ kafka-verify format=avro sink=materialize.public.snk1 sort-messages=true
{"before": null, "after": {"row":{"a": "goofus", "b": "gallant", "offset": 2}}}
{"before": null, "after": {"row":{"a": "jack", "b": "jill", "offset": 1}}}

$ kafka-verify format=avro sink=materialize.public.snk2 sort-messages=true
{"before": null, "after": {"row":{"a": "goofus", "b": "gallant", "offset": 2}}}
{"before": null, "after": {"row":{"a": "jack", "b": "jill", "offset": 1}}}

$ kafka-verify format=avro sink=materialize.public.snk3 sort-messages=true
{"before": null, "after": {"row":{"c": "goofusgallant"}}}
{"before": null, "after": {"row":{"c": "jackjill"}}}

# Test the case where we have non +/- 1 multiplicities

> CREATE MATERIALIZED VIEW v4 AS
  SELECT true AS c FROM src

> CREATE SINK snk4 FROM v4
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk4-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

$ kafka-verify format=avro sink=materialize.public.snk4
{"before": null, "after": {"row":{"c": true}}}
{"before": null, "after": {"row":{"c": true}}}

# Test WITH (SNAPSHOT).
#
# N.B. It's important that we've verified above that a sink exporting
# src_materialized has processed the row. This means the data has a definite
# timestamp.  Without that, WITH (SNAPSHOT = false) could correct either include or
# exclude the old rows.

> CREATE SINK snk5 FROM src_materialized
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk5-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
  WITH (SNAPSHOT = false)

> CREATE SINK snk6 FROM src_materialized
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk6-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
  WITH (SNAPSHOT = true)

$ kafka-ingest topic=test format=bytes
extra,row

$ kafka-verify format=avro sink=materialize.public.snk5
{"before": null, "after": {"row":{"a": "extra", "b": "row", "offset": 3}}}

$ kafka-verify format=avro sink=materialize.public.snk6 sort-messages=true
{"before": null, "after": {"row":{"a": "extra", "b": "row", "offset": 3}}}
{"before": null, "after": {"row":{"a": "goofus", "b": "gallant", "offset": 2}}}
{"before": null, "after": {"row":{"a": "jack", "b": "jill", "offset": 1}}}

# Test that we are correctly handling SNAPSHOT on views with empty upper
# frontier
> CREATE MATERIALIZED VIEW foo AS VALUES (1), (2), (3);

> CREATE SINK snk7 FROM foo
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk7-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
  WITH (SNAPSHOT = false)

> CREATE SINK snk8 FROM foo
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk8-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
  WITH (SNAPSHOT)

$ kafka-verify format=avro sink=materialize.public.snk8 sort-messages=true
{"before": null, "after": {"row":{"column1": 1}}}
{"before": null, "after": {"row":{"column1": 2}}}
{"before": null, "after": {"row":{"column1": 3}}}

> SHOW SINKS
name
----
snk1
snk2
snk3
snk4
snk5
snk6
snk7
snk8

# test explicit partition count
> CREATE SINK snk9 FROM foo
  INTO KAFKA CONNECTION kafka_conn (PARTITION COUNT=1, TOPIC 'testdrive-snk9-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

# test explicit replication factor
> CREATE SINK snk10 FROM foo
  INTO KAFKA CONNECTION kafka_conn (REPLICATION FACTOR=1, TOPIC 'testdrive-snk10-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

# test explicit partition count and replication factor
> CREATE SINK snk11 FROM foo
  INTO KAFKA CONNECTION kafka_conn (PARTITION COUNT=1, REPLICATION FACTOR=1, TOPIC 'testdrive-snk11-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

# test broker defaulted partition count and replication factor
> CREATE SINK snk12 FROM foo
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-snk12-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

# test explicit request for broker defaulted partition count and replication factor
> CREATE SINK snk13 FROM foo
  INTO KAFKA CONNECTION kafka_conn (PARTITION COUNT=-1, REPLICATION FACTOR=-1, TOPIC 'testdrive-snk13-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
