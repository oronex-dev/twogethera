import unittest

import validate_release_config as config


class ReleaseConfigProjectBindingTest(unittest.TestCase):
    def test_ref_must_be_exactly_twenty_lowercase_alphanumeric_characters(self):
        self.assertTrue(config.valid_project_ref("projectref1234567890"))
        for value in ("", "Projectref1234567890", "project-ref1234567", "x" * 21):
            with self.subTest(value=value):
                self.assertFalse(config.valid_project_ref(value))

    def test_url_must_match_approved_project_ref(self):
        ref = "projectref1234567890"
        self.assertTrue(
            config.project_url_matches_ref(f"https://{ref}.supabase.co", ref)
        )
        self.assertFalse(
            config.project_url_matches_ref(
                "https://anotherref1234567890.supabase.co", ref
            )
        )
        self.assertFalse(config.project_url_matches_ref("http://127.0.0.1:54321", ref))
        self.assertFalse(
            config.project_url_matches_ref(f"https://{ref}.supabase.co/path", ref)
        )

    def test_release_config_fails_closed_on_project_mismatch_or_missing_ref(self):
        env = {
            "APP_ENV": "staging",
            "SUPABASE_PROJECT_REF": "projectref1234567890",
            "SUPABASE_URL": "https://projectref1234567890.supabase.co",
            "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_" + "p" * 40,
            "APP_WEB_URL": "https://staging.twogethera.com",
        }
        self.assertTrue(config.valid_configuration(env))

        mismatch = dict(env, SUPABASE_URL="https://anotherref1234567890.supabase.co")
        self.assertFalse(config.valid_configuration(mismatch))

        missing = dict(env)
        del missing["SUPABASE_PROJECT_REF"]
        self.assertFalse(config.valid_configuration(missing))


if __name__ == "__main__":
    unittest.main()
