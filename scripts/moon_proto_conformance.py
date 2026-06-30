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
import sys
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
    sha256: str = ""
    size: int = 0


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
    ),
    ConformanceCase(
        name="proto3_32bit_numeric_boundaries",
        fixture="numbers32",
        category="binary+json",
        feature="uint32/int32/sint32/fixed32/sfixed32 boundary values",
        oracle_function="numbers32_oracle_values",
        required_json={"u": 4294967295, "i": -1, "s": -2, "f": 4294967295, "sf": -3},
    ),
    ConformanceCase(
        name="proto3_float_double_roundtrip",
        fixture="floats",
        category="binary+json",
        feature="float and double finite numeric values",
        oracle_function="floats_oracle_values",
        required_json={"f": 1.5, "d": -2.25},
    ),
    ConformanceCase(
        name="proto3_float_special_json_strings",
        fixture="float_specials",
        category="binary+json",
        feature='NaN, Infinity and -Infinity protobuf JSON string mapping',
        oracle_function="float_specials_oracle_values",
        required_json={"f_nan": "NaN", "f_inf": "Infinity", "d_neg_inf": "-Infinity"},
    ),
]


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
                    failures.append(f"{bin_path.relative_to(ROOT)} differs from Python protobuf oracle")
            else:
                failures.append(f"{bin_path.relative_to(ROOT)} differs from Python protobuf oracle")
        if actual_hex != expected_hex:
            if not case.allow_binary_semantic_equivalence:
                failures.append(f"{hex_path.relative_to(ROOT)} differs from Python protobuf oracle")
        if bytes.fromhex(actual_hex.strip()) != actual_bin:
            failures.append("hex fixture does not decode to the binary fixture")
        if actual_json != expected_json:
            failures.append(f"{json_path.relative_to(ROOT)} differs from Python protobuf oracle")
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
        )


def markdown_cell(text: str) -> str:
    return str(text).replace("|", "\\|").replace("\n", "<br>")


def conformance_report(results: list[CaseResult]) -> str:
    ok = all(result.ok for result in results)
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
        "## Coverage axes",
        "",
        "- proto3 scalar, repeated and packed repeated fields;",
        "- bytes/base64 and protobuf JSON 64-bit integer strings;",
        "- map fields with string and int64 keys;",
        "- oneof JSON selection;",
        "- 32-bit numeric boundary values;",
        "- float/double finite and special JSON values.",
        "",
    ])
    return "\n".join(lines)


def result_json(results: list[CaseResult]) -> dict[str, Any]:
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "overall_status": "PASS" if all(result.ok for result in results) else "FAIL",
        "case_count": len(results),
        "passing_count": sum(1 for result in results if result.ok),
        "oracle": "python google.protobuf dynamic descriptors; go oracle checked separately",
        "cases": [
            {
                "name": result.name,
                "fixture": result.fixture,
                "category": result.category,
                "feature": result.feature,
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


def write_junit(path: Path, results: list[CaseResult]) -> None:
    failures = sum(1 for result in results if not result.ok)
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<testsuite name="moon-proto-lab.conformance-lite" tests="{len(results)}" failures="{failures}">',
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
    lines.append('</testsuite>')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate a protobuf conformance-lite evidence report")
    parser.add_argument("--fixtures-dir", default=str(FIXTURES), help="fixture directory; defaults to tests/fixtures")
    parser.add_argument("--report", help="write Markdown report")
    parser.add_argument("--json-out", help="write machine-readable JSON result")
    parser.add_argument("--junit-out", help="write JUnit XML result")
    args = parser.parse_args(argv)

    fixtures_dir = Path(args.fixtures_dir)
    oracle_module = load_python_oracle_module()
    results = [run_case(case, fixtures_dir, oracle_module) for case in CASES]
    ok = all(result.ok for result in results)

    if args.report:
        report = Path(args.report)
        report.parent.mkdir(parents=True, exist_ok=True)
        report.write_text(conformance_report(results), encoding="utf-8")
        print(f"report: {args.report}")
    if args.json_out:
        out = Path(args.json_out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(result_json(results), indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(f"json: {args.json_out}")
    if args.junit_out:
        write_junit(Path(args.junit_out), results)
        print(f"junit: {args.junit_out}")

    print("Moon Proto Lab conformance-lite: " + ("PASS" if ok else "FAIL"))
    for result in results:
        print(f"- {result.name}: {'PASS' if result.ok else 'FAIL'} - {result.details.splitlines()[0] if result.details else ''}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
