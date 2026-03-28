## Purpose

NixOS adapter module for Home Manager config accumulation via `deferredModule`. Provides the `agentplot.hmModules` namespace where clanService client roles register their HM configuration, and an `agentplot.user` option to wire accumulated modules into `home-manager.users`.

## Requirements

### Requirement: NixOS option namespace for HM config accumulation
The adapter module SHALL define `options.agentplot.hmModules` as `attrsOf deferredModule`. Each agentplot clanService client role SHALL write its generated Home Manager configuration into a uniquely-keyed entry in this namespace. Keys SHALL be namespaced by service and instance (e.g., `linkding-personal`, `linkding-business`).

#### Scenario: Single clanService registers HM config
- **WHEN** the linkding clanService client role is evaluated for a machine
- **THEN** `config.agentplot.hmModules` SHALL contain an entry keyed by the service-client name with a valid Home Manager module

#### Scenario: Multiple clanServices compose
- **WHEN** both linkding and paperless clanService client roles are evaluated for the same machine
- **THEN** `config.agentplot.hmModules` SHALL contain entries for both services and they SHALL merge without conflict

### Requirement: User wiring option
The adapter module SHALL define `options.agentplot.user` as `nullOr str` with default `null`. When set to a username string, the module SHALL import all `agentplot.hmModules` entries into `home-manager.users.${agentplot.user}`.

#### Scenario: User is set
- **WHEN** `agentplot.user = "chuck"` is configured
- **THEN** all entries in `agentplot.hmModules` SHALL be imported as Home Manager modules for the `chuck` user

#### Scenario: User is null
- **WHEN** `agentplot.user` is not set (null)
- **THEN** `agentplot.hmModules` entries SHALL exist but SHALL NOT be wired into any `home-manager.users` automatically

### Requirement: Platform compatibility
The adapter module SHALL work identically on NixOS (via `home-manager.users`) and nix-darwin (via `home-manager.users`). The module SHALL NOT contain platform-specific code paths.

#### Scenario: NixOS deployment
- **WHEN** the adapter module is imported on a NixOS system with home-manager integration
- **THEN** HM config SHALL be applied to the specified user

#### Scenario: nix-darwin deployment
- **WHEN** the adapter module is imported on a nix-darwin system with home-manager integration
- **THEN** HM config SHALL be applied to the specified user using the same code path as NixOS

### Requirement: Clan vars accessibility from HM modules
The deferred HM modules accumulated in `agentplot.hmModules` SHALL access NixOS-level values (including `config.clan.core.vars.generators.*.files.*.path`) via closure capture in the clanService's `perInstance` block. Secret paths MUST be interpolated into string values in the perInstance `let` block *before* entering the deferredModule -- the deferredModule's `config` argument refers to Home Manager config, not NixOS config.

#### Scenario: HM module references clan var secret path
- **WHEN** a clanService client role generates HM config that references a clan vars secret path
- **THEN** the path SHALL be captured as a string value in the perInstance closure
- **AND** the HM module SHALL use the captured string in env vars or file references

### Requirement: HM integration module dependency
The adapter module SHALL require the Home Manager NixOS/nix-darwin integration module (`home-manager.nixosModules.home-manager` or `home-manager.darwinModules.home-manager`). It SHALL NOT support standalone Home Manager.

#### Scenario: Missing HM integration
- **WHEN** the adapter module is imported without the HM integration module
- **THEN** evaluation SHALL fail with a clear error about the missing `home-manager.users` option
