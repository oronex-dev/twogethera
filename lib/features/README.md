# Feature boundaries

Each module owns `presentation/`, `domain/`, and `data/` layers. Empty layers are intentional placeholders for CP-002 and later work.

- Presentation: screens, feature widgets, and Riverpod controllers.
- Domain: pure Dart models and repository contracts, independent of Flutter and storage SDKs.
- Data: implementations and mappings between local/cloud records and domain models.

Dependencies flow inward: presentation → domain ← data. The app composition layer wires implementations to contracts. Features should not import another feature’s data or presentation internals. Put genuinely shared UI in `shared/` and cross-cutting configuration/errors in `core/`; avoid generic dumping grounds.

No repositories, fake services, auth gates, database schemas, or sync logic exist in CP-001.
