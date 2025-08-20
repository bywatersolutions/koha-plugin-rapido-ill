# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

## [0.3.13] - 2024-08-XX

### Fixed
- [#53] Fix typo in codebase

## [0.3.12] - 2024-08-XX

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
