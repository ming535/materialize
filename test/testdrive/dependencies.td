# Copyright Materialize, Inc. and contributors. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

# Test that a dependency chain with multiple links is properly maintained
# across creation and deletion.

$ set-regex match=cluster1|default replacement=<CLUSTER_NAME>

$ set schema={
    "name": "row",
    "type": "record",
    "fields": [
      {"name": "x", "type": "long"},
      {"name": "y", "type": "string"}
    ]
  }

> CREATE CONNECTION kafka_conn
  FOR KAFKA BROKER '${testdrive.kafka-addr}';

> CREATE CONNECTION IF NOT EXISTS csr_conn
  FOR CONFLUENT SCHEMA REGISTRY
  URL '${testdrive.schema-registry-url}';

> CREATE SOURCE s
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'

! CREATE SOURCE s
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-blah-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'
contains:catalog item 's' already exists

> CREATE SOURCE IF NOT EXISTS s
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-blah-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'

> CREATE VIEW test1 AS SELECT 1;

> CREATE VIEW test2 AS SELECT * FROM test1;

> CREATE VIEW test3a AS SELECT * FROM test2;

> CREATE VIEW test3b AS SELECT * FROM test2;

! DROP VIEW test1;
contains:cannot drop materialize.public.test1: still depended upon by catalog item 'materialize.public.test2'

! DROP VIEW test2;
contains:cannot drop materialize.public.test2: still depended upon by catalog item 'materialize.public.test3a'

> DROP VIEW test3a;

! DROP VIEW test1;
contains:cannot drop materialize.public.test1: still depended upon by catalog item 'materialize.public.test2'

! DROP VIEW test2;
contains:cannot drop materialize.public.test2: still depended upon by catalog item 'materialize.public.test3b'

> DROP VIEW test3b;

! DROP VIEW test1;
contains:cannot drop materialize.public.test1: still depended upon by catalog item 'materialize.public.test2'

> DROP VIEW test2;

> DROP VIEW test1;

# Test that CASCADE causes all dependent views to be dropped along with the
# named view.

> CREATE VIEW test1 AS SELECT 1;

> CREATE VIEW test2 AS SELECT * FROM test1;

> DROP VIEW test1 CASCADE;

# TODO(benesch): when we have a system stream that has the names of all
# available views, we can verify there that views are actually dropped,
# rather than verifying the drop by checking whether DROP VIEW fails.

! DROP VIEW test1;
contains:unknown catalog item 'test1'

! DROP VIEW test2;
contains:unknown catalog item 'test2'

# Test that DROP VIEW IF EXISTS succeeds even if the view does not exist.

> DROP VIEW IF EXISTS test1;

# Test that CASCADE causes all dependent views to be dropped along with the
# named source.

> CREATE VIEW test4 as SELECT * FROM s;

> DROP SOURCE s CASCADE;

! DROP VIEW test4;
contains:unknown catalog item 'test4'

> CREATE SOURCE s
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'

> CREATE SINK s1 FROM s
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-v-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

! CREATE SINK s1 FROM s
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-v-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn
contains:catalog item 's1' already exists

> CREATE SINK IF NOT EXISTS s1 FROM s
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-v2-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

> CREATE SINK s2 FROM s
  INTO KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-v3-${testdrive.seed}')
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY CONNECTION csr_conn

# Test that sinks cannot be depended upon.
! CREATE VIEW v2 AS SELECT * FROM s1;
contains:catalog item 'materialize.public.s1' is a sink and so cannot be depended upon

> CREATE VIEW v2 AS SELECT X from s;

> CREATE VIEW v2a AS SELECT X+1 as X from v2;

> CREATE INDEX i1 ON v2(x);

# Test that indexes cannot be depended upon

! CREATE VIEW v3 as SELECT * FROM i1;
contains:catalog item 'materialize.public.i1' is an index and so cannot be depended upon

> CREATE INDEX i2 ON v2a(x*2);

> SHOW INDEXES FROM v2a;
cluster        on_name   key_name         seq_in_index column_name expression  nullable
---------------------------------------------------------------------------------------
<CLUSTER_NAME> v2a       i2               1            <null>      "x * 2"     false

> SHOW INDEXES FROM v2;
cluster        on_name  key_name        seq_in_index column_name expression nullable
------------------------------------------------------------------------------------
<CLUSTER_NAME> v2       i1              1            x           <null>     false

# Test that dependent indexes do not prevent view deletion when restrict is specified
# but do not cause deletion of dependent views
> DROP VIEW v2a;

! DROP VIEW v2a;
contains:unknown catalog item 'v2a'

