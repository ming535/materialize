// Copyright Materialize, Inc. and contributors. All rights reserved.
//
// Use of this software is governed by the Business Source License
// included in the LICENSE file.
//
// As of the Change Date specified in that file, in accordance with
// the Business Source License, use of this software will be governed
// by the Apache License, Version 2.0.

use std::env;

fn main() {
    env::set_var("PROTOC", protobuf_src::protoc());

    tonic_build::configure()
        // Enabling `emit_rerun_if_changed` will rerun the build script when
        // anything in the include directory (..) changes. This causes quite a
        // bit of spurious recompilation, so we disable it. The default behavior
        // is to re-run if any file in the crate changes; that's still a bit too
        // broad, but it's better.
        .emit_rerun_if_changed(false)
        .extern_path(".mz_ccsr.config", "::mz_ccsr")
        .extern_path(".mz_expr.id", "::mz_expr")
        .extern_path(".mz_expr.linear", "::mz_expr")
        .extern_path(".mz_expr.relation", "::mz_expr")
        .extern_path(".mz_expr.scalar", "::mz_expr")
        .extern_path(".mz_kafka_util.addr", "::mz_kafka_util")
        .extern_path(".mz_proto", "::mz_proto")
        .extern_path(".mz_postgres_util.desc", "::mz_postgres_util::desc")
        .extern_path(".mz_repr.adt.regex", "::mz_repr::adt::regex")
        .extern_path(".mz_repr.antichain", "::mz_repr::antichain")
        .extern_path(".mz_repr.chrono", "::mz_repr::chrono")
        .extern_path(".mz_repr.global_id", "::mz_repr::global_id")
        .extern_path(".mz_repr.relation_and_scalar", "::mz_repr")
        .extern_path(".mz_repr.row", "::mz_repr")
        .extern_path(".mz_repr.url", "::mz_repr::url")
        .extern_path(".mz_storage", "::mz_storage")
        .compile(
            &[
                "compute-client/src/command.proto",
                "compute-client/src/logging.proto",
                "compute-client/src/plan.proto",
                "compute-client/src/plan/join.proto",
                "compute-client/src/plan/reduce.proto",
                "compute-client/src/plan/threshold.proto",
                "compute-client/src/plan/top_k.proto",
                "compute-client/src/response.proto",
                "compute-client/src/service.proto",
                "compute-client/src/sinks.proto",
            ],
            &[".."],
        )
        .unwrap();
}
