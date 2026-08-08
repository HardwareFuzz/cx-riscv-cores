#!/usr/bin/env python3
"""Validate the architectural invariants of one or more CX Trace V2 logs.

The validator deliberately ignores legacy lines and auxiliary CXTRACE events
except for checking that interrupts do not consume instruction identity fields.
It accepts simulator prefixes before ``CXTRACE`` so it can validate direct
Verilator output as well as trace files written by a host testbench.
"""

from __future__ import annotations

import argparse
import dataclasses
import pathlib
import re
import sys
from collections import defaultdict
from typing import Iterable, TextIO


TERMINAL_FIELDS = {
    "v",
    "event",
    "core",
    "hart",
    "token",
    "term_seq",
    "instret_seq",
    "commit_slot",
    "pc",
    "insn",
    "insn_len",
    "start_cycle",
    "end_cycle",
    "span",
    "start_kind",
    "end_kind",
    "retired",
    "trap",
    "cause",
    "priv",
}

PLAIN_HEADER_FIELDS = {
    "trace_version",
    "cycle_domain",
    "cycle_base",
    "interval",
    "start_kind",
    "end_kind",
    "core",
    "harts",
    "isa",
    "build_config",
}

INLINE_HEADER_FIELDS = {
    "cycle_domain",
    "cycle_base",
    "interval",
    "start_kind",
    "end_kind",
    "core",
    "harts",
    "isa",
    "build_config",
}

FIXED_HEADER_FIELDS = {
    "cycle_domain": "core_ref_clk",
    "cycle_base": "first_post_reset_posedge_is_1",
    "interval": "inclusive",
    "start_kind": "backend_alloc",
    "end_kind": "arch_commit_or_precise_trap",
}

MAX_U64 = (1 << 64) - 1
MAX_U32 = (1 << 32) - 1
ISA_PATTERN = re.compile(r"rv(?:32|64)[a-z0-9_]*", re.IGNORECASE)


@dataclasses.dataclass(frozen=True)
class Terminal:
    source: str
    line_number: int
    hart: int
    token: int
    term_seq: int
    instret_seq: int | None
    commit_slot: int
    end_cycle: int
    retired: bool