> SHOW INDEXES FROM v2;
cluster on_name  key_name        seq_in_index   column_name expression nullable
-----------------------------------------------------------------------------------
<CLUSTER_NAME> v2       i1              1              x           <null>     false

! DROP INDEX i2;
contains:unknown catalog item 'i2'

> CREATE VIEW v4 AS SELECT x, y from s;

> CREATE VIEW v4a AS SELECT y from v4;

> CREATE INDEX i3 ON v4a(y);

> SHOW INDEXES FROM v4a;
cluster on_name  key_name         seq_in_index   column_name expression nullable
------------------------------------------------------------------------------------
<CLUSTER_NAME> v4a      i3               1              y           <null>     false

> CREATE INDEX i4 ON v4(x);

> SHOW INDEXES FROM v4;
cluster on_name  key_name        seq_in_index  column_name expression nullable
----------------------------------------------------------------------------------
<CLUSTER_NAME> v4       i4              1             x           <null>     false

# Test cascade deletes associated indexes as well
> DROP VIEW v4a CASCADE;

! DROP VIEW v4a;
contains:unknown catalog item 'v4a'

! DROP INDEX i3;
contains:unknown catalog item 'i3'

> SHOW INDEXES FROM v4;
cluster on_name  key_name        seq_in_index  column_name expression nullable
----------------------------------------------------------------------------------
<CLUSTER_NAME> v4       i4              1             x           <null>     false

> CREATE VIEW v5 AS SELECT substr(y, 3, 2) as substr from v4;

> CREATE INDEX i5 ON v5(substr);

> SHOW INDEXES FROM v5;
cluster on_name   key_name        seq_in_index  column_name expression nullable
----------------------------------------------------------------------------------
<CLUSTER_NAME> v5        i5              1             substr      <null>     true

> CREATE VIEW multicol AS SELECT 'a' AS a, 'b' AS b, 'c' AS c, 'd' AS d
> CREATE INDEX i6 ON multicol (2, a, 4)
> SHOW INDEXES FROM multicol
cluster on_name   key_name  seq_in_index column_name  expression   nullable
-------------------------------------------------------------------------------
<CLUSTER_NAME> multicol  i6        1            b            <null>       false
<CLUSTER_NAME> multicol  i6        2            a            <null>       false
<CLUSTER_NAME> multicol  i6        3            d            <null>       false

> SHOW INDEXES FROM multicol WHERE column_name = 'a'
cluster on_name   key_name  seq_in_index column_name  expression   nullable
-------------------------------------------------------------------------------
<CLUSTER_NAME> multicol  i6        2            a            <null>       false

# Test cascade deletes all indexes associated with cascaded views
> DROP VIEW v4 CASCADE;

! DROP VIEW v4;
contains:unknown catalog item 'v4'

! DROP INDEX i5;
contains:unknown catalog item 'i5'

! DROP VIEW v5;
contains:unknown catalog item 'v5'

! DROP INDEX i4;
contains:unknown catalog item 'i4'

# Test that dropping indexes even with cascade does not cause the underlying view to be dropped

> DROP INDEX i1 CASCADE;

> DROP VIEW v2;

# Materialized source tests

> CREATE SOURCE s3
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'

# Test that dependent indexes do not prevent source deletion when restrict is specified
> CREATE INDEX j1 on s3(ascii(y))

> SHOW INDEXES FROM s3;
cluster on_name  key_name        seq_in_index  column_name expression             nullable
----------------------------------------------------------------------------------------------
<CLUSTER_NAME> s3       j1              1             <null>      "pg_catalog.ascii(y)"  false

> DROP SOURCE s3;

! DROP SOURCE s3;
contains:unknown catalog item 's3'

! DROP INDEX j1;
contains:unknown catalog item 'j1'

# Test cascade deletes all indexes associated with cascaded sources and views

> CREATE SOURCE s4
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'

> CREATE INDEX j2 on s4(x+2);

> CREATE VIEW w as SELECT y, x + 2 as z from s4;

> CREATE INDEX j3 on w(z);

> SHOW INDEXES FROM s4;
cluster on_name  key_name        seq_in_index   column_name expression  nullable
------------------------------------------------------------------------------------
<CLUSTER_NAME> s4       j2              1               <null>      "x + 2"    false

> SHOW INDEXES FROM w;
cluster on_name  key_name   seq_in_index  column_name expression nullable
-----------------------------------------------------------------------------
<CLUSTER_NAME> w        j3         1             z           <null>     false

> DROP SOURCE s4 CASCADE;

! DROP VIEW w;
contains:unknown catalog item 'w'

