# Foreman provenance

- Repository: https://github.com/ddollar/foreman
- Revision: `f65ddba83932bd4670e014389d6e27ea1e20b469` (`update docs`)
- Source archive: https://codeload.github.com/ddollar/foreman/tar.gz/f65ddba83932bd4670e014389d6e27ea1e20b469
- License: MIT, Copyright (c) 2012 David Dollar; preserved verbatim in `LICENSE`.

The initial local import copied `lib/foreman/{procfile,env,process,engine,cli}.rb`
into the renamed namespace before applying the MVP changes. The Procfile
reader/writer, environment assignment/quoting parser, process execution wrapper,
ordered engine registration and lookup, pipe/signal approach, and Thor command
foundation derive from that source. The supervisor loop and terminal components
were refactored or written for Foruiman's independent process and log semantics.

Relevant upstream test files are retained verbatim as review references in
`docs/upstream/*_spec.rb.txt` (not part of the packaged gem). Active tests in
`spec/foruiman/procfile_spec.rb`, `env_spec.rb`, and `process_spec.rb` adapt the
applicable upstream examples to real temporary files and managed Ruby fixtures.
The CLI and engine tests cover the new contract rather than upstream concurrency,
export, command substitution, or stop-on-first-exit behavior.

`docs/upstream/SHA256SUMS` records the original imported source/test checksums.
Exporters, distribution code, scaling, and obsolete runtime compatibility code are
not included in the distributed implementation. There is no runtime dependency
on the Foreman gem and no claim of complete Foreman compatibility.
