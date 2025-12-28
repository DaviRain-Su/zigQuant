const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // Add zigeth dependency for Ethereum crypto functions
    const zigeth = b.dependency("zigeth", .{
        .target = target,
        .optimize = optimize,
    });

    // Add WebSocket dependency for real-time market data
    const websocket = b.dependency("websocket", .{
        .target = target,
        .optimize = optimize,
    });

    // Add zig-clap dependency for CLI argument parsing
    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    // Add libxev dependency for high-performance event loop
    const libxev = b.dependency("libxev", .{
        .target = target,
        .optimize = optimize,
    });

    // Add zig-ai-sdk dependency for AI/LLM integration
    const ai_sdk = b.dependency("zig-ai-sdk", .{
        .target = target,
        .optimize = optimize,
    });

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    const mod = b.addModule("zigQuant", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
        .imports = &.{
            .{ .name = "zigeth", .module = zigeth.module("zigeth") },
            .{ .name = "websocket", .module = websocket.module("websocket") },
            .{ .name = "xev", .module = libxev.module("xev") },
            .{ .name = "ai", .module = ai_sdk.module("ai") },
            .{ .name = "openai", .module = ai_sdk.module("openai") },
            .{ .name = "anthropic", .module = ai_sdk.module("anthropic") },
            .{ .name = "provider", .module = ai_sdk.module("provider") },
        },
    });

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "zigQuant",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "zigQuant" is the name you will use in your source code to
                // import this module (e.g. `@import("zigQuant")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "zigQuant", .module = mod },
                .{ .name = "clap", .module = clap.module("clap") },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Integration tests - requires network access
    const integration_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/hyperliquid_integration_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });

    const run_integration_test = b.addRunArtifact(integration_test);
    const integration_step = b.step("test-integration", "Run integration tests (requires network and API credentials)");
    integration_step.dependOn(&run_integration_test.step);

    // WebSocket Orderbook integration test - tests orderbook updates via WebSocket
    const ws_orderbook_test = b.addExecutable(.{
        .name = "websocket-orderbook-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/websocket_orderbook_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });

    const run_ws_orderbook_test = b.addRunArtifact(ws_orderbook_test);
    const ws_orderbook_step = b.step("test-ws-orderbook", "Run WebSocket Orderbook integration test (requires network)");
    ws_orderbook_step.dependOn(&run_ws_orderbook_test.step);

    // Order Lifecycle integration test - tests complete order lifecycle (submit, query, cancel)
    const order_lifecycle_test = b.addExecutable(.{
        .name = "order-lifecycle-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/order_lifecycle_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });

    const run_order_lifecycle_test = b.addRunArtifact(order_lifecycle_test);
    const order_lifecycle_step = b.step("test-order-lifecycle", "Run Order Lifecycle integration test (requires network and testnet account)");
    order_lifecycle_step.dependOn(&run_order_lifecycle_test.step);

    // Position Management integration test - tests position open/close lifecycle
    const position_management_test = b.addExecutable(.{
        .name = "position-management-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/position_management_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });

    const run_position_management_test = b.addRunArtifact(position_management_test);
    const position_management_step = b.step("test-position-management", "Run Position Management integration test (requires network and testnet account)");
    position_management_step.dependOn(&run_position_management_test.step);

    // WebSocket Events integration test - tests WebSocket event callbacks
    const websocket_events_test = b.addExecutable(.{
        .name = "websocket-events-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/websocket_events_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });

    const run_websocket_events_test = b.addRunArtifact(websocket_events_test);
    const websocket_events_step = b.step("test-websocket-events", "Run WebSocket Events integration test (requires network and testnet account)");
    websocket_events_step.dependOn(&run_websocket_events_test.step);

    // Strategy Full integration test - tests complete strategy system
    const strategy_full_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/strategy_full_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });

    const run_strategy_full_test = b.addRunArtifact(strategy_full_test);
    const strategy_full_step = b.step("test-strategy-full", "Run full strategy system integration test");
    strategy_full_step.dependOn(&run_strategy_full_test.step);

    // v0.5.0 Integration test - tests event-driven architecture components
    const v050_integration_test = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/v050_integration_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });

    const run_v050_integration_test = b.addRunArtifact(v050_integration_test);
    const v050_integration_step = b.step("test-v050", "Run v0.5.0 event-driven architecture integration test");
    v050_integration_step.dependOn(&run_v050_integration_test.step);

    // Verify Keys tool - helps verify private key and wallet address match
    const verify_keys = b.addExecutable(.{
        .name = "verify-keys",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/verify_keys.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigeth", .module = zigeth.module("zigeth") },
            },
        }),
    });

    const run_verify_keys = b.addRunArtifact(verify_keys);
    const verify_keys_step = b.step("verify-keys", "Verify that private key and wallet address in test config match");
    verify_keys_step.dependOn(&run_verify_keys.step);

    // ========================================================================
    // Examples
    // ========================================================================

    // Example 1: Core Basics
    const example_core = b.addExecutable(.{
        .name = "example-core",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/01_core_basics.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_core);
    const run_example_core = b.addRunArtifact(example_core);
    const example_core_step = b.step("run-example-core", "Run core modules example");
    example_core_step.dependOn(&run_example_core.step);

    // Example 2: WebSocket Streaming
    const example_websocket = b.addExecutable(.{
        .name = "example-websocket",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/02_websocket_stream.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_websocket);
    const run_example_websocket = b.addRunArtifact(example_websocket);
    const example_websocket_step = b.step("run-example-websocket", "Run WebSocket streaming example (requires network)");
    example_websocket_step.dependOn(&run_example_websocket.step);

    // Example 3: HTTP Market Data
    const example_http = b.addExecutable(.{
        .name = "example-http",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/03_http_market_data.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_http);
    const run_example_http = b.addRunArtifact(example_http);
    const example_http_step = b.step("run-example-http", "Run HTTP market data example (requires network)");
    example_http_step.dependOn(&run_example_http.step);

    // Example 4: Exchange Connector
    const example_connector = b.addExecutable(.{
        .name = "example-connector",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/04_exchange_connector.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_connector);
    const run_example_connector = b.addRunArtifact(example_connector);
    const example_connector_step = b.step("run-example-connector", "Run exchange connector example (requires network)");
    example_connector_step.dependOn(&run_example_connector.step);

    // Example 5: Colored Logging
    const example_colored_logging = b.addExecutable(.{
        .name = "example-colored-logging",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/05_colored_logging.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_colored_logging);
    const run_example_colored_logging = b.addRunArtifact(example_colored_logging);
    const example_colored_logging_step = b.step("run-example-colored-logging", "Run colored logging example");
    example_colored_logging_step.dependOn(&run_example_colored_logging.step);

    // Example 6: Strategy Backtest
    const example_backtest = b.addExecutable(.{
        .name = "example-backtest",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/06_strategy_backtest.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_backtest);
    const run_example_backtest = b.addRunArtifact(example_backtest);
    const example_backtest_step = b.step("run-example-backtest", "Run strategy backtest example");
    example_backtest_step.dependOn(&run_example_backtest.step);

    // Example 7: Strategy Optimize
    const example_optimize = b.addExecutable(.{
        .name = "example-optimize",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/07_strategy_optimize.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_optimize);
    const run_example_optimize = b.addRunArtifact(example_optimize);
    const example_optimize_step = b.step("run-example-optimize", "Run strategy optimization example");
    example_optimize_step.dependOn(&run_example_optimize.step);

    // Example 8: Custom Strategy
    const example_custom = b.addExecutable(.{
        .name = "example-custom",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/08_custom_strategy.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_custom);
    const run_example_custom = b.addRunArtifact(example_custom);
    const example_custom_step = b.step("run-example-custom", "Run custom strategy example");
    example_custom_step.dependOn(&run_example_custom.step);

    // Example 9: New Indicators (v0.4.0)
    const example_indicators = b.addExecutable(.{
        .name = "example-indicators",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/09_new_indicators.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_indicators);
    const run_example_indicators = b.addRunArtifact(example_indicators);
    const example_indicators_step = b.step("run-example-indicators", "Run new indicators example");
    example_indicators_step.dependOn(&run_example_indicators.step);

    // Example 10: Walk-Forward Analysis (v0.4.0)
    const example_walkforward = b.addExecutable(.{
        .name = "example-walkforward",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/10_walk_forward.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_walkforward);
    const run_example_walkforward = b.addRunArtifact(example_walkforward);
    const example_walkforward_step = b.step("run-example-walkforward", "Run Walk-Forward analysis example");
    example_walkforward_step.dependOn(&run_example_walkforward.step);

    // Example 11: Result Export (v0.4.0)
    const example_export = b.addExecutable(.{
        .name = "example-export",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/11_result_export.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_export);
    const run_example_export = b.addRunArtifact(example_export);
    const example_export_step = b.step("run-example-export", "Run result export example");
    example_export_step.dependOn(&run_example_export.step);

    // Example 12: Parallel Optimization (v0.4.0)
    const example_parallel = b.addExecutable(.{
        .name = "example-parallel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/12_parallel_optimize.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_parallel);
    const run_example_parallel = b.addRunArtifact(example_parallel);
    const example_parallel_step = b.step("run-example-parallel", "Run parallel optimization example");
    example_parallel_step.dependOn(&run_example_parallel.step);

    // Example 13: Event-Driven Architecture (v0.5.0)
    const example_event_driven = b.addExecutable(.{
        .name = "example-event-driven",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/13_event_driven.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_event_driven);
    const run_example_event_driven = b.addRunArtifact(example_event_driven);
    const example_event_driven_step = b.step("run-example-event-driven", "Run event-driven architecture example (v0.5.0)");
    example_event_driven_step.dependOn(&run_example_event_driven.step);

    // Example 14: Async Trading Engine (v0.5.0)
    const example_async_engine = b.addExecutable(.{
        .name = "example-async-engine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/14_async_engine.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_async_engine);
    const run_example_async_engine = b.addRunArtifact(example_async_engine);
    const example_async_engine_step = b.step("run-example-async-engine", "Run async trading engine example (v0.5.0)");
    example_async_engine_step.dependOn(&run_example_async_engine.step);

    // Example 15: Vectorized Backtest (v0.6.0)
    const example_vectorized = b.addExecutable(.{
        .name = "example-vectorized",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/15_vectorized_backtest.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_vectorized);
    const run_example_vectorized = b.addRunArtifact(example_vectorized);
    const example_vectorized_step = b.step("run-example-vectorized", "Run vectorized backtest example (v0.6.0)");
    example_vectorized_step.dependOn(&run_example_vectorized.step);

    // Example 16: Hyperliquid Adapter (v0.6.0)
    const example_adapter = b.addExecutable(.{
        .name = "example-adapter",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/16_hyperliquid_adapter.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_adapter);
    const run_example_adapter = b.addRunArtifact(example_adapter);
    const example_adapter_step = b.step("run-example-adapter", "Run Hyperliquid adapter example (v0.6.0)");
    example_adapter_step.dependOn(&run_example_adapter.step);

    // Example 17: Paper Trading (v0.6.0)
    const example_paper_trading = b.addExecutable(.{
        .name = "example-paper-trading",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/17_paper_trading.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_paper_trading);
    const run_example_paper_trading = b.addRunArtifact(example_paper_trading);
    const example_paper_trading_step = b.step("run-example-paper-trading", "Run paper trading example (v0.6.0)");
    example_paper_trading_step.dependOn(&run_example_paper_trading.step);

    // Example 18: Hot Reload (v0.6.0)
    const example_hot_reload = b.addExecutable(.{
        .name = "example-hot-reload",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/18_hot_reload.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_hot_reload);
    const run_example_hot_reload = b.addRunArtifact(example_hot_reload);
    const example_hot_reload_step = b.step("run-example-hot-reload", "Run hot reload example (v0.6.0)");
    example_hot_reload_step.dependOn(&run_example_hot_reload.step);

    // Example 19: Clock-Driven Mode (v0.7.0)
    const example_clock_driven = b.addExecutable(.{
        .name = "example-clock-driven",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/19_clock_driven.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_clock_driven);
    const run_example_clock_driven = b.addRunArtifact(example_clock_driven);
    const example_clock_driven_step = b.step("run-example-clock-driven", "Run clock-driven mode example (v0.7.0)");
    example_clock_driven_step.dependOn(&run_example_clock_driven.step);

    // Example 20: Pure Market Making (v0.7.0)
    const example_pure_mm = b.addExecutable(.{
        .name = "example-pure-mm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/20_pure_market_making.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_pure_mm);
    const run_example_pure_mm = b.addRunArtifact(example_pure_mm);
    const example_pure_mm_step = b.step("run-example-pure-mm", "Run pure market making example (v0.7.0)");
    example_pure_mm_step.dependOn(&run_example_pure_mm.step);

    // Example 21: Inventory Management (v0.7.0)
    const example_inventory = b.addExecutable(.{
        .name = "example-inventory",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/21_inventory_management.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_inventory);
    const run_example_inventory = b.addRunArtifact(example_inventory);
    const example_inventory_step = b.step("run-example-inventory", "Run inventory management example (v0.7.0)");
    example_inventory_step.dependOn(&run_example_inventory.step);

    // Example 22: Data Persistence (v0.7.0)
    const example_persistence = b.addExecutable(.{
        .name = "example-persistence",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/22_data_persistence.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_persistence);
    const run_example_persistence = b.addRunArtifact(example_persistence);
    const example_persistence_step = b.step("run-example-persistence", "Run data persistence example (v0.7.0)");
    example_persistence_step.dependOn(&run_example_persistence.step);

    // Example 23: Cross-Exchange Arbitrage (v0.7.0)
    const example_arbitrage = b.addExecutable(.{
        .name = "example-arbitrage",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/23_cross_exchange_arb.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_arbitrage);
    const run_example_arbitrage = b.addRunArtifact(example_arbitrage);
    const example_arbitrage_step = b.step("run-example-arbitrage", "Run cross-exchange arbitrage example (v0.7.0)");
    example_arbitrage_step.dependOn(&run_example_arbitrage.step);

    // Example 24: Queue Position Modeling (v0.7.0)
    const example_queue = b.addExecutable(.{
        .name = "example-queue",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/24_queue_position.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_queue);
    const run_example_queue = b.addRunArtifact(example_queue);
    const example_queue_step = b.step("run-example-queue", "Run queue position modeling example (v0.7.0)");
    example_queue_step.dependOn(&run_example_queue.step);

    // Example 25: Latency Simulation (v0.7.0)
    const example_latency = b.addExecutable(.{
        .name = "example-latency",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/25_latency_simulation.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_latency);
    const run_example_latency = b.addRunArtifact(example_latency);
    const example_latency_step = b.step("run-example-latency", "Run latency simulation example (v0.7.0)");
    example_latency_step.dependOn(&run_example_latency.step);

    // Example 32: AI Strategy (v0.9.0)
    const example_ai = b.addExecutable(.{
        .name = "example-ai",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/32_ai_strategy.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigQuant", .module = mod },
            },
        }),
    });
    b.installArtifact(example_ai);
    const run_example_ai = b.addRunArtifact(example_ai);
    const example_ai_step = b.step("run-example-ai", "Run AI strategy example (v0.9.0)");
    example_ai_step.dependOn(&run_example_ai.step);

    // Run all examples
    const examples_step = b.step("run-examples", "Run all examples");
    examples_step.dependOn(&run_example_core.step);
    examples_step.dependOn(&run_example_websocket.step);
    examples_step.dependOn(&run_example_http.step);
    examples_step.dependOn(&run_example_connector.step);
    examples_step.dependOn(&run_example_colored_logging.step);
    examples_step.dependOn(&run_example_backtest.step);
    examples_step.dependOn(&run_example_optimize.step);
    examples_step.dependOn(&run_example_custom.step);
    examples_step.dependOn(&run_example_indicators.step);
    examples_step.dependOn(&run_example_walkforward.step);
    examples_step.dependOn(&run_example_export.step);
    examples_step.dependOn(&run_example_parallel.step);
    examples_step.dependOn(&run_example_event_driven.step);
    examples_step.dependOn(&run_example_async_engine.step);
    examples_step.dependOn(&run_example_vectorized.step);
    examples_step.dependOn(&run_example_adapter.step);
    examples_step.dependOn(&run_example_paper_trading.step);
    examples_step.dependOn(&run_example_hot_reload.step);
    examples_step.dependOn(&run_example_clock_driven.step);
    examples_step.dependOn(&run_example_pure_mm.step);
    examples_step.dependOn(&run_example_inventory.step);
    examples_step.dependOn(&run_example_persistence.step);
    examples_step.dependOn(&run_example_arbitrage.step);
    examples_step.dependOn(&run_example_queue.step);
    examples_step.dependOn(&run_example_latency.step);
    examples_step.dependOn(&run_example_ai.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
