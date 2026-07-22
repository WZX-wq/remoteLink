#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path


MAIN_BUNDLE_ID = "com.kunqiong.remotelink"
BROADCAST_BUNDLE_ID = "com.kunqiong.remotelink.broadcast"
TARGET_BUNDLES = (MAIN_BUNDLE_ID, BROADCAST_BUNDLE_ID)
CONFIGURATION_BLOCK = re.compile(
    r"(?ms)^(?P<header>\t\t[A-Za-z0-9]+ /\* [^\n]+ \*/ = \{\n)(?P<body>.*?^\t\t\};\n)"
)
PRODUCT_BUNDLE_ID = re.compile(
    r"(?m)^\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = (?P<bundle>[^;]+);\n"
)
CODE_SIGN_STYLE = re.compile(r"(?m)^\t\t\t\tCODE_SIGN_STYLE = [^;]+;\n")
PROVISIONING_PROFILE = re.compile(
    r"(?m)^\t\t\t\tPROVISIONING_PROFILE(?:_SPECIFIER)? = [^;]+;\n"
)
CODE_SIGN_IDENTITY = re.compile(
    r"(?m)^\t\t\t\t(?:\"?CODE_SIGN_IDENTITY(?:\[[^\]]+\])?\"?) = [^;]+;\n"
)
DEVELOPMENT_TEAM = re.compile(
    r"(?m)^(?P<indent>\t\t\t\t)DEVELOPMENT_TEAM = [^;]+;\n"
)


def quote_pbx_value(value):
    return '"{}"'.format(value.replace("\\", "\\\\").replace('"', '\\"'))


def configure_project(project_text, team_id, profiles):
    configured_counts = {bundle_id: 0 for bundle_id in TARGET_BUNDLES}
    project_text = CODE_SIGN_IDENTITY.sub("", project_text)

    def configure_block(match):
        body = match.group("body")
        bundle_match = PRODUCT_BUNDLE_ID.search(body)
        if bundle_match is None:
            return match.group(0)

        bundle_id = bundle_match.group("bundle").strip().strip('"')
        if bundle_id not in profiles:
            return match.group(0)

        body = CODE_SIGN_STYLE.sub("", body)
        body = PROVISIONING_PROFILE.sub("", body)
        team_match = DEVELOPMENT_TEAM.search(body)
        if team_match is None:
            raise ValueError(
                f"Missing DEVELOPMENT_TEAM for the {bundle_id} build configuration."
            )

        indent = team_match.group("indent")
        signing_settings = (
            f"{indent}DEVELOPMENT_TEAM = {team_id};\n"
            f"{indent}CODE_SIGN_STYLE = Manual;\n"
            f'{indent}CODE_SIGN_IDENTITY = "Apple Distribution";\n'
            f'{indent}"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";\n'
            f"{indent}PROVISIONING_PROFILE_SPECIFIER = {quote_pbx_value(profiles[bundle_id])};\n"
        )
        body = DEVELOPMENT_TEAM.sub(signing_settings, body, count=1)
        configured_counts[bundle_id] += 1
        return match.group("header") + body

    configured_text = CONFIGURATION_BLOCK.sub(configure_block, project_text)
    missing_bundles = [
        bundle_id for bundle_id, count in configured_counts.items() if count == 0
    ]
    if missing_bundles:
        raise ValueError(
            "No Xcode build configuration was found for: " + ", ".join(missing_bundles)
        )

    return configured_text, configured_counts


def parse_args():
    parser = argparse.ArgumentParser(
        description="Configure manual iOS archive signing in a CI project copy."
    )
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--main-profile", required=True)
    parser.add_argument("--broadcast-profile", required=True)
    args = parser.parse_args()

    if not args.project.is_file():
        parser.error(f"Xcode project file does not exist: {args.project}")
    if re.fullmatch(r"[A-Z0-9]{10}", args.team_id) is None:
        parser.error("--team-id must be a 10-character Apple team identifier.")
    if not args.main_profile.strip() or not args.broadcast_profile.strip():
        parser.error("Provisioning profile names must not be empty.")
    return args


def main():
    args = parse_args()
    profiles = {
        MAIN_BUNDLE_ID: args.main_profile,
        BROADCAST_BUNDLE_ID: args.broadcast_profile,
    }

    try:
        project_text = args.project.read_text(encoding="utf-8")
        configured_text, configured_counts = configure_project(
            project_text, args.team_id, profiles
        )
    except ValueError as error:
        raise SystemExit(f"error: {error}") from error

    args.project.write_text(configured_text, encoding="utf-8")
    print(
        "Configured manual signing for "
        f"{configured_counts[MAIN_BUNDLE_ID]} main and "
        f"{configured_counts[BROADCAST_BUNDLE_ID]} broadcast build configurations."
    )


if __name__ == "__main__":
    main()