class Validation:
    def __init__(self, max_errors: int) -> None:
        self.max_errors = max_errors
        self.errors: list[str] = []
        self.headers = 0
        self.plain_header_fields: dict[str, tuple[str, int]] = {}
        self.header_core: str | None = None
        self.header_harts: int | None = None
        self.interrupts = 0
        self.interrupt_identities: list[tuple[str, int, str, int]] = []
        self.auxiliary = 0
        self.terminals: list[Terminal] = []
        self.hart_tokens: dict[int, set[int]] = defaultdict(set)
        self.next_term_seq: dict[int, int] = defaultdict(int)
        self.next_instret_seq: dict[int, int] = defaultdict(int)
        self.last_end_cycle: dict[int, int] = {}
        self.hart_retired: dict[int, int] = defaultdict(int)
        self.hart_traps: dict[int, int] = defaultdict(int)
        self.terminal_cores: set[str] = set()

    def error(self, source: str, line_number: int, detail: str) -> None:
        if len(self.errors) < self.max_errors:
            self.errors.append(f"{source}:{line_number}: {detail}")

    def parse_fields(
        self, record: str, source: str, line_number: int
    ) -> dict[str, str]:
        fields: dict[str, str] = {}
        for word in record.split()[1:]:
            if "=" not in word:
                continue
            key, value = word.split("=", 1)
            if key in fields:
                self.error(source, line_number, f"duplicate field {key!r}")
            fields[key] = value.rstrip(",")
        return fields

    def consume_header(
        self, fields: dict[str, str], source: str, line_number: int
    ) -> None:
        self.headers += 1
        missing = sorted(INLINE_HEADER_FIELDS - fields.keys())
        if missing:
            self.error(
                source,
                line_number,
                "V2 run header is missing fields: " + ", ".join(missing),
            )

        version = fields.get("v", fields.get("trace_version"))
        if version != "2":
            self.error(source, line_number, f"run header has trace version {version!r}, expected '2'")
        if "v" in fields and "trace_version" in fields and fields["v"] != fields["trace_version"]:
            self.error(source, line_number, "run header v and trace_version disagree")

        for key, expected in FIXED_HEADER_FIELDS.items():
            if key in fields and fields[key] != expected:
                self.error(
                    source,
                    line_number,
                    f"run header {key}={fields[key]!r}, expected {expected!r}",
                )

        core = fields.get("core", "")
        if not core:
            self.error(source, line_number, "run header core must be non-empty")
        elif self.header_core is None:
            self.header_core = core
        elif self.header_core != core:
            self.error(
                source,
                line_number,
                f"conflicting run-header cores {self.header_core!r} and {core!r}",
            )

        harts = self.integer(fields, "harts", source, line_number, max_value=MAX_U32)
        if harts is not None:
            # cx-riscv-cores currently publishes only 1c and 2c simulators.
            if harts not in (1, 2):
                self.error(source, line_number, f"run header harts must be 1 or 2, got {harts}")
            elif self.header_harts is None:
                self.header_harts = harts
            elif self.header_harts != harts:
                self.error(
                    source,
                    line_number,
                    f"conflicting run-header hart counts {self.header_harts} and {harts}",
                )

        isa = fields.get("isa", "")
        if not ISA_PATTERN.fullmatch(isa):
            self.error(source, line_number, f"run header isa is not a canonical RISC-V tag: {isa!r}")
        if not fields.get("build_config"):
            self.error(source, line_number, "run header build_config must be non-empty")

    def integer(
        self,
        fields: dict[str, str],
        key: str,
        source: str,
        line_number: int,
        *,
        nonnegative: bool = True,
        max_value: int | None = None,
    ) -> int | None:
        raw = fields.get(key)
        if raw is None:
            return None
        try:
            # Trace sequence/cycle fields are decimal. Hexadecimal is accepted
            # for architectural values such as pc, insn, cause and priv.
            value = int(raw, 0)
        except ValueError:
            try:
                value = int(raw, 16) if any(c in "abcdefABCDEF" for c in raw) else int(raw, 10)
            except ValueError:
                self.error(source, line_number, f"{key} is not an integer: {raw!r}")
                return None
        if nonnegative and value < 0:
            self.error(source, line_number, f"{key} is negative: {value}")
            return None
        if max_value is not None and value > max_value:
            self.error(source, line_number, f"{key} exceeds {max_value}: {value}")
            return None
        return value

    def consume_terminal(
        self, fields: dict[str, str], source: str, line_number: int
    ) -> None:
        missing = sorted(TERMINAL_FIELDS - fields.keys())
        if missing:
            self.error(source, line_number, f"terminal is missing fields: {', '.join(missing)}")
            return
        if fields["v"] != "2":
            self.error(source, line_number, f"unexpected trace version {fields['v']!r}")
        if fields["start_kind"] != "backend_alloc":
            self.error(source, line_number, "start_kind must be backend_alloc")
        if not fields["core"]:
            self.error(source, line_number, "terminal core must be non-empty")
        else:
            self.terminal_cores.add(fields["core"])

        numeric_keys = (
            "hart",
            "token",
            "term_seq",
            "commit_slot",
            "pc",
            "insn",
            "insn_len",
            "start_cycle",
            "end_cycle",
            "span",
            "retired",
            "trap",
            "priv",
        )
        u64_keys = {"token", "term_seq", "pc", "start_cycle", "end_cycle", "span"}
        u32_keys = {"hart", "commit_slot", "insn", "priv"}
        values = {
            key: self.integer(
                fields,
                key,
                source,
                line_number,
                max_value=MAX_U64 if key in u64_keys else MAX_U32 if key in u32_keys else None,
            )
            for key in numeric_keys
        }
        if any(value is None for value in values.values()):
            return

        hart = values["hart"]
        token = values["token"]
        term_seq = values["term_seq"]
        commit_slot = values["commit_slot"]
        insn = values["insn"]
        insn_len = values["insn_len"]
        start_cycle = values["start_cycle"]
        end_cycle = values["end_cycle"]
        span = values["span"]
        retired_raw = values["retired"]
        trap_raw = values["trap"]
        privilege = values["priv"]
        assert all(
            isinstance(value, int)
            for value in (
                hart,
                token,
                term_seq,
                commit_slot,
                insn,
                insn_len,
                start_cycle,
                end_cycle,
                span,
                retired_raw,
                trap_raw,
                privilege,
            )
        )

        if retired_raw not in (0, 1) or trap_raw not in (0, 1):
            self.error(source, line_number, "retired and trap must be 0 or 1")
            return
        retired = bool(retired_raw)
        trap = bool(trap_raw)
        expected_end_kind = "arch_commit" if retired else "precise_trap"
        if retired == trap or fields["end_kind"] != expected_end_kind:
            self.error(
                source,
                line_number,
                "retired/trap/end_kind do not describe one normal commit or precise trap",
            )

        if retired:
            if fields["cause"] != "none":
                self.error(
                    source,
                    line_number,
                    "architectural commit must encode cause=none",
                )
        else:
            # A precise trap must retain its architectural numeric cause.  In
            # particular, cause 0 is a real exception and must not be confused
            # with the normal-commit sentinel above.
            self.integer(fields, "cause", source, line_number, max_value=MAX_U64)

        instret_seq: int | None
        if retired:
            instret_seq = self.integer(
                fields, "instret_seq", source, line_number, max_value=MAX_U64
            )
            if instret_seq is None:
                return
        else:
            instret_seq = None
            if fields["instret_seq"] != "-":
                self.error(
                    source,
                    line_number,
                    "precise trap must encode instret_seq=-",
                )

        if start_cycle < 1 or end_cycle < start_cycle:
            self.error(
                source,
                line_number,
                f"invalid inclusive interval {start_cycle}..={end_cycle}",
            )
        elif span != end_cycle - start_cycle + 1:
            self.error(
                source,
                line_number,
                f"span={span}, expected {end_cycle - start_cycle + 1}",
            )

        if insn_len not in (2, 4):
            self.error(source, line_number, f"insn_len must be 2 or 4, got {insn_len}")
        elif insn_len == 2 and insn > 0xFFFF:
            self.error(source, line_number, f"compressed insn is wider than 16 bits: 0x{insn:x}")
        if privilege not in (0, 1, 3):
            self.error(source, line_number, f"priv must be U/S/M mode (0, 1 or 3), got {privilege}")

        if "start_valid" in fields:
            start_valid = self.integer(fields, "start_valid", source, line_number)
            if start_valid != 1:
                self.error(
                    source,
                    line_number,
                    f"terminal explicitly reports invalid allocation metadata: start_valid={fields['start_valid']}",
                )

        if token in self.hart_tokens[hart]:
            self.error(source, line_number, f"duplicate terminal token {token} on hart {hart}")
        self.hart_tokens[hart].add(token)

        expected_term = self.next_term_seq[hart]
        if term_seq != expected_term:
            self.error(
                source,
                line_number,
                f"hart {hart} term_seq={term_seq}, expected {expected_term}",
            )
        self.next_term_seq[hart] = term_seq + 1

        previous_end = self.last_end_cycle.get(hart)
        if previous_end is not None and end_cycle < previous_end:
            self.error(
                source,
                line_number,
                f"hart {hart} terminal time moved backwards from {previous_end} to {end_cycle}",
            )
        self.last_end_cycle[hart] = end_cycle

        if retired:
            expected_instret = self.next_instret_seq[hart]
            if instret_seq != expected_instret:
                self.error(
                    source,
                    line_number,
                    f"hart {hart} instret_seq={instret_seq}, expected {expected_instret}",
                )
            assert instret_seq is not None
            self.next_instret_seq[hart] = instret_seq + 1
            self.hart_retired[hart] += 1
        else:
            self.hart_traps[hart] += 1

        self.terminals.append(
            Terminal(
                source=source,
                line_number=line_number,
                hart=hart,
                token=token,
                term_seq=term_seq,
                instret_seq=instret_seq,
                commit_slot=commit_slot,
                end_cycle=end_cycle,
                retired=retired,
            )
        )

    def consume_interrupt(
        self, fields: dict[str, str], source: str, line_number: int
    ) -> None:
        self.interrupts += 1
        for required in ("v", "event", "core", "hart", "cycle", "cause"):
            if required not in fields:
                self.error(source, line_number, f"interrupt is missing {required}")
        forbidden = {"token", "term_seq", "instret_seq", "start_cycle", "end_cycle"}
        present = sorted(forbidden & fields.keys())
        if present:
            self.error(
                source,
                line_number,
                f"interrupt consumes instruction identity fields: {', '.join(present)}",
            )
        core = fields.get("core", "")
        if not core:
            self.error(source, line_number, "interrupt core must be non-empty")
        hart = self.integer(fields, "hart", source, line_number, max_value=MAX_U32)
        if core and hart is not None:
            self.interrupt_identities.append((core, hart, source, line_number))
        cycle = self.integer(fields, "cycle", source, line_number, max_value=MAX_U64)
        if cycle is not None and cycle < 1:
            self.error(source, line_number, f"interrupt cycle must be at least 1, got {cycle}")
        self.integer(fields, "cause", source, line_number, max_value=MAX_U64)
        if "priv" in fields:
            privilege = self.integer(fields, "priv", source, line_number, max_value=3)
            if privilege is not None and privilege not in (0, 1, 3):
                self.error(source, line_number, f"interrupt priv is reserved: {privilege}")

    def consume_line(self, raw_line: str, source: str, line_number: int) -> None:
        header_marker = raw_line.find("CXTRACE_HEADER ")
        if header_marker >= 0:
            record = raw_line[header_marker:].strip()
            fields = self.parse_fields(record, source, line_number)
            self.consume_header(fields, source, line_number)
            return
        marker = raw_line.find("CXTRACE ")
        if marker < 0:
            stripped = raw_line.strip()
            if "=" in stripped and " " not in stripped:
                key, value = stripped.split("=", 1)
                if key in PLAIN_HEADER_FIELDS:
                    if key in self.plain_header_fields:
                        self.error(source, line_number, f"duplicate plain-header field {key!r}")
                    self.plain_header_fields[key] = (value, line_number)
            return
        record = raw_line[marker:].strip()
        fields = self.parse_fields(record, source, line_number)
        if fields.get("v") != "2":
            self.error(source, line_number, "CXTRACE record is not v=2")
            return
        event = fields.get("event")
        if event == "inst_terminal":
            self.consume_terminal(fields, source, line_number)
        elif event == "interrupt":
            self.consume_interrupt(fields, source, line_number)
        elif event:
            self.auxiliary += 1
        else:
            self.error(source, line_number, "CXTRACE record is missing event")

    def finalize_header(self, display_name: str) -> None:
        if self.plain_header_fields:
            missing = sorted(PLAIN_HEADER_FIELDS - self.plain_header_fields.keys())
            if missing:
                if self.headers == 0:
                    self.error(
                        display_name,
                        0,
                        "incomplete plain V2 run header; missing fields: " + ", ".join(missing),
                    )
            else:
                fields = {
                    key: value for key, (value, _line_number) in self.plain_header_fields.items()
                }
                first_line = min(line for _value, line in self.plain_header_fields.values())
                self.consume_header(fields, display_name, first_line)

        if self.headers == 0:
            self.error(display_name, 0, "no complete CX Trace V2 run header found")

        if self.header_core is not None and self.terminal_cores != {self.header_core}:
            self.error(
                display_name,
                0,
                f"terminal cores {sorted(self.terminal_cores)!r} do not match run-header core {self.header_core!r}",
            )
        if self.header_harts is not None:
            for hart in sorted(self.next_term_seq):
                if hart >= self.header_harts:
                    self.error(
                        display_name,
                        0,
                        f"terminal hart {hart} is outside header harts={self.header_harts}",
                    )
        for core, hart, source, line_number in self.interrupt_identities:
            if self.header_core is not None and core != self.header_core:
                self.error(
                    source,
                    line_number,
                    f"interrupt core {core!r} does not match run-header core {self.header_core!r}",
                )
            if self.header_harts is not None and hart >= self.header_harts:
                self.error(
                    source,
                    line_number,
                    f"interrupt hart {hart} is outside header harts={self.header_harts}",
                )

    def check_commit_slots(self) -> None:
        groups: dict[tuple[str, int, int], list[Terminal]] = defaultdict(list)
        for terminal in self.terminals:
            groups[(terminal.source, terminal.hart, terminal.end_cycle)].append(terminal)
        for (_, hart, cycle), records in groups.items():
            expected_slots = list(range(len(records)))
            actual_slots = [record.commit_slot for record in records]
            if actual_slots != expected_slots:
                first = records[0]
                self.error(
                    first.source,
                    first.line_number,
                    f"hart {hart} cycle {cycle} commit slots {actual_slots}, expected {expected_slots}",
                )


