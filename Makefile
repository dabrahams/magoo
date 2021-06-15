# Part of the Carbon Language project, under the Apache License v2.0 with LLVM
# Exceptions. See /LICENSE for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# This Makefile is a thin layer on top of Swift package manager that handles the
# building of the citron parser generator binary and the generation of
# Sources/Parser.swift from Sources/Parser.citron.
GRAMMAR = ./Sources/Parser
CC = cc
SWIFTC = swiftc
BIN = ./bin
SWIFT_FLAGS =
LCOV_FILE = ./.build/coverage.lcov
SHELL=/bin/bash

ifeq ($(OS),Windows_NT)
    GRAMMAR_OPTS =  -Xlinker swiftCore.lib
else
    GRAMMAR_OPTS =
endif

build: ${GRAMMAR}.swift
	swift build --enable-test-discovery ${SWIFT_FLAGS}

test: ${GRAMMAR}.swift
	swift test --enable-test-discovery ${SWIFT_FLAGS}

test-lcov: ${GRAMMAR}.swift
	swift build --build-tests --enable-code-coverage
	$$(swift test --enable-test-discovery --enable-code-coverage --verbose \
	   ${SWIFT_FLAGS} 2>&1 \
	   | tee /dev/tty | grep 'llvm-cov export' \
	   | sed -e 's/ export / export -format=lcov /') > "${LCOV_FILE}"

test-jcov: ${GRAMMAR}.swift
	swift test --enable-test-discovery --enable-code-coverage ${SWIFT_FLAGS}

clean:
	rm -rf ${GRAMMAR}.swift ./.build

${GRAMMAR}.swift: ${GRAMMAR}.citron
	rm -f $@
	swift build --target citron # Build citron executable
	swift run citron ${GRAMMAR_OPTS} ${GRAMMAR}.citron -o $@ # Generate the grammar
	chmod -w $@                              # prevent unintended edits
