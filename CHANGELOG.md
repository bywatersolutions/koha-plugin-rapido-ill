# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.8] - 2025-08-27

### Added
- [#83] Added `decoded_payload` method to RapidoILL::QueuedTask for JSON-decoding payload attribute
- [#83] Overloaded `store` method in RapidoILL::QueuedTask to automatically JSON-encode payload references
- [#83] Added ILL renewal system with B_ITEM_RENEWAL_REQUESTED status and borrower_renew action
- [#83] Added renewal task queue processing with structured payload support

### Fixed
- [#84] Added PATRON_HOLD to no-op status list to prevent UnhandledException errors

### Changed
- [#84] Refactored both ActionHandlers to use no-op status list instead of empty methods for better maintainability

## [0.7.7] - 2025-08-27

### Fixed
- [#82] Added missing BORROWING_SITE_CANCEL action handler to prevent UnhandledException errors
- [#82] BORROWING_SITE_CANCEL now properly sets request status to O_ITEM_CANCELLED and cancels associated holds

## [0.7.6] - 2025-08-27

### Enhanced
- [#81] Improved RequestFailed exception error messages with detailed HTTP information for better debugging

### Fixed
- [#81] RequestFailed exceptions now show HTTP status codes, messages, and response bodies instead of memory addresses

## [0.7.5] - 2025-08-27

### Fixed
- [#78] QueuedTask retry method now handles both string and reference errors correctly for test compatibility

## [0.7.3] - 2025-08-27

### Enhanced
- [#77] Deferred OAuth2 token refresh for improved startup performance and error handling
- [#77] APIHttpClient constructor now succeeds immediately without network calls
- [#77] OAuth2 tokens acquired on-demand during first request instead of eagerly during construction
- [#77] Enhanced logging with contextual messages for token acquisition vs refresh scenarios
- [#78] Improved daemon performance by maintaining HTTP client cache across task batches
- [#78] Reduced OAuth2 API calls through proper token reuse (10-minute token lifespan)

### Fixed
- [#77] Authentication errors now occur during first request rather than during object construction
- [#77] Improved resilience against network issues during plugin initialization
- [#78] OAuth2 tokens now properly reused between task batches in daemon script
- [#78] JSON encoding error in QueuedTask retry method causing stuck retry loops
- [#78] Daemon script creating unnecessary plugin instances, breaking HTTP client cache

## [0.7.2] - 2025-08-27

### Fixed
- [#76] Complete interface coverage for Koha::Logger categories (opac, intranet, commandline, cron)
- [#76] Log format standardized to match Koha's standard format: `[%d] [%p] %m %l%n`
- [#76] Added troubleshooting guide for logging configuration issues

### Enhanced
- [#76] Comprehensive log4perl.conf configuration covering all execution contexts
- [#76] Documentation updated with complete interface-prefixed category examples

## [0.7.0] - 2025-08-26

### Changed
- [#75] **BREAKING**: Replaced custom debug_mode and debug_requests configuration with native log4perl integration
- [#75] Logging verbosity now controlled exclusively through Koha's log4perl.conf configuration
- [#75] Simplified plugin configuration by removing debug-related parameters
- [#76] **BREAKING**: Split logging into three separate log files for better operational monitoring

### Enhanced  
- [#75] Implemented conditional logging: brief error messages in production (INFO level), detailed HTTP debugging in debug mode (DEBUG level)
- [#75] Added business context parameters to all HTTP operations for improved traceability
- [#75] Optimized logging architecture to eliminate redundant messages between controller and HTTP client layers
- [#76] Implemented three dedicated logger categories:
  - `rapidoill` - General plugin operations (rapidoill.log)
  - `rapidoill.api` - External API calls to Rapido ILL servers (rapidoill-api.log)  
  - `rapidoill.daemon` - Task queue daemon processing (rapidoill-daemon.log)

### Removed
- [#75] Custom debug_mode() method and debug_requests parameter from plugin configuration
- [#75] All debug-related configuration options from documentation and example configs

### Migration Guide
- Remove `debug_mode` and `debug_requests` from your plugin configuration YAML
- Update log4perl.conf to configure three separate log files:
  ```perl
  # General plugin logging
  log4perl.logger.rapidoill = INFO, RAPIDOILL
  
  # API communication logging  
  log4perl.logger.rapidoill.api = DEBUG, RAPIDOILL_API
  
  # Task queue daemon logging
  log4perl.logger.rapidoill.daemon = INFO, RAPIDOILL_DAEMON
  ```
- Configure separate appenders for each log file (see README.md for complete configuration)

## [0.6.0] - 2025-08-26

### Enhanced
- [#75] HTTP logging improvements across all APIHttpClient methods - added detailed response content and headers in debug mode, context parameter support for business operation identification, and hybrid logging architecture to eliminate duplication

### Added
- [#75] Complete test coverage for all HTTP verb methods (POST, PUT, GET, DELETE, refresh_token) with proper LWP::UserAgent mocking and logger verification - 79 test assertions covering various HTTP status codes and context parameter functionality

### Fixed
- [#74] Added missing template files for Backend.pm error handling (borrower_cancel.inc, item_received.inc, item_in_transit.inc)

## [0.5.4] - 2025-08-26

### Fixed
- [#69] Fixed borrower_cancel method in Backend.pm to use correct BorrowerActions class (corrected fix - previous fix in v0.5.3 was incomplete)
- [#73] Standardize exception throwing patterns across codebase - use proper field-based format for MissingParameter and BadParameter exceptions

## [0.5.3] - 2025-08-26

### Changed
- [#70] Disable nightly agencies syncing - commented out cronjob_nightly hook
- [#71] Silence specific redefinition warnings for koha_objects_class and koha_object_class methods in schema result classes

### Fixed
- [#69] Fixed borrower_cancel method in Backend.pm calling wrong handler causing "unblessed reference" error in production
- [#72] Remove vulnerable node-datetime dependency from build process - replaced with built-in Node.js Date functionality

## [0.5.1] - 2025-08-26

### Changed
- [#67] Do not set interface in Koha::Logger->get()

## [0.5.0] - 2025-08-26

### Changed
- [#67] Replaced rapido_warn() with proper Koha::Logger integration for consistent logging
- [#68] Standardized Backend Actions method signatures to consistent `method($req, $params)` pattern
- [#68] Enhanced LenderActions methods to support optional `$params` with `client_options` passthrough
- [#68] Simplified BorrowerActions methods from hashref-first to request-first parameter approach
- [#68] All Backend Actions methods now return `$self` for method chaining support

### Removed
- [#67] Deprecated rapido_warn() method in favor of proper Koha logger

### Testing
- [#67] Updated test mocks to use logger instead of deprecated rapido_warn
- [#68] Replaced plugin mocking with real plugin instances to eliminate "Un-mocked method" warnings
- [#68] Updated all Backend Actions tests to use new standardized method signatures
- [#68] Replaced local redefinitions with Test::MockModule for cleaner test mocking
- [#68] Enhanced Backend Actions tests to verify API client method calls and client_options passthrough
- [#68] Added comprehensive verification of API client integration in all Backend Actions tests

### Documentation
- [#68] Added Backend Actions method patterns section to DEVELOPMENT.md
- [#68] Documented standardized method signatures and client_options usage
- [#68] Added migration guide from old patterns to new standardized approach

## [0.4.0] - 2025-08-22

### Added
- [#65] Complete ActionHandler system for circulation action processing
- RapidoILL::ActionHandler::Borrower class for borrower-side circulation workflows
- RapidoILL::ActionHandler::Lender class for lender-side circulation workflows
- Plugin integration methods: get_borrower_action_handler, get_lender_action_handler, get_action_handler
- Unified get_action_handler interface with perspective parameter ('borrower' or 'lender')
- Comprehensive test coverage for all ActionHandler classes and plugin integration
- Parameter pattern documentation in DEVELOPMENT.md for consistent API design
- POD documentation for all ActionHandler methods and plugin integration
- [#62] Due date setting from dueDateTime epoch in ITEM_SHIPPED messages
- [#66] Comprehensive documentation for ILL request status setting workaround (Bug #40682)

### Changed
- [#65] sync_circ_requests now uses ActionHandler system instead of legacy action methods
- update_ill_request method refactored with elegant ternary operator chain for perspective determination
- Consistent hashref parameter patterns across all plugin methods with validate_params
- Removed inheritance from ActionHandler classes to eliminate redefinition warnings
- Plugin-level caching for ActionHandler instances for improved performance
- [#62] item_shipped method now sets ILL request due_date from Rapido API dueDateTime field
- [#66] All status() calls now use explicit store() for future-proofing against upstream changes
- [#67] Replaced rapido_warn() with proper Koha::Logger integration for consistent logging

### Fixed
- [#66] ILL request status setting in BorrowerActions.pm (status was being ignored in set() calls)
- [#66] Future-proof all status updates with explicit store() calls for when Bug #40682 is resolved

### Removed
- [#67] Deprecated rapido_warn() method in favor of proper Koha logger

### Architecture
- ActionHandler system provides perspective-based processing (borrower vs lender workflows)
- Real CircAction object handling via TestBuilder integration
- Proper exception handling with RapidoILL::Exception types
- Database transaction support for reliable operations
- Clean separation of concerns between perspective determination and action execution

### Testing
- Unit tests for ActionHandler base class (constructor, parameter validation)
- Integration tests for concrete implementations (Borrower, Lender)
- Database-dependent tests with real CircAction objects
- Plugin accessor method testing with caching verification
- Exception handling validation for missing parameters
- [#62] Comprehensive due_date functionality tests with and without dueDateTime
- [#66] Updated tests to validate explicit store() calls for future-proofing
- [#67] Updated test mocks to use logger instead of deprecated rapido_warn
- Full test suite: 17 files, 99 tests, all passing

## [0.3.15] - 2025-08-20

### Added
- borrower_final_checkin method to handle FINAL_CHECKIN from borrower perspective
- Paper trail functionality in borrower_final_checkin (sets B_ITEM_CHECKED_IN before COMP)
- Paper trail functionality in lender final_checkin (sets O_ITEM_CHECKED_IN before COMP)
- Comprehensive test suite for BorrowerActions and LenderActions backend methods
- Backend test organization with t/RapidoILL/Backend/ directory structure
- Exception handling tests for all 17 RapidoILL exception classes
- Mock Rapido API with configurable scenarios for testing (borrowing, lending, mixed, cancellations)
- GET /scenarios endpoint for programmatic access to available test scenarios
- --list-scenarios CLI parameter for mock API to display available scenarios
- Control endpoints: POST /control/scenario/{name}, POST /control/reset
- Cancellation workflow scenarios: borrowing_cancellation, lending_cancellation, cancellations
- Lender cancel endpoint: POST /view/broker/circ/{circId}/lendercancel

### Fixed
- FINAL_CHECKIN handling in borrowing requests (previously threw UnhandledException)
- Complete borrowing workflow now works end-to-end without exceptions
- BorrowerActions now properly handles FINAL_CHECKIN circulation control

### Testing
- Added t/RapidoILL/Backend/BorrowerActions.t (7 tests) - FINAL_CHECKIN with paper trail validation
- Added t/RapidoILL/Backend/LenderActions.t (3 tests) - FINAL_CHECKIN consistency testing
- Full test suite now includes 15 test files with 81 total tests, all passing
- Comprehensive coverage of borrower_final_checkin method and paper trail functionality

## [0.3.14] - 2025-08-20

### Added
- [#54] Comprehensive unit tests for logger integration
- [#56] Enable IllLog syspref in bootstrap script for proper logging
- [#57] Comprehensive tests for add_or_update_attributes method
- [#58] Rename RapidoILL::OAuth2 to RapidoILL::APIHttpClient for better clarity
- [#59] Improve sync_requests.pl output and use proper logging
- [#60] Reorganize test file structure following Koha conventions
- GitHub release badge and GPL v3 license badge to README
- Comprehensive Exception tests covering all 17 exception classes
- Backend template correspondence tests
- Comprehensive development documentation

### Changed
- Test file organization: method tests now use underscore convention (RapidoILL_method_name.t)
- Separate class tests remain in subdirectories (RapidoILL/ClassName.t)
- Improved logging throughout the codebase with proper Koha::Logger integration
- Enhanced error handling and validation in database operations
- CI schedule changed from daily to twice monthly (1st and 15th of each month)

### Fixed
- [#54] Remove debug output from OAuth2 requests
- [#56] Fix bootstrap script and mock API for complete workflow testing
- [#57] Fix database constraint error in add_or_update_attributes method
- Database constraint validation and error handling improvements

### Documentation
- Updated DEVELOPMENT.md with comprehensive test documentation
- Added backend template test documentation
- Enhanced README with development workflow information
- Documented proper test file organization conventions

## [0.3.13] - 2024-08-13

### Fixed
- [#53] Fix typo in codebase

## [0.3.12] - 2024-08-13

### Fixed
- [#53] Fix database schema: add missing puaAgencyCode column

### Added
- Comprehensive mock Rapido API for development and testing
- Enhanced development documentation in README

### Changed
- Reorganized README structure for better clarity
- Updated GitHub Actions to latest version
- Improved CI to run all tests including subdirectories

---

*Note: This changelog was created retroactively. Future releases will maintain this format from the start.*
