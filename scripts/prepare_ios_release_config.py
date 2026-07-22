#!/usr/bin/env python3
"""Validate the non-secret Dart defines required by an App Store iOS build."""

from __future__ import annotations

import json
import os
import sys
from collections.abc import Mapping
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen


class ReleaseConfigError(ValueError):
    """Raised when an App Store build would omit a required user-facing flow."""


_required_url_names = (
    "KQ_PRIVACY_POLICY_URL",
    "KQ_ACCOUNT_DELETE_URL",
    "KQ_IOS_IAP_VERIFY_URL",
)
_direct_payment_enabled_values = {"1", "true", "yes", "on"}
_direct_payment_disabled_values = {"", "0", "false", "no", "off"}
_endpoint_probe_statuses = {200, 400, 401, 403, 422}


def _require_https_url(values: Mapping[str, str], name: str) -> str:
    value = str(values.get(name, "")).strip()
    parsed = urlparse(value)
    if not value or parsed.scheme != "https" or not parsed.netloc:
        raise ReleaseConfigError(f"{name} must be a complete HTTPS URL.")
    return value


def _require_product_mapping(values: Mapping[str, str]) -> str:
    raw = str(values.get("KQ_IOS_IAP_PRODUCTS", "")).strip()
    try:
        mapping = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ReleaseConfigError(
            "KQ_IOS_IAP_PRODUCTS must be a JSON object mapping server package IDs "
            "to App Store product IDs."
        ) from error

    if not isinstance(mapping, dict) or not mapping:
        raise ReleaseConfigError("KQ_IOS_IAP_PRODUCTS must contain at least one product.")

    product_ids: set[str] = set()
    for package_id, product_id in mapping.items():
        package_text = str(package_id).strip()
        if not package_text or not isinstance(product_id, str) or not product_id.strip():
            raise ReleaseConfigError(
                "Each KQ_IOS_IAP_PRODUCTS entry needs a non-empty package ID and product ID."
            )
        normalized_product_id = product_id.strip()
        if normalized_product_id in product_ids:
            raise ReleaseConfigError(
                "KQ_IOS_IAP_PRODUCTS cannot map multiple packages to one product ID."
            )
        product_ids.add(normalized_product_id)
    return raw


def validate_release_config(values: Mapping[str, str] | None = None) -> dict[str, str]:
    """Return validated Dart defines without printing their values to CI logs."""

    environment = os.environ if values is None else values
    direct_payment = str(environment.get("KQ_IOS_INTERNAL_DIRECT_PAYMENT", "")).strip().lower()
    if direct_payment in _direct_payment_enabled_values:
        raise ReleaseConfigError(
            "KQ_IOS_INTERNAL_DIRECT_PAYMENT must be disabled for an App Store/TestFlight build."
        )
    if direct_payment not in _direct_payment_disabled_values:
        raise ReleaseConfigError(
            "KQ_IOS_INTERNAL_DIRECT_PAYMENT must be empty or an explicit false value."
        )

    config = {name: _require_https_url(environment, name) for name in _required_url_names}
    config["KQ_IOS_IAP_PRODUCTS"] = _require_product_mapping(environment)
    return config


def probe_release_endpoints(config: Mapping[str, str], opener=urlopen) -> None:
    """Confirm authenticated release endpoints are routed before spending CI time."""

    for name in ("KQ_ACCOUNT_DELETE_URL", "KQ_IOS_IAP_VERIFY_URL"):
        request = Request(
            config[name],
            data=b"{}",
            method="POST",
            headers={"Content-Type": "application/json", "Accept": "application/json"},
        )
        try:
            response = opener(request, timeout=10)
            status = getattr(response, "status", None)
            if status is None:
                status = response.getcode()
            status = int(status)
        except HTTPError as error:
            status = error.code
        except (URLError, TimeoutError) as error:
            raise ReleaseConfigError(
                f"{name} could not be reached from the release builder."
            ) from error

        if status not in _endpoint_probe_statuses:
            raise ReleaseConfigError(
                f"{name} returned HTTP {status}; deploy the authenticated POST route before release."
            )


def endpoint_probe_is_skipped(values: Mapping[str, str] | None = None) -> bool:
    """Return whether a manually triggered test build explicitly skips probing."""

    environment = os.environ if values is None else values
    raw = str(environment.get("KQ_SKIP_ENDPOINT_PROBE", "")).strip().lower()
    if raw in _direct_payment_enabled_values:
        return True
    if raw in _direct_payment_disabled_values:
        return False
    raise ReleaseConfigError(
        "KQ_SKIP_ENDPOINT_PROBE must be empty or an explicit true/false value."
    )


def main() -> int:
    try:
        config = validate_release_config()
        if endpoint_probe_is_skipped():
            print(
                "Endpoint reachability probe skipped by explicit manual test-build input.",
                file=sys.stderr,
            )
        else:
            probe_release_endpoints(config)
    except ReleaseConfigError as error:
        print(f"iOS App Store release configuration error: {error}", file=sys.stderr)
        return 1
    print("iOS App Store release configuration is valid.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
