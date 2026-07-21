import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


CONFIGURATOR = Path(__file__).with_name("configure-ios-archive-signing.py")
TEAM_ID = "G4C3ADW2F4"
MAIN_BUNDLE_ID = "com.kunqiong.remotelink"
BROADCAST_BUNDLE_ID = "com.kunqiong.remotelink.broadcast"
MAIN_PROFILE = "RemoteLink Development 20260721"
BROADCAST_PROFILE = "RemoteLink Broadcast Development 20260721"


def build_configuration(identifier, bundle_id, profile_name):
    return (
        f"\t\t{identifier} /* Release */ = {{\n"
        "\t\t\tisa = XCBuildConfiguration;\n"
        "\t\t\tbuildSettings = {\n"
        f"\t\t\t\tDEVELOPMENT_TEAM = {TEAM_ID};\n"
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        f"\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = \"{profile_name}\";\n"
        f"\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {bundle_id};\n"
        "\t\t\t};\n"
        "\t\t\tname = Release;\n"
        "\t\t};\n"
    )


class ConfigureArchiveSigningTest(unittest.TestCase):
    def test_binds_each_target_to_its_development_profile(self):
        source = "/* Begin XCBuildConfiguration section */\n"
        source += build_configuration("AAA", MAIN_BUNDLE_ID, "Old Main Profile")
        source += build_configuration("BBB", BROADCAST_BUNDLE_ID, "Old Broadcast Profile")
        source += "/* End XCBuildConfiguration section */\n"

        with tempfile.TemporaryDirectory() as temp_dir:
            project = Path(temp_dir) / "project.pbxproj"
            project.write_text(source, encoding="utf-8")
            result = subprocess.run(
                [
                    sys.executable,
                    str(CONFIGURATOR),
                    "--project",
                    str(project),
                    "--team-id",
                    TEAM_ID,
                    "--main-profile",
                    MAIN_PROFILE,
                    "--broadcast-profile",
                    BROADCAST_PROFILE,
                ],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            configured = project.read_text(encoding="utf-8")

        self.assertEqual(configured.count("CODE_SIGN_STYLE = Manual;"), 2)
        self.assertIn(
            f'PROVISIONING_PROFILE_SPECIFIER = "{MAIN_PROFILE}";', configured
        )
        self.assertIn(
            f'PROVISIONING_PROFILE_SPECIFIER = "{BROADCAST_PROFILE}";', configured
        )
        self.assertNotIn("Old Main Profile", configured)
        self.assertNotIn("Old Broadcast Profile", configured)


if __name__ == "__main__":
    unittest.main()
