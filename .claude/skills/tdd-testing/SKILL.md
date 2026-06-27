---
name: tdd-testing
description: t-wada's TDD methodology used in BiteLog — Red-Green-Refactor, TODO lists, triangulation, and test writing guidelines. Use when writing tests or implementing features test-first.
---

# Testing Strategy — t-wada's TDD Approach

This project follows the Test-Driven Development (TDD) approach advocated by
Takuto Wada (t-wada).

## Core Principles

1. **Red-Green-Refactor**: Write a failing test → Implement minimal code to pass → Refactor
2. **TODO List**: List all required test cases before implementation
3. **Triangulation**: Derive generalization from multiple specific examples
4. **Obvious Implementation**: Start with simple, obvious implementations
5. **Fake It**: Pass tests with constants first, then generalize gradually

## Test Writing Guidelines

- Write tests as readable specifications
- Test names can be descriptive (clearly state what is being tested)
- Use Arrange-Act-Assert pattern
- One test method should test only one thing

## Development Process

1. Create a TODO list of test cases
2. Start with the simplest test case
3. Follow test-first approach (test → implementation order)
4. Keep each step in a committable state
5. Ensure tests pass during refactoring
