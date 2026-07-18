#!/usr/bin/env python3
"""Regression tests for TestFlight-only Dart define validation."""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("prepare_ios_release_config.py")
SPEC = importlib.util.spec_from_file_location("prepare_ios_release_config", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load {SCRIPT_PATH}")
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class IosReleaseConfigTests(unittest.TestCase):
    def setUp(self) -> None:
        self.values = {
            "KQ_PRIVACY_POLICY_URL": "https://www.example.com/privacy",
            "KQ_ACCOUNT_DELETE_URL": "https://api.example.com/account/delete",
            "KQ_IOS_IAP_PRODUCTS": '{"1":"com.example.remote.member.month"}',
            "KQ_IOS_IAP_VERIFY_URL": "https://api.example.com/membership/apple/verify",
        }

    def test_accepts_complete_https_configuration(self) -> None:
        config = MODULE.validate_release_config(self.values)

        self.assertEqual(
            config["KQ_IOS_IAP_PRODUCTS"],
            self.values["KQ_IOS_IAP_PRODUCTS"],
        )

    def test_rejects_missing_required_setting(self) -> None:
        values = dict(self.values)
        values.pop("KQ_ACCOUNT_DELETE_URL")

        with self.assertRaises(MODULE.ReleaseConfigError):
            MODULE.validate_release_config(values)

    def test_rejects_non_https_service_url(self) -> None:
        values = dict(self.values)
        values["KQ_IOS_IAP_VERIFY_URL"] = "http://api.example.com/verify"

        with self.assertRaises(MODULE.ReleaseConfigError):
            MODULE.validate_release_config(values)

    def test_rejects_invalid_product_mapping(self) -> None:
        values = dict(self.values)
        values["KQ_IOS_IAP_PRODUCTS"] = '{"1":""}'

        with self.assertRaises(MODULE.ReleaseConfigError):
            MODULE.validate_release_config(values)

    def test_rejects_direct_payment_for_app_store_build(self) -> None:
        values = dict(self.values)
        values["KQ_IOS_INTERNAL_DIRECT_PAYMENT"] = "true"

        with self.assertRaises(MODULE.ReleaseConfigError):
            MODULE.validate_release_config(values)

    def test_endpoint_probe_accepts_an_authenticated_route(self) -> None:
        config = MODULE.validate_release_config(self.values)

        MODULE.probe_release_endpoints(
            config,
            opener=lambda _request, timeout: _Response(401),
        )

    def test_endpoint_probe_rejects_a_missing_route(self) -> None:
        config = MODULE.validate_release_config(self.values)

        with self.assertRaises(MODULE.ReleaseConfigError):
            MODULE.probe_release_endpoints(
                config,
                opener=lambda _request, timeout: _Response(404),
            )


class _Response:
    def __init__(self, status: int) -> None:
        self.status = status


if __name__ == "__main__":
    unittest.main()