! DROP INDEX j3;
contains:unknown catalog item 'j3'

! DROP SOURCE s4;
contains:unknown catalog item 's4'

! DROP INDEX j2;
contains:unknown catalog item 'j2'

# Test that dropping indexes even with cascade does not cause the underlying source to be dropped

> CREATE SOURCE s5
  FROM KAFKA CONNECTION kafka_conn (TOPIC 'testdrive-data-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'

> CREATE DEFAULT INDEX ON s5;

> DROP INDEX s5_primary_idx CASCADE;

> DROP SOURCE s5;

# https://github.com/MaterializeInc/materialize/issues/5577
> CREATE TYPE int4_list AS LIST (element_type=int4)

> CREATE VIEW v1 AS SELECT CAST('{2}' AS int4_list)

! DROP TYPE int4_list
contains:cannot drop materialize.public.int4_list: still depended upon by catalog item 'materialize.public.v1'

> DROP VIEW v1

> CREATE TABLE t1 (custom int4_list)

! DROP TYPE int4_list
contains:cannot drop materialize.public.int4_list: still depended upon by catalog item 'materialize.public.t1'

> DROP TABLE t1

> SHOW TABLES

> CREATE VIEW v1 AS SELECT * FROM ( SELECT CAST('{2}' AS int4_list) )

! DROP TYPE int4_list
contains:cannot drop materialize.public.int4_list: still depended upon by catalog item 'materialize.public.v1'

> DROP VIEW v1

> CREATE VIEW v1 AS SELECT CAST(CAST('{2}' AS int4_list) AS text)

! DROP TYPE int4_list
contains:cannot drop materialize.public.int4_list: still depended upon by catalog item 'materialize.public.v1'

> DROP VIEW v1

> CREATE VIEW v1 AS VALUES (CAST('{2}' AS int4_list))

! DROP TYPE int4_list
contains:cannot drop materialize.public.int4_list: still depended upon by catalog item 'materialize.public.v1'

> DROP VIEW v1

> CREATE VIEW v1 AS SELECT MIN(CAST(CAST('{1}' AS int4_list) AS string))

! DROP TYPE int4_list
contains:cannot drop materialize.public.int4_list: still depended upon by catalog item 'materialize.public.v1'

> DROP VIEW v1

> CREATE TABLE t1 (f1 TEXT DEFAULT CAST ('{}' AS int4_list))

> DROP TABLE t1

> CREATE TEMPORARY TABLE t1 (f1 int4_list)

! DROP TYPE int4_list
contains:cannot drop materialize.public.int4_list: still depended upon by catalog item 'mz_temp.t1'

> DROP TABLE t1

> CREATE TABLE t1 (f1 TEXT)

> CREATE INDEX i1 ON t1 (CAST(f1 AS int4_list))

! DROP TYPE int4_list
contains:cannot drop materialize.public.int4_list: still depended upon by catalog item 'materialize.public.i1'

> DROP TABLE t1

> CREATE TYPE int4_list_list AS LIST (element_type=int4_list)

! DROP TYPE int4_list
contains:cannot drop materialize.public.int4_list: still depended upon by catalog item 'materialize.public.int4_list_list'

> DROP TYPE int4_list_list

#cleanup
> DROP SINK s1;

> DROP SINK s2;

> DROP SOURCE s;

# Test CREATE OR REPLACE view.

> CREATE OR REPLACE VIEW v3 AS SELECT 1
> SELECT * FROM v3
1

> CREATE OR REPLACE VIEW v3 AS SELECT 2
> SELECT * FROM v3
2

> CREATE OR REPLACE VIEW v4 AS SELECT * FROM v3
> SELECT * FROM v4
2

! CREATE OR REPLACE VIEW v3 AS SELECT 3
contains:cannot drop materialize.public.v3: still depended upon by catalog item 'materialize.public.v4'

> CREATE OR REPLACE VIEW v4 AS SELECT 3
> SELECT * FROM v4
3

> SELECT * FROM v3
2

> CREATE OR REPLACE VIEW v3 AS SELECT 4
> SELECT * FROM v3
4

# Test CREATE VIEW IF NOT EXISTS

> CREATE VIEW test1 AS SELECT 1;

> CREATE VIEW test2 AS SELECT * FROM test1;

! DROP VIEW test1;
contains:cannot drop materialize.public.test1: still depended upon by catalog item 'materialize.public.test2'

# Succeeds even though it's dependent on.
> CREATE VIEW IF NOT EXISTS test1 AS SELECT 2 as b;

> SELECT * FROM test1;
1

> DROP VIEW test2;

> DROP VIEW test1;
