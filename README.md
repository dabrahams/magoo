# Barcon

Swift implementation of executable semantics of
[Carbon](https://carbon-language/carbon-lang).

## Preparation

1. Have Swift installed and in your path.
2. `git submodule update --init`
3. `eval "$(pyenv -)" && pre-commit install --allow-missing-config`

## To Build

    make build
    
## To Test

    make test

## To work on the project in Xcode

    make Sources/Syntax/Parser.swift
    open Package.swift