def lines_from_path(path: pathlib.Path) -> Iterable[tuple[str, int, str]]:
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, line in enumerate(handle, 1):
            yield str(path), line_number, line


def lines_from_stdin(handle: TextIO) -> Iterable[tuple[str, int, str]]:
    for line_number, line in enumerate(handle, 1):
        yield "<stdin>", line_number, line


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="*", type=pathlib.Path, help="trace logs; stdin if omitted")
    parser.add_argument(
        "--max-errors", type=int, default=100, help="maximum number of diagnostics to retain"
    )
    args = parser.parse_args()
    def validate_one(
        display_name: str, stream: Iterable[tuple[str, int, str]]
    ) -> int:
        validation = Validation(max(1, args.max_errors))
        try:
            for source, line_number, line in stream:
                validation.consume_line(line, source, line_number)
        except OSError as error:
            print(f"cxtrace-v2 validation error: {error}", file=sys.stderr)
            return 2

        validation.finalize_header(display_name)
        validation.check_commit_slots()
        if not validation.terminals:
            validation.error(display_name, 0, "no CXTRACE v=2 inst_terminal records found")

        harts = sorted(validation.next_term_seq)
        print(
            f"CXTRACE V2 summary [{display_name}]: "
            f"headers={validation.headers} terminals={len(validation.terminals)} "
            f"interrupts={validation.interrupts} auxiliary={validation.auxiliary} "
            f"harts={harts}"
        )
        for hart in harts:
            print(
                f"  hart={hart} terminals={validation.next_term_seq[hart]} "
                f"retired={validation.hart_retired[hart]} traps={validation.hart_traps[hart]} "
                f"next_instret_seq={validation.next_instret_seq[hart]}"
            )

        if validation.errors:
            print(
                f"CXTRACE V2 validation failed [{display_name}] with "
                f"{len(validation.errors)} error(s):",
                file=sys.stderr,
            )
            for error in validation.errors:
                print(f"  {error}", file=sys.stderr)
            return 1
        print(f"CXTRACE V2 validation passed [{display_name}]")
        return 0

    if not args.logs:
        return validate_one("<stdin>", lines_from_stdin(sys.stdin))

    exit_status = 0
    for path in args.logs:
        status = validate_one(str(path), lines_from_path(path))
        exit_status = max(exit_status, status)
    return exit_status


if __name__ == "__main__":
    raise SystemExit(main())
