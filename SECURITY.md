# Security policy

## Supported versions

The latest minor release receives fixes.

## Reporting a vulnerability

SwaTex parses untrusted LaTeX input, so parser robustness is a security
surface (e.g. crashes on hostile input — a stack-overflow DoS was found
and fixed in 0.2.0; deeply nested input now fails with a parse error on
any thread).

Please report vulnerabilities privately to **security@phrase.so** — do
not open a public issue. We aim to acknowledge within 48 hours. Include a
minimal reproducing input if possible.
