#!/usr/bin/env python3
"""Conformance-lite evidence report for Moon Proto Lab.

The full upstream protobuf conformance runner is intentionally much larger than
this project needs for CI.  This script turns the checked-in Python/Go oracle
fixtures into an explicit, reviewable conformance-lite matrix: every fixture is
checked against the official Python protobuf encoder output, the checked-in
binary/hex/JSON files are cross-checked with each other, and Markdown/JSON/JUnit
reports are emitted for CI dashboards and contest review.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import importlib.util
import json
import shutil
import sys
import tempfile
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
PYTHON_ORACLE = ROOT / "tests" / "oracle" / "python_protobuf_oracle.py"


@dataclass(frozen=True)
class ConformanceCase:
    name: str
    fixture: str
    category: str
    feature: str
    oracle_function: str
    required_json: dict[str, Any]
    axes: tuple[str, ...]
    allow_binary_semantic_equivalence: bool = False
    message_class_function: str = ""


@dataclass
class CaseResult:
    name: str
    fixture: str
    category: str
    feature: str
    ok: bool
    details: str
    axes: tuple[str, ...] = ()
    sha256: str = ""
    size: int = 0


@dataclass(frozen=True)
class NegativeMutationCase:
    name: str
    base_case: str
    mutation: str
    feature: str
    axes: tuple[str, ...]


@dataclass(frozen=True)
class CoverageGate:
    name: str
    axis: str
    min_count: int
    ok: bool
    details: str


CASES = [
    ConformanceCase(
        name="proto3_scalar_repeated_packed_bytes_json64",
        fixture="user_full",
        category="binary+json",
        feature="uint64/string/bool/bytes/repeated/packed sint64 + protobuf JSON 64-bit strings",
        oracle_function="oracle_values",
        required_json={
            "id": "150",
            "name": 'Alice "A"',
            "active": True,
            "tags": ["admin", "tester"],
            "score": "-2",
            "blob": "/wA=",
            "samples": ["1", "150"],
            "deltas": ["-1", "2"],
        },
        axes=("oracle", "binary", "json", "scalar", "repeated", "packed", "bytes", "json-int64"),
    ),
    ConformanceCase(
        name="proto3_map_string_and_int64_keys",
        fixture="bag_maps",
        category="binary+json",
        feature="map<string,uint64> and map<int64,string> deterministic binary + JSON object mapping",
        oracle_function="bag_oracle_values",
        required_json={
            "scores": {"alice": "150", "bob": "7"},
            "labels": {"2": "two", "7": "seven"},
        },
        axes=("oracle", "binary", "json", "map"),
        allow_binary_semantic_equivalence=True,
        message_class_function="make_bag_message_class",
    ),
    ConformanceCase(
        name="proto3_oneof_last_selected_json",
        fixture="contact_oneof",
        category="binary+json",
        feature="oneof selected field binary encoding and JSON emission",
        oracle_function="contact_oracle_values",
        required_json={"id": "1", "phone": "123"},
        axes=("oracle", "binary", "json", "oneof"),
    ),
    ConformanceCase(
        name="proto3_32bit_numeric_boundaries",
        fixture="numbers32",
        category="binary+json",
        feature="uint32/int32/sint32/fixed32/sfixed32 boundary values",
        oracle_function="numbers32_oracle_values",
        required_json={"u": 4294967295, "i": -1, "s": -2, "f": 4294967295, "sf": -3},
        axes=("oracle", "binary", "json", "numeric32", "boundary"),
    ),
    ConformanceCase(
        name="proto3_float_double_roundtrip",
        fixture="floats",
        category="binary+json",
        feature="float and double finite numeric values",
        oracle_function="floats_oracle_values",
        required_json={"f": 1.5, "d": -2.25},
        axes=("oracle", "binary", "json", "float", "double"),
    ),
    ConformanceCase(
        name="proto3_float_special_json_strings",
        fixture="float_specials",
        category="binary+json",
        feature='NaN, Infinity and -Infinity protobuf JSON string mapping',
        oracle_function="float_specials_oracle_values",
        required_json={"f_nan": "NaN", "f_inf": "Infinity", "d_neg_inf": "-Infinity"},
        axes=("oracle", "binary", "json", "float", "double", "float-special"),
    ),
]


NEGATIVE_MUTATIONS = [
    NegativeMutationCase(
        name="reject_hex_binary_mismatch",
        base_case="proto3_scalar_repeated_packed_bytes_json64",
        mutation="hex_mismatch",
        feature="detects when a checked-in .hex file no longer decodes to the checked-in .bin fixture",
        axes=("negative", "mutation", "fixture-integrity", "hex"),
    ),
    NegativeMutationCase(
        name="reject_json_missing_required_evidence",
        base_case="proto3_scalar_repeated_packed_bytes_json64",
        mutation="json_missing_required_evidence",
        feature="detects when a JSON fixture silently drops required oracle evidence fields",
        axes=("negative", "mutation", "fixture-integrity", "json"),
    ),
    NegativeMutationCase(
        name="reject_missing_binary_fixture",
        base_case="proto3_oneof_last_selected_json",
        mutation="missing_bin",
        feature="detects when a binary golden fixture is absent from the conformance matrix",
        axes=("negative", "mutation", "fixture-integrity", "missing-artifact"),
    ),
    NegativeMutationCase(
        name="reject_corrupt_binary_fixture",
        base_case="proto3_float_double_roundtrip",
        mutation="corrupt_bin",
        feature="detects when binary fixture bytes no longer match the official protobuf oracle",
        axes=("negative", "mutation", "fixture-integrity", "binary"),
    ),
]


COVERAGE_REQUIREMENTS = {
    "oracle": 6,
    "binary": 6,
    "json": 6,
    "map": 1,
    "oneof": 1,
    "numeric32": 1,
    "float": 2,
    "float-special": 1,
    "negative": 4,
    "fixture-integrity": 4,
}


def load_python_oracle_module():
    from google.protobuf import message_factory

    if not hasattr(message_factory.MessageFactory, "GetPrototype"):
        def _message_factory_get_prototype(self, descriptor):
            return message_factory.GetMessageClass(descriptor)

        message_factory.MessageFactory.GetPrototype = _message_factory_get_prototype

    spec = importlib.util.spec_from_file_location("moon_proto_python_oracle", PYTHON_ORACLE)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load oracle module: {PYTHON_ORACLE}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_fixture_text(path: Path) -> str:
    return path.read_text(encoding="utf-8") if path.exists() else ""


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def compare_json_subset(actual: Any, expected: Any, path: str = "$") -> list[str]:
    if isinstance(expected, dict):
        if not isinstance(actual, dict):
            return [f"{path}: expected object, got {type(actual).__name__}"]
        errors: list[str] = []
        for key, expected_value in expected.items():
            if key not in actual:
                errors.append(f"{path}.{key}: missing")
            else:
                errors.extend(compare_json_subset(actual[key], expected_value, f"{path}.{key}"))
        return errors
    if actual != expected:
        return [f"{path}: expected {expected!r}, got {actual!r}"]
    return []


def parsed_message_dict(oracle_module: Any, class_function: str, data: bytes) -> dict[str, Any]:
    message_class = getattr(oracle_module, class_function)()
    message = message_class()
    message.ParseFromString(data)
    return oracle_module.json_format.MessageToDict(message, preserving_proto_field_name=True)


def run_case(case: ConformanceCase, fixtures_dir: Path, oracle_module: Any) -> CaseResult:
    bin_path = fixtures_dir / f"{case.fixture}.bin"
    hex_path = fixtures_dir / f"{case.fixture}.hex"
    json_path = fixtures_dir / f"{case.fixture}.json"
    try:
        oracle_fn: Callable[[], tuple[bytes, str, str]] = getattr(oracle_module, case.oracle_function)
        expected_bin, expected_hex, expected_json = oracle_fn()
        actual_bin = bin_path.read_bytes()
        actual_hex = read_fixture_text(hex_path)
        actual_json = read_fixture_text(json_path)

        failures: list[str] = []
        semantic_binary_note = ""
        if actual_bin != expected_bin:
            if case.allow_binary_semantic_equivalence and case.message_class_function:
                actual_dict = parsed_message_dict(oracle_module, case.message_class_function, actual_bin)
                expected_dict = parsed_message_dict(oracle_module, case.message_class_function, expected_bin)
                if actual_dict == expected_dict:
                    semantic_binary_note = "binary order accepted by parsed semantic equivalence; "
                else:
                    failures.append(f"{display_path(bin_path)} differs from Python protobuf oracle")
            else:
                failures.append(f"{display_path(bin_path)} differs from Python protobuf oracle")
        if actual_hex != expected_hex:
            if not case.allow_binary_semantic_equivalence:
                failures.append(f"{display_path(hex_path)} differs from Python protobuf oracle")
        if bytes.fromhex(actual_hex.strip()) != actual_bin:
            failures.append("hex fixture does not decode to the binary fixture")
        if actual_json != expected_json:
            failures.append(f"{display_path(json_path)} differs from Python protobuf oracle")
        try:
            parsed_json = json.loads(actual_json)
        except json.JSONDecodeError as exc:
            parsed_json = None
            failures.append(f"JSON fixture is invalid JSON: {exc}")
        if parsed_json is not None:
            failures.extend(compare_json_subset(parsed_json, case.required_json))

        digest = hashlib.sha256(actual_bin).hexdigest()
        details = (
            f"{case.feature}; {semantic_binary_note}bytes={len(actual_bin)}; sha256={digest[:16]}; "
            f"fixtures={bin_path.name},{hex_path.name},{json_path.name}"
        )
        if failures:
            details = "; ".join(failures)
        return CaseResult(
            name=case.name,
            fixture=case.fixture,
            category=case.category,
            feature=case.feature,
            ok=not failures,
            details=details,
            axes=case.axes,
            sha256=digest,
            size=len(actual_bin),
        )
    except Exception as exc:
        return CaseResult(
            name=case.name,
            fixture=case.fixture,
            category=case.category,
            feature=case.feature,
            ok=False,
            details=str(exc),
            axes=case.axes,
        )


def copy_fixture_triplet(source_dir: Path, target_dir: Path, fixture: str) -> None:
    target_dir.mkdir(parents=True, exist_ok=True)
    for suffix in (".bin", ".hex", ".json"):
        shutil.copy2(source_dir / f"{fixture}{suffix}", target_dir / f"{fixture}{suffix}")


def apply_negative_mutation(fixtures_dir: Path, fixture: str, mutation: str) -> None:
    if mutation == "hex_mismatch":
        (fixtures_dir / f"{fixture}.hex").write_text("00\n", encoding="utf-8")
    elif mutation == "json_missing_required_evidence":
        (fixtures_dir / f"{fixture}.json").write_text("{}\n", encoding="utf-8")
    elif mutation == "missing_bin":
        (fixtures_dir / f"{fixture}.bin").unlink()
    elif mutation == "corrupt_bin":
        (fixtures_dir / f"{fixture}.bin").write_bytes(b"\x00")
        (fixtures_dir / f"{fixture}.hex").write_text("00\n", encoding="utf-8")
    else:
        raise ValueError(f"unknown negative mutation: {mutation}")


def run_negative_case(
    negative: NegativeMutationCase,
    cases_by_name: dict[str, ConformanceCase],
    fixtures_dir: Path,
    oracle_module: Any,
) -> CaseResult:
    base_case = cases_by_name[negative.base_case]
    with tempfile.TemporaryDirectory(prefix="moon_proto_conformance_negative_") as tmp:
        mutated_dir = Path(tmp)
        copy_fixture_triplet(fixtures_dir, mutated_dir, base_case.fixture)
        apply_negative_mutation(mutated_dir, base_case.fixture, negative.mutation)
        observed = run_case(base_case, mutated_dir, oracle_module)
    ok = not observed.ok
    details = (
        f"expected rejection observed via {negative.mutation}: {observed.details}"
        if ok
        else f"mutation was unexpectedly accepted via {negative.mutation}: {observed.details}"
    )
    return CaseResult(
        name=negative.name,
        fixture=base_case.fixture,
        category="negative-self-check",
        feature=negative.feature,
        ok=ok,
        details=details,
        axes=negative.axes,
        sha256=observed.sha256,
        size=observed.size,
    )


def evaluate_coverage_gates(results: list[CaseResult], include_negative: bool = True) -> list[CoverageGate]:
    gates: list[CoverageGate] = []
    for axis, minimum in COVERAGE_REQUIREMENTS.items():
        if not include_negative and axis in {"negative", "fixture-integrity"}:
            continue
        matching = [result for result in results if result.ok and axis in result.axes]
        count = len(matching)
        gates.append(CoverageGate(
            name=f"coverage:{axis}",
            axis=axis,
            min_count=minimum,
            ok=count >= minimum,
            details=f"{count} passing case(s) for axis {axis}; required >= {minimum}",
        ))
    return gates


def markdown_cell(text: str) -> str:
    return str(text).replace("|", "\\|").replace("\n", "<br>")


def conformance_report(results: list[CaseResult], gates: list[CoverageGate]) -> str:
    ok = all(result.ok for result in results) and all(gate.ok for gate in gates)
    lines = [
        "# Moon Proto Lab conformance-lite report",
        "",
        f"- Generated at: `{datetime.now(timezone.utc).isoformat()}`",
        f"- Overall status: **{'PASS' if ok else 'FAIL'}**",
        f"- Cases: `{sum(1 for result in results if result.ok)}/{len(results)}` passing",
        "- Oracle: Python `google.protobuf` dynamic descriptors; Go oracle is run separately in CI against the same fixtures.",
        "",
        "| Case | Category | Fixture | Status | Evidence |",
        "| --- | --- | --- | --- | --- |",
    ]
    for result in results:
        lines.append(
            f"| {markdown_cell(result.name)} | {markdown_cell(result.category)} | "
            f"{markdown_cell(result.fixture)} | {'PASS' if result.ok else 'FAIL'} | {markdown_cell(result.details)} |"
        )
    lines.extend([
        "",
        "## Coverage gates",
        "",
        "| Gate | Axis | Minimum | Status | Details |",
        "| --- | --- | --- | --- | --- |",
    ])
    for gate in gates:
        lines.append(
            f"| {markdown_cell(gate.name)} | {markdown_cell(gate.axis)} | {gate.min_count} | "
            f"{'PASS' if gate.ok else 'FAIL'} | {markdown_cell(gate.details)} |"
        )
    lines.extend([
        "",
        "## Coverage axes",
        "",
        "- proto3 scalar, repeated and packed repeated fields;",
        "- bytes/base64 and protobuf JSON 64-bit integer strings;",
        "- map fields with string and int64 keys;",
        "- oneof JSON selection;",
        "- 32-bit numeric boundary values;",
        "- float/double finite and special JSON values.",
        "- negative mutation self-checks for fixture corruption, missing artifacts and JSON evidence loss.",
        "",
    ])
    return "\n".join(lines)


def result_json(results: list[CaseResult], gates: list[CoverageGate]) -> dict[str, Any]:
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "overall_status": "PASS" if all(result.ok for result in results) and all(gate.ok for gate in gates) else "FAIL",
        "case_count": len(results),
        "passing_count": sum(1 for result in results if result.ok),
        "oracle": "python google.protobuf dynamic descriptors; go oracle checked separately",
        "coverage_gates": [
            {
                "name": gate.name,
                "axis": gate.axis,
                "min_count": gate.min_count,
                "status": "PASS" if gate.ok else "FAIL",
                "details": gate.details,
            }
            for gate in gates
        ],
        "cases": [
            {
                "name": result.name,
                "fixture": result.fixture,
                "category": result.category,
                "feature": result.feature,
                "axes": list(result.axes),
                "status": "PASS" if result.ok else "FAIL",
                "details": result.details,
                "sha256": result.sha256,
                "size": result.size,
            }
            for result in results
        ],
    }


def xml_escape(text: str) -> str:
    return html.escape(str(text), quote=True)


def write_junit(path: Path, results: list[CaseResult], gates: list[CoverageGate]) -> None:
    failures = sum(1 for result in results if not result.ok) + sum(1 for gate in gates if not gate.ok)
    test_count = len(results) + len(gates)
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<testsuite name="moon-proto-lab.conformance-lite" tests="{test_count}" failures="{failures}">',
    ]
    for result in results:
        lines.append(f'  <testcase name="{xml_escape(result.name)}">')
        if not result.ok:
            lines.append(
                f'    <failure message="{xml_escape(result.details.splitlines()[0] if result.details else "failed")}">'
                + xml_escape(result.details)
                + '</failure>'
            )
        lines.append('  </testcase>')
    for gate in gates:
        lines.append(f'  <testcase name="{xml_escape(gate.name)}">')
        if not gate.ok:
            lines.append(
                f'    <failure message="{xml_escape(gate.details)}">'
                + xml_escape(gate.details)
                + '</failure>'
            )
        lines.append('  </testcase>')
    lines.append('</testsuite>')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate a protobuf conformance-lite evidence report")
    parser.add_argument("--fixtures-dir", default=str(FIXTURES), help="fixture directory; defaults to tests/fixtures")
    parser.add_argument("--report", help="write Markdown report")
    parser.add_argument("--json-out", help="write machine-readable JSON result")
    parser.add_argument("--junit-out", help="write JUnit XML result")
    parser.add_argument("--skip-negative-self-checks", action="store_true", help="only run positive oracle fixtures")
    args = parser.parse_args(argv)

    fixtures_dir = Path(args.fixtures_dir)
    oracle_module = load_python_oracle_module()
    results = [run_case(case, fixtures_dir, oracle_module) for case in CASES]
    if not args.skip_negative_self_checks:
        cases_by_name = {case.name: case for case in CASES}
        results.extend(
            run_negative_case(negative, cases_by_name, fixtures_dir, oracle_module)
            for negative in NEGATIVE_MUTATIONS
        )
    gates = evaluate_coverage_gates(results, include_negative=not args.skip_negative_self_checks)
    ok = all(result.ok for result in results) and all(gate.ok for gate in gates)

    if args.report:
        report = Path(args.report)
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(conformance_report(results, gates), encoding="utf-8")
        print(f"report: {args.report}")
    if args.json_out:
        out = Path(args.json_out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(result_json(results, gates), indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"json: {args.json_out}")
    if args.junit_out:
        write_junit(Path(args.junit_out), results, gates)
        print(f"junit: {args.junit_out}")

    print("Moon Proto Lab conformance-lite: " + ("PASS" if ok else "FAIL"))
    for result in results:
        print(f"- {result.name}: {'PASS' if result.ok else 'FAIL'} - {result.details.splitlines()[0] if result.details else ''}")
    print("coverage gates: " + ("PASS" if all(gate.ok for gate in gates) else "FAIL"))
    for gate in gates:
        print(f"- {gate.name}: {'PASS' if gate.ok else 'FAIL'} - {gate.details}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
