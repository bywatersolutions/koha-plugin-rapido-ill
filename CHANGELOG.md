# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
