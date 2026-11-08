#!/usr/bin/env python3
"""check_cases.py: the gate on the frozen eval set.

    python3 -I evals/check_cases.py [--cases-dir evals/cases] [--min-per-task 20]

Checks every case file under the cases dir:
  - the file is YAML with the required keys and a known task
  - `id` matches the file name and is unique across the set
  - `input.schema` exists and loads; `input.project`, if given, exists (both relative to evals/)
  - every source table a case names exists in its schema
  - every column an assertion names exists in the schema or is declared `derived` on that model
  - every `missing_inputs` entry names something the schema does NOT have (that is the point)
  - `validators` are known scripts
  - at least --min-per-task cases per task
  - no case request appears in the training set (training/data/requests.sha256, when it exists)

Exit 0 when every check passes, 1 otherwise, with one line per finding. Needs PyYAML.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    print("check_cases: PyYAML is required (pip install pyyaml, or use the dbt venv's python)")
    sys.exit(2)

KNOWN_TASKS = {"dbt-bq", "composer-dag", "cloudrun-job"}
KNOWN_VALIDATORS = {"dbt_lint", "dbt_parse", "dag_import", "container", "dbt_sandbox"}
MATERIALIZATIONS = {"view", "table", "incremental", "ephemeral"}
REQUIRED = ("id", "task", "request", "input", "expect", "validators")
ID_RE = re.compile(r"^(dbt-bq|composer-dag|cloudrun-job)-\d{3}$")


def norm(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def load_schema(path: Path) -> dict[str, set[str]]:
    data = json.loads(path.read_text())
    return {t["name"]: {c["name"] for c in t["columns"]} for t in data["tables"]}


def check_case(path: Path, root: Path, evals_root: Path, findings: list[str]) -> dict | None:
    rel = path.relative_to(root)
    try:
        case = yaml.safe_load(path.read_text())
    except yaml.YAMLError as e:
        findings.append(f"{rel}: not valid YAML: {e}")
        return None
    if not isinstance(case, dict):
        findings.append(f"{rel}: top level is not a mapping")
        return None
    for k in REQUIRED:
        if k not in case:
            findings.append(f"{rel}: missing key '{k}'")
    if any(k not in case for k in REQUIRED):
        return None

    cid = case["id"]
    if not ID_RE.match(str(cid)):
        findings.append(f"{rel}: id '{cid}' is not <task>-NNN")
    if path.stem != cid:
        findings.append(f"{rel}: file name does not match id '{cid}'")
    if case["task"] not in KNOWN_TASKS:
        findings.append(f"{rel}: unknown task '{case['task']}'")
    if not str(cid).startswith(case["task"]):
        findings.append(f"{rel}: id '{cid}' does not start with its task '{case['task']}'")
    if not isinstance(case["request"], str) or len(case["request"].strip()) < 20:
        findings.append(f"{rel}: request is missing or too short to be a real request")

    inp = case["input"]
    schema: dict[str, set[str]] | None = None
    if not isinstance(inp, dict) or "schema" not in inp:
        findings.append(f"{rel}: input.schema is required")
    else:
        spath = (
            (evals_root / inp["schema"])
            if not Path(inp["schema"]).is_absolute()
            else Path(inp["schema"])
        )
        if not spath.is_file():
            findings.append(f"{rel}: input.schema '{inp['schema']}' does not exist")
        else:
            try:
                schema = load_schema(spath)
            except (json.JSONDecodeError, KeyError, TypeError) as e:
                findings.append(
                    f"{rel}: input.schema '{inp['schema']}' is not a schema export: {e}"
                )
        if "project" in inp and not (evals_root / inp["project"]).is_dir():
            findings.append(f"{rel}: input.project '{inp['project']}' does not exist")

    bad_validators = set(case["validators"]) - KNOWN_VALIDATORS
    if bad_validators:
        findings.append(f"{rel}: unknown validators {sorted(bad_validators)}")

    exp = case["expect"]
    if not isinstance(exp, dict):
        findings.append(f"{rel}: expect is not a mapping")
        return case

    if schema is not None:
        for src in exp.get("sources", []):
            for t in src.get("tables", []):
                if t not in schema:
                    findings.append(f"{rel}: expect.sources names table '{t}', not in the schema")
        for m in exp.get("models", []):
            name = m.get("name", "?")
            if "materialized" in m and m["materialized"] not in MATERIALIZATIONS:
                findings.append(
                    f"{rel}: model {name}: unknown materialization '{m['materialized']}'"
                )
            if m.get("materialized") == "incremental":
                if "unique_key" not in m:
                    findings.append(f"{rel}: model {name}: incremental without unique_key")
                if m.get("incremental_strategy") != "merge":
                    findings.append(
                        f"{rel}: model {name}: incremental_strategy must be merge (the Culvert way)"
                    )
            derived = set(m.get("derived", []))
            known_cols = set().union(*schema.values()) | derived
            for src_tbl in m.get("sources", []):
                tbl = src_tbl.split(".")[-1]
                if tbl not in schema:
                    findings.append(f"{rel}: model {name}: source '{src_tbl}' not in the schema")
            for col in m.get("columns_required", []):
                if col not in known_cols:
                    findings.append(
                        f"{rel}: model {name}: column '{col}' is not in the schema "
                        "and not declared derived"
                    )
            for col in m.get("tests", {}):
                if col not in known_cols:
                    findings.append(
                        f"{rel}: model {name}: tested column '{col}' is not in the schema "
                        "and not declared derived"
                    )
        for mi in exp.get("missing_inputs", []):
            tbl, _, col = str(mi).partition(".")
            if tbl in schema and (not col or col in schema[tbl]):
                findings.append(
                    f"{rel}: missing_inputs '{mi}' exists in the schema, so it is not missing"
                )
    return case


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases-dir", default=None, help="default: evals/cases next to this script")
    ap.add_argument("--min-per-task", type=int, default=20)
    ap.add_argument(
        "--training-hashes", default=None, help="default: training/data/requests.sha256"
    )
    args = ap.parse_args()

    here = Path(__file__).resolve().parent
    cases_dir = Path(args.cases_dir).resolve() if args.cases_dir else here / "cases"
    hashes_path = (
        Path(args.training_hashes)
        if args.training_hashes
        else here.parent / "training" / "data" / "requests.sha256"
    )

    findings: list[str] = []
    files = sorted(cases_dir.rglob("*.yaml"))
    if not files:
        findings.append(f"no case files under {cases_dir}")
    seen: dict[str, Path] = {}
    per_task: dict[str, int] = {}
    requests: list[tuple[str, str]] = []
    for f in files:
        case = check_case(f, cases_dir, here, findings)
        if case is None:
            continue
        cid = str(case["id"])
        if cid in seen:
            findings.append(
                f"{f.relative_to(cases_dir)}: duplicate id '{cid}' "
                f"(also {seen[cid].relative_to(cases_dir)})"
            )
        seen[cid] = f
        per_task[case["task"]] = per_task.get(case["task"], 0) + 1
        requests.append((cid, norm(case["request"])))

    for task, n in sorted(per_task.items()):
        if n < args.min_per_task:
            findings.append(f"task {task}: {n} cases, fewer than {args.min_per_task}")

    if hashes_path.is_file():
        train = {line.strip() for line in hashes_path.read_text().splitlines() if line.strip()}
        for cid, req in requests:
            if hashlib.sha256(req.encode()).hexdigest() in train:
                findings.append(f"{cid}: its request is in the training set ({hashes_path})")
        leak_note = f"leakage checked against {len(train)} training hashes"
    else:
        leak_note = "leakage not checked: no training set yet"

    for line in findings:
        print(f"FAIL {line}")
    total = sum(per_task.values())
    summary = ", ".join(f"{t}={n}" for t, n in sorted(per_task.items())) or "none"
    print(f"check_cases: {total} case(s) [{summary}], {len(findings)} finding(s); {leak_note}")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
