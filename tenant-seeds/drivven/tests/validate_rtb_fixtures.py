#!/usr/bin/env python3
"""Validate Drivven's candidate RTB calculation against synthetic fixtures.

This tenant-owned test encodes candidate business, tax, and schedule behavior.
Passing it does not constitute legal, accounting, tax, or activation approval.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP, getcontext
from pathlib import Path
from typing import Any

getcontext().prec = 60


def round_minor(value: Decimal) -> int:
    return int(value.quantize(Decimal("1"), rounding=ROUND_HALF_UP))


def calculate_rtb(inputs: dict[str, Any]) -> dict[str, Any]:
    initial = inputs["initial_payment_total_minor"]
    brokerage = round_minor(Decimal(initial) * Decimal("0.70"))
    down = initial - brokerage
    taxable_fees = sum(
        row["amount_minor"]
        for row in inputs.get("fees", [])
        if row.get("taxable") and row.get("financed")
    )
    non_taxable_fees = sum(
        row["amount_minor"]
        for row in inputs.get("fees", [])
        if not row.get("taxable") and row.get("financed")
    )
    vehicle_after = max(
        inputs["vehicle_cash_price_minor"]
        - down
        - inputs.get("eligible_trade_in_credit_minor", 0),
        0,
    )
    consideration = vehicle_after + taxable_fees
    vehicle_gst = round_minor(Decimal(consideration) * Decimal("0.05"))
    vehicle_qst = round_minor(Decimal(consideration) * Decimal("0.09975"))
    brokerage_gst = round_minor(Decimal(brokerage) * Decimal("0.05"))
    brokerage_qst = round_minor(Decimal(brokerage) * Decimal("0.09975"))
    principal = (
        vehicle_after
        + taxable_fees
        + vehicle_gst
        + vehicle_qst
        + non_taxable_fees
        + inputs.get("trade_in_lien_payoff_minor", 0)
        + brokerage_gst
        + brokerage_qst
    )

    frequency = inputs["payment_frequency"]
    periods = 52 if frequency == "weekly" else 26
    period_days = 7 if frequency == "weekly" else 14
    count = inputs["duration_months"] * periods // 12
    periodic_rate = Decimal(inputs["annual_rate_bps"]) / Decimal(10000) / Decimal(periods)
    if periodic_rate == 0:
        regular = round_minor(Decimal(principal) / Decimal(count))
    else:
        regular = round_minor(
            Decimal(principal)
            * periodic_rate
            / (Decimal(1) - (Decimal(1) + periodic_rate) ** (-count))
        )

    opening = principal
    schedule: list[dict[str, Any]] = []
    signature = date.fromisoformat(inputs["signature_date"])
    total_interest = 0
    total_payments = 0
    for number in range(1, count + 1):
        interest = round_minor(Decimal(opening) * periodic_rate)
        if number == count:
            principal_part = opening
            payment = principal_part + interest
        else:
            payment = regular
            principal_part = payment - interest
            if principal_part > opening:
                principal_part = opening
                payment = principal_part + interest
        opening -= principal_part
        total_interest += interest
        total_payments += payment
        schedule.append(
            {
                "payment_number": number,
                "due_date": (signature + timedelta(days=period_days * number)).isoformat(),
                "payment_minor": payment,
                "principal_minor": principal_part,
                "interest_minor": interest,
                "remaining_balance_minor": opening,
            }
        )

    return {
        "brokerage_fee_base_minor": brokerage,
        "capital_down_payment_minor": down,
        "taxable_financed_fees_minor": taxable_fees,
        "non_taxable_financed_fees_minor": non_taxable_fees,
        "vehicle_price_after_capital_and_trade_in_minor": vehicle_after,
        "vehicle_taxable_consideration_minor": consideration,
        "vehicle_gst_minor": vehicle_gst,
        "vehicle_qst_minor": vehicle_qst,
        "brokerage_gst_minor": brokerage_gst,
        "brokerage_qst_minor": brokerage_qst,
        "net_capital_financed_minor": principal,
        "periods_per_year": periods,
        "number_of_payments": count,
        "first_payment_date": schedule[0]["due_date"],
        "regular_payment_minor": regular,
        "total_schedule_payments_minor": total_payments,
        "total_interest_minor": total_interest,
        "first_three_schedule_rows": schedule[:3],
        "final_schedule_row": schedule[-1],
        "final_payment_adjustment_minor": schedule[-1]["payment_minor"] - regular,
        "ending_balance_minor": opening,
    }


def validate_fixtures(root: Path) -> list[str]:
    errors: list[str] = []
    fixture_root = root / "tenant-seeds/drivven/formulas/rtb/tests"
    fixtures = sorted(fixture_root.glob("*.json"))
    if not fixtures:
        return [f"{fixture_root.relative_to(root)}: no fixtures found"]

    for path in fixtures:
        data = json.loads(path.read_text(encoding="utf-8"))
        actual = calculate_rtb(data["input"])
        for key, expected in data["expected"].items():
            if actual.get(key) != expected:
                errors.append(
                    f"{path.relative_to(root)}: {key} expected {expected!r}, "
                    f"calculated {actual.get(key)!r}"
                )
        if (
            actual["brokerage_fee_base_minor"] + actual["capital_down_payment_minor"]
            != data["input"]["initial_payment_total_minor"]
        ):
            errors.append(f"{path.relative_to(root)}: initial payment split invariant failed")
        if actual["ending_balance_minor"] != 0:
            errors.append(f"{path.relative_to(root)}: ending balance is not zero")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", nargs="?", default=str(Path(__file__).resolve().parents[3]))
    args = parser.parse_args()
    root = Path(args.root).resolve()
    errors = validate_fixtures(root)
    payload = {
        "name": "drivven_candidate_rtb_formula_invariants",
        "status": "pass" if not errors else "fail",
        "details": errors,
    }
    print(json.dumps(payload, indent=2))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
