import unittest
from check_xcresult import validate


class XCTestResultTests(unittest.TestCase):
    def test_modern_result(self):
        self.assertIn("24 passed", validate({"totalTestCount": 24, "passedTests": 24, "failedTests": 0}))

    def test_legacy_result(self):
        self.assertIn("24 passed", validate({"metrics": {"testsCount": {"_value": "24"}}}))

    def test_zero_or_all_skipped_is_not_success(self):
        for total, skipped in [(0, 0), (9, 9)]:
            with self.assertRaises(ValueError):
                validate({"totalTestCount": total, "passedTests": 0, "failedTests": 0, "skippedTests": skipped})

    def test_nonzero_failure_is_rejected(self):
        with self.assertRaises(ValueError):
            validate({"totalTestCount": 25, "passedTests": 24, "failedTests": 1})


if __name__ == "__main__":
    unittest.main()
