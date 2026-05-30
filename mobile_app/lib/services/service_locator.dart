/// Application-wide service locator.
///
/// Provides lazy-initialized singletons for all core services.  Initialize
/// once in `main.dart` via [ServiceLocator.init] before `runApp`.
///
/// Access services anywhere with `ServiceLocator.instance.xxx`.
///
/// Every service getter throws [StateError] if accessed before [init] has been
/// called, so accidental use during startup is caught immediately.
library;

import '../app/app_config.dart';
import '../domain/task_domain_service.dart';
import '../repositories/task_repository.dart';
import '../state/task_store.dart';

import 'api_client.dart';
import 'local_db.dart';

// ── Concrete implementation classes (imported only here) ────────────────

/// Central registry for application services.
///
/// All services are lazily created on first access and cached for the
/// lifetime of the application.  The locator is a singleton so there is
/// exactly one instance per process.
class ServiceLocator {
  ServiceLocator._();

  static final ServiceLocator _instance = ServiceLocator._();

  /// The singleton locator instance.
  ///
  /// Access only after [init] has completed.  Service getters will throw
  /// [StateError] if accessed before initialization.
  static ServiceLocator get instance => _instance;

  bool _initialized = false;

  // ── Core services ────────────────────────────────────────────────────

  /// Shared API facade (Sync, Chat, Call).
  ApiClient get api => _checkInit(() => _api);
  late ApiClient _api;

  /// Local SQLite database (singleton).
  LocalDb get db => _checkInit(() => _db);
  late LocalDb _db;

  /// Task repository — the single source of truth for task data.
  TaskRepository get taskRepository => _checkInit(() => _taskRepository);
  late TaskRepository _taskRepository;

  /// Domain logic for task CRUD and validation.
  final TaskDomainService taskDomainService = TaskDomainService();

  /// Central reactive state container.
  TaskStore get taskStore => _checkInit(() => _taskStore);
  late TaskStore _taskStore;

  // ── Initialization ───────────────────────────────────────────────────

  /// Initialize the locator and all services that require async setup.
  ///
  /// Call this once in `main()` before `runApp()`.  After this call,
  /// [instance] is safe to access from anywhere in the application.
  Future<void> init() async {
    // 1. API client.
    _api = ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      apiKey: AppConfig.apiKey,
    );

    // 2. Open database.
    _db = await LocalDb.open();

    // 3. Create repository.
    _taskRepository = TaskRepository(db: _db, api: _api);

    // 4. Create store — the central state container.
    _taskStore = TaskStore(
      repository: _taskRepository,
      domainService: taskDomainService,
    );

    _initialized = true;
  }

  T _checkInit<T>(T Function() getter) {
    if (!_initialized) {
      throw StateError(
        'ServiceLocator not initialized. Call ServiceLocator.instance.init() in main() before runApp().',
      );
    }
    return getter();
  }

  /// Release resources.  Call in tests or when tearing down the app.
  void dispose() {
    if (_initialized) {
      _taskStore.dispose();
      _initialized = false;
    }
  }
}
