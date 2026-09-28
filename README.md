# Angular server asset / generated entry collision reproduction

This repository demonstrates an output-integrity failure in the shipped Angular
`@angular-devkit/build-angular:server` builder. A configured dependency asset is
copied after Webpack emits the server program. If that asset is named `main.js`
and the asset output is the server output root, the copy silently replaces the
generated server entry point. Starting the built application then runs the
dependency-controlled file.

The reproduction pins Angular, Angular CLI, and the builder to 22.2.0 and Node
to 24.21.0. It uses no Angular source modification, debug API, install script,
direct output mutation, or privileged runtime control.

## Run the automated reproduction

Requirements:

- Docker with Compose v2
- network access while the image installs the pinned npm packages

Run:

```sh
./scripts/validate.sh
```

The container has no runtime network. The script builds and starts these four
states in order:

1. `clean-1`: dependency version 1.0.0 contains only benign `data.json`.
2. `attack-1`: version 1.0.1 adds only `assets/main.js`.
3. `clean-2`: restoring 1.0.0 restores the genuine Angular server bundle.
4. `attack-2`: restoring 1.0.1 reproduces replacement and execution.

For each state, the script installs the local dependency archive with
`--ignore-scripts`, runs the real Angular server build, starts
`dist/server/main.js`, and records the output hash, startup output, and marker
status. Attack states must be byte-for-byte identical to the dependency asset;
clean and attack hashes must each repeat across both cycles.

Evidence is preserved under `evidence/<run-id>/`. A successful run ends with
`PROTOCOL_COMPLETE` and produces `summary.tsv`, complete build/startup logs,
input hashes, and copies of each built entry point.

## Why the control is meaningful

The two dependency packages have the same name and the same benign data asset.
Neither package has `scripts`, `main`, `exports`, `imports`, or `bin`. The only
payload-bearing difference is `assets/main.js` in version 1.0.1. The victim
configuration publishes the dependency's documented asset directory with a
normal Angular asset glob and uses the stable server entry filename produced by
`outputHashing: "none"`.

The marker file is created only when the built server entry point is started.
It makes the security consequence observable without networking or an external
service.

## Cleanup

Remove the generated `evidence/` directory and the Compose image when they are
no longer needed:

```sh
docker compose down --rmi local
```
