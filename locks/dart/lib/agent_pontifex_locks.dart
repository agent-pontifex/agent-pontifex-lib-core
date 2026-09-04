/// agent-pontifex lock routines. Re-exports `ores_locks_and_leases` and adds the
/// org's key prefix and lock catalog. Generated from `../catalog.json` by
/// ores-locks-and-leases' `templates/lib-core/gen_org_locks.py`.
library;

import 'package:ores_locks_and_leases/ores_locks_and_leases.dart';

export 'package:ores_locks_and_leases/ores_locks_and_leases.dart';

/// This org's key prefix.
const String org = 'agent-pontifex';

/// The lock domains this org uses.
enum Domain {
  jobs('jobs'),
  migrations('migrations'),
  outbox('outbox'),
  tenant('tenant');

  final String wire;
  const Domain(this.wire);
}

/// Build `agent-pontifex/<domain>/<name>`.
LockKey key(Domain domain, String name) => LockKey('$org/${domain.wire}/$name');

/// One catalog row: the defaults a call site should use for a named lock.
final class Entry {
  final Domain domain;

  /// May contain `{placeholders}`; see [key].
  final String name;
  final LockLayers layers;
  final PgScope pgScope;
  final bool wait;

  const Entry({
    required this.domain,
    required this.name,
    required this.layers,
    required this.pgScope,
    required this.wait,
  });

  /// The key for this entry with `{placeholders}` filled from [fill], in order of appearance.
  LockKey key(List<String> fill) {
    var i = 0;
    final filled = name.replaceAllMapped(
      RegExp(r'\{[^}]*\}'),
      (_) => i < fill.length ? fill[i++] : '',
    );
    return LockKey('$org/${domain.wire}/$filled');
  }

  /// The plan this entry's defaults produce.
  LockPlan get plan => planFor(layers, pgScope, wait);
}

LockPlan planFor(LockLayers layers, PgScope scope, bool wait) =>
    plan(layers, scope, wait);

/// The catalog, as constants.
abstract final class Catalog {
  /// One migration runner at a time. Session scope because some DDL cannot run inside a transaction; fail fast so a second runner exits instead of queueing.
  static const migrationsApply = Entry(
    domain: Domain.migrations,
    name: 'apply',
    layers: LockLayers(fiducia: true, pgAdvisory: true),
    pgScope: PgScope.session,
    wait: false,
  );

  /// A named job that must not overlap itself across replicas. Skip the run when it is already held.
  static const jobsSingletonJob = Entry(
    domain: Domain.jobs,
    name: 'singleton:{job}',
    layers: LockLayers(fiducia: true, pgAdvisory: true),
    pgScope: PgScope.transaction,
    wait: false,
  );

  /// Transactional-outbox drainer: single-database exclusion is enough, and the transaction that reads the batch is the one that holds the lock.
  static const outboxDrain = Entry(
    domain: Domain.outbox,
    name: 'drain',
    layers: LockLayers(fiducia: false, pgAdvisory: true),
    pgScope: PgScope.transaction,
    wait: false,
  );

  /// Serialize mutations of one tenant's aggregate across every server that can write it. Waits; contention here is normal.
  static const tenantTenantIdMutate = Entry(
    domain: Domain.tenant,
    name: '{tenant_id}/mutate',
    layers: LockLayers(fiducia: true, pgAdvisory: true),
    pgScope: PgScope.transaction,
    wait: true,
  );
}
